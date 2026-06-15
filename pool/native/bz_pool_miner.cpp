// bz-pool-miner — native BLOZ pool miner (RandomX + Stratum/WSS)
// Started by blockzero-ops: mine-mainnet.ps1 -Pool (Windows) / mine-pool.sh (Linux, macOS)
//
// Mining modes:
//   fast  (default) — full ~2 GB RandomX dataset, ~10x faster. Falls back to
//                     light automatically when memory is short.
//   light           — 256 MB cache only (--light or MODE=light in miner.conf)

#include "miner_config.hpp"
#include "pow_util.hpp"
#include "stratum_client.hpp"

#include <ixwebsocket/IXNetSystem.h>
#include <randomx.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace {

constexpr int kMaxThreads = 64;

struct RxCache {
    randomx_cache* ptr{nullptr};
    explicit RxCache(randomx_cache* cache) : ptr(cache) {}
    ~RxCache() {
        if (ptr) randomx_release_cache(ptr);
    }
};

struct RxDataset {
    randomx_dataset* ptr{nullptr};
    explicit RxDataset(randomx_dataset* ds) : ptr(ds) {}
    ~RxDataset() {
        if (ptr) randomx_release_dataset(ptr);
    }
};

randomx_flags MiningFlags() {
    // Determined once: JIT is ~10x faster than the interpreter. On Windows the
    // SECURE flag keeps JIT pages W^X-safe (plain JIT crashes under DEP).
    static const randomx_flags cached = [] {
        randomx_flags flags = randomx_get_flags();
#ifdef _WIN32
        if (flags & RANDOMX_FLAG_JIT) {
            flags = static_cast<randomx_flags>(flags | RANDOMX_FLAG_SECURE);
        }
#endif
        if (flags & RANDOMX_FLAG_JIT) {
            randomx_cache* probe = randomx_alloc_cache(flags);
            if (probe) {
                randomx_release_cache(probe);
            } else {
                // JIT allocation refused (hardened system) - interpreter fallback.
                flags = static_cast<randomx_flags>(
                    flags & ~(RANDOMX_FLAG_JIT | RANDOMX_FLAG_SECURE));
            }
        }
        return flags;
    }();
    return cached;
}

struct ActiveJob {
    std::string id;
    std::vector<uint8_t> header_prefix;
    uint8_t pool_target_be[32]{};
    randomx_flags flags{};
    std::shared_ptr<RxCache> cache;
    std::string rx_key_hex;
    uint64_t vm_generation{0}; // bumped when cache/dataset epoch changes
};

std::mutex g_job_mu;
ActiveJob g_job;

std::mutex g_ds_mu;
std::shared_ptr<RxDataset> g_dataset;
std::string g_dataset_key;
std::atomic<bool> g_dataset_building{false};

std::atomic<bool> g_stop{false};
std::atomic<uint64_t> g_hashes{0};
bool g_fast_mode = true;
int g_threads = 1;
pool::StratumClient* g_client{nullptr};

void BuildDatasetAsync(std::shared_ptr<RxCache> cache, std::string key_hex, randomx_flags flags) {
    std::thread([cache = std::move(cache), key_hex = std::move(key_hex), flags]() {
        randomx_dataset* raw =
            randomx_alloc_dataset(static_cast<randomx_flags>(flags | RANDOMX_FLAG_LARGE_PAGES));
        if (!raw) raw = randomx_alloc_dataset(flags);
        if (!raw) {
            std::cout << "Fast mode unavailable (needs ~2.3 GB free RAM) - staying in light mode.\n";
            std::cout.flush();
            g_fast_mode = false; // don't retry every epoch
            g_dataset_building.store(false);
            return;
        }

        std::cout << "Initializing RandomX dataset (fast mode, ~1 min, mining continues)...\n";
        std::cout.flush();
        const auto t0 = std::chrono::steady_clock::now();

        const unsigned long total = randomx_dataset_item_count();
        const int n = g_threads < 1 ? 1 : g_threads; // no std::max: windows.h defines a max macro
        std::vector<std::thread> workers;
        workers.reserve(n);
        const unsigned long chunk = total / n;
        for (int i = 0; i < n; ++i) {
            const unsigned long start = chunk * i;
            const unsigned long count = (i == n - 1) ? (total - start) : chunk;
            workers.emplace_back([raw, &cache, start, count]() {
                randomx_init_dataset(raw, cache->ptr, start, count);
            });
        }
        for (auto& w : workers) w.join();

        auto holder = std::make_shared<RxDataset>(raw);
        {
            std::lock_guard<std::mutex> lock(g_ds_mu);
            g_dataset = holder;
            g_dataset_key = key_hex;
        }
        {
            std::lock_guard<std::mutex> lock(g_job_mu);
            if (g_job.rx_key_hex == key_hex) ++g_job.vm_generation;
        }
        const double sec =
            std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        std::printf("Fast mode active (dataset ready in %.0fs).\n", sec);
        std::fflush(stdout);
        g_dataset_building.store(false);
    }).detach();
}

bool ApplyJob(const pool::MiningJob& mj) {
    auto prefix = pool::HexDecode(mj.header_prefix_hex);
    auto key = pool::HexDecode(mj.rx_key_hex);
    if (prefix.size() < 76 || key.size() != 32) {
        std::cerr << "Ignored invalid job " << mj.job_id << " (header=" << prefix.size()
                  << "B key=" << key.size() << "B)\n";
        return false;
    }

    std::cout << "New job: " << mj.job_id << " - mining.\n";
    std::cout.flush();

    // Reuse the existing RandomX cache when the key is unchanged. Cache init
    // takes seconds; jobs change every block but the key only every epoch.
    std::shared_ptr<RxCache> cache_holder;
    {
        std::lock_guard<std::mutex> lock(g_job_mu);
        if (g_job.cache && g_job.rx_key_hex == mj.rx_key_hex) {
            cache_holder = g_job.cache;
        }
    }

    const randomx_flags flags = MiningFlags();
    if (!cache_holder) {
        randomx_cache* raw_cache = randomx_alloc_cache(flags);
        if (!raw_cache) {
            std::cerr << "RandomX cache allocation failed (low memory?)\n";
            return false;
        }
        randomx_init_cache(raw_cache, key.data(), key.size());
        cache_holder = std::make_shared<RxCache>(raw_cache);
    }

    {
        std::lock_guard<std::mutex> lock(g_job_mu);
        const bool epoch_changed = g_job.rx_key_hex != mj.rx_key_hex;
        g_job.id = mj.job_id;
        g_job.header_prefix = std::move(prefix);
        pool::HexToTargetBe(mj.pool_target_hex, g_job.pool_target_be);
        if (epoch_changed || !g_job.cache) {
            g_job.flags = flags;
            g_job.cache = cache_holder;
            g_job.rx_key_hex = mj.rx_key_hex;
            ++g_job.vm_generation;
        }
    }

    // Kick off (or refresh) the fast-mode dataset for this epoch key.
    if (g_fast_mode) {
        bool need_build = false;
        {
            std::lock_guard<std::mutex> lock(g_ds_mu);
            need_build = (g_dataset_key != mj.rx_key_hex);
        }
        if (need_build && !g_dataset_building.exchange(true)) {
            BuildDatasetAsync(cache_holder, mj.rx_key_hex, flags);
        }
    }

    return true;
}

void GrindThread(int thread_id, int thread_count) {
    std::vector<uint8_t> header(80);
    uint8_t hash[32];
    randomx_vm* vm = nullptr;
    uint64_t vm_generation = UINT64_MAX;
    std::shared_ptr<RxCache> cache_holder;
    std::shared_ptr<RxDataset> vm_dataset; // must outlive the VM that uses it
    randomx_flags flags{};
    std::string key_hex;
    std::string cur_job;
    uint64_t nonce = static_cast<uint32_t>(thread_id);
    const uint64_t step = static_cast<uint64_t>(thread_count);

    while (!g_stop.load()) {
        std::string job_id;
        uint8_t pool_target_be[32]{};
        {
            std::lock_guard<std::mutex> lock(g_job_mu);
            if (!g_job.cache || g_job.header_prefix.size() < 76) {
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
                continue;
            }
            // VM rebuild only on epoch change or when the dataset became ready.
            if (g_job.vm_generation != vm_generation) {
                if (vm) {
                    randomx_destroy_vm(vm);
                    vm = nullptr;
                }
                vm_dataset.reset();
                flags = g_job.flags;
                cache_holder = g_job.cache;
                key_hex = g_job.rx_key_hex;
                vm_generation = g_job.vm_generation;
            }
            job_id = g_job.id;
            if (job_id != cur_job) {
                cur_job = job_id;
                std::memcpy(header.data(), g_job.header_prefix.data(), 76);
                nonce = static_cast<uint32_t>(thread_id);
            }
            std::memcpy(pool_target_be, g_job.pool_target_be, 32);
        }

        if (!vm) {
            {
                std::lock_guard<std::mutex> lock(g_ds_mu);
                if (g_dataset && g_dataset_key == key_hex) vm_dataset = g_dataset;
            }
            if (vm_dataset) {
                vm = randomx_create_vm(static_cast<randomx_flags>(flags | RANDOMX_FLAG_FULL_MEM),
                                       nullptr, vm_dataset->ptr);
            }
            if (!vm) {
                vm_dataset.reset();
                vm = randomx_create_vm(flags, cache_holder->ptr, nullptr);
            }
            if (!vm) {
                std::cerr << "RandomX VM init failed on thread " << thread_id << "\n";
                std::this_thread::sleep_for(std::chrono::milliseconds(250));
                continue;
            }
        }

        int done = 0;
        for (; done < 500 && !g_stop.load(); ++done) {
            const uint32_t n = static_cast<uint32_t>(nonce);
            std::memcpy(header.data() + 76, &n, 4);
            randomx_calculate_hash(vm, header.data(), header.size(), hash);

            if (pool::HashMeetsTarget(hash, pool_target_be)) {
                std::cout << "Share found (nonce=" << n << ") - submitting...\n";
                std::cout.flush();
                if (g_client) g_client->SubmitShare(job_id, n);
            }
            nonce += step;
        }
        g_hashes.fetch_add(static_cast<uint64_t>(done), std::memory_order_relaxed);
    }

    if (vm) randomx_destroy_vm(vm);
}

void ReportThread() {
    auto t0 = std::chrono::steady_clock::now();
    uint64_t last = 0;
    while (!g_stop.load()) {
        for (int i = 0; i < 300 && !g_stop.load(); ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        if (g_stop.load()) break;
        const uint64_t now_hashes = g_hashes.load(std::memory_order_relaxed);
        const auto now = std::chrono::steady_clock::now();
        const double sec = std::chrono::duration<double>(now - t0).count();
        if (sec <= 0) continue;
        const double rate = static_cast<double>(now_hashes - last) / sec;
        last = now_hashes;
        t0 = now;
        bool fast;
        {
            std::lock_guard<std::mutex> lock(g_ds_mu);
            fast = static_cast<bool>(g_dataset);
        }
        const uint64_t acc = g_client ? g_client->AcceptedShares() : 0;
        const uint64_t rej = g_client ? g_client->RejectedShares() : 0;
        std::printf("Hashrate: %.0f H/s (%s) | shares: %llu accepted",
                    rate, fast ? "fast" : "light",
                    static_cast<unsigned long long>(acc));
        if (rej > 0) std::printf(", %llu rejected", static_cast<unsigned long long>(rej));
        std::printf("\n");
        std::fflush(stdout);
    }
}

bool MatchesThreadsArg(const std::string& arg) {
    return arg == "-t" || arg == "--threads" || arg == "-Threads" || arg == "--Threads";
}

void PrintBlockZeroHint() {
    std::cerr << "\nThis miner is started by BlockZero (blockzero-ops).\n";
    std::cerr << "Windows:\n";
    std::cerr << "  cd blockzero-ops\\scripts\\mainnet\n";
    std::cerr << "  .\\mine-mainnet.ps1 -Pool\n";
    std::cerr << "Linux/macOS:\n";
    std::cerr << "  cd blockzero-ops/scripts/mainnet\n";
    std::cerr << "  ./mine-pool.sh\n\n";
}

void PrintUsage(const char* argv0) {
    std::fprintf(stderr,
        "Usage: %s -o pool_url -u bz1ADDR.rig [-Threads N] [--light]\n"
        "\n"
        "End users: run BlockZero pool mining instead:\n"
        "  Windows:     mine-mainnet.ps1 -Pool\n"
        "  Linux/macOS: mine-pool.sh\n"
        "\n"
        "  -Threads N   CPU threads (1-%d). Also: -t, --threads\n"
        "  --light      RandomX light mode (256 MB instead of ~2.3 GB RAM)\n",
        argv0, kMaxThreads);
}

} // namespace

int main(int argc, char* argv[]) {
    SetupConsole();

    if (!ix::initNetSystem()) {
        std::cerr << "Network init failed (WSAStartup).\n";
        PauseBeforeExit(1);
        return 1;
    }

    std::string url;
    std::string worker;
    std::string password = "x";
    int threads = 0;
    bool help = false;
    bool light = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if ((arg == "-o" || arg == "--url") && i + 1 < argc) url = argv[++i];
        else if ((arg == "-u" || arg == "--user") && i + 1 < argc) worker = argv[++i];
        else if ((arg == "-p" || arg == "--pass") && i + 1 < argc) password = argv[++i];
        else if (MatchesThreadsArg(arg) && i + 1 < argc) threads = std::atoi(argv[++i]);
        else if (arg == "--light" || arg == "-Light") light = true;
        else if (arg == "-h" || arg == "--help") help = true;
    }

    if (help) {
        PrintUsage(argv[0]);
        ix::uninitNetSystem();
        return 0;
    }

    MinerConfig cfg;
    const std::string conf_path = DefaultConfigPath();

    if (worker.empty()) {
        if (!LoadConfig(conf_path, cfg)) {
            PrintBlockZeroHint();
            ix::uninitNetSystem();
            PauseBeforeExit(1);
            return 1;
        }
        worker = BuildWorker(cfg);
        if (url.empty()) url = cfg.pool_url;
        if (threads <= 0) threads = ResolveThreads(cfg);
        if (cfg.mode == "light") light = true;
    } else {
        if (url.empty()) url = "wss://pool.bloz.org/stratum";
        if (threads <= 0) threads = ResolveThreads(cfg);
    }
    g_fast_mode = !light;

    // Clamp instead of erroring out - users should never see a hard failure
    // for asking for too many threads.
    if (threads < 1) threads = 1;
    if (threads > kMaxThreads) {
        std::cout << "Requested " << threads << " threads - capping at " << kMaxThreads << ".\n";
        threads = kMaxThreads;
    }
    const int cores = static_cast<int>(std::thread::hardware_concurrency());
    if (cores > 0 && threads > cores) {
        std::cout << "Note: " << threads << " threads on " << cores
                  << " logical cores - using " << cores << ".\n";
        threads = cores;
    }
    g_threads = threads;

    if (worker.find("bz1") != 0 || worker.find('.') == std::string::npos) {
        std::fprintf(stderr, "Worker must be bz1ADDRESS.rigname (got: %s)\n", worker.c_str());
        std::fprintf(stderr, "Delete miner.conf and run again, or fix BZ1_ADDRESS.\n");
        ix::uninitNetSystem();
        PauseBeforeExit(1);
        return 1;
    }

    std::cout << "Connecting to pool...\n";
    std::cout << "Pool:    " << url << "\n";
    std::cout << "Worker:  " << worker << "\n";
    std::cout << "Threads: " << threads << "\n";
    std::cout << "Mode:    " << (g_fast_mode ? "fast (RandomX dataset)" : "light") << "\n";
    std::cout << "Config:  " << conf_path << "\n";
    std::cout << "Press Ctrl+C to stop.\n\n";
    std::cout.flush();

    pool::StratumClient client(url, worker, password);
    g_client = &client;
    client.SetJobCallback([](const pool::MiningJob& job) { ApplyJob(job); });

    std::signal(SIGINT, [](int) { g_stop.store(true); });
    std::signal(SIGTERM, [](int) { g_stop.store(true); });

    client.Start(); // keeps retrying in the background even if first connect fails

    std::vector<std::thread> workers;
    workers.reserve(threads + 1);
    for (int t = 0; t < threads; ++t) {
        workers.emplace_back(GrindThread, t, threads);
    }
    workers.emplace_back(ReportThread);

    while (!g_stop.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    for (auto& w : workers) {
        if (w.joinable()) w.join();
    }

    client.Stop();
    {
        std::lock_guard<std::mutex> lock(g_job_mu);
        g_job.cache.reset();
    }
    {
        std::lock_guard<std::mutex> lock(g_ds_mu);
        g_dataset.reset();
    }

    std::cout << "\nMiner stopped.\n";
    std::cout.flush();
    ix::uninitNetSystem();
    return 0;
}
