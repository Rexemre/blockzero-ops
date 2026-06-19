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
#include <fstream>
#include <iostream>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#elif defined(__APPLE__)
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <unistd.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace {

constexpr const char* kMinerVersion = "0.7.6";
// High cap so big servers (EPYC / Threadripper, often 64-128+ threads) use all
// their cores. The actual count is still clamped to hardware_concurrency below.
constexpr int kMaxThreads = 256;

// Fast mode builds a ~2080 MiB RandomX dataset. Add the per-epoch cache (256 MiB),
// per-thread scratchpads and OS headroom: require ~3 GiB available before we try.
// On a smaller box the dataset alloc/init thrashes swap and freezes the grind
// threads (0 H/s, stuck on the "light" label) - genuine light mode is far better.
constexpr uint64_t kFastModeMinMiB = 3072;

// Physically available RAM in MiB, or 0 when it cannot be determined.
uint64_t AvailableMemoryMiB() {
#ifdef _WIN32
    MEMORYSTATUSEX st;
    st.dwLength = sizeof(st);
    if (GlobalMemoryStatusEx(&st)) {
        return static_cast<uint64_t>(st.ullAvailPhys) / (1024ULL * 1024ULL);
    }
    return 0;
#elif defined(__APPLE__)
    // No cheap "available" metric; total RAM is a safe proxy on Apple Silicon.
    uint64_t total = 0;
    size_t len = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &len, nullptr, 0) == 0) {
        return total / (1024ULL * 1024ULL);
    }
    return 0;
#else
    std::ifstream meminfo("/proc/meminfo");
    std::string key, unit;
    uint64_t value = 0;
    while (meminfo >> key >> value >> unit) {
        if (key == "MemAvailable:") return value / 1024ULL; // kB -> MiB
    }
    return 0;
#endif
}

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

constexpr uint8_t kRxProbeKey[32] = {
    0x42, 0x6c, 0x6f, 0x63, 0x6b, 0x5a, 0x65, 0x72, 0x6f, 0x2d, 0x52, 0x61, 0x6e,
    0x64, 0x6f, 0x6d, 0x58, 0x2d, 0x62, 0x6f, 0x6f, 0x74, 0x73, 0x74, 0x72, 0x61,
    0x70, 0x2d, 0x6b, 0x65, 0x79, 0x76,
};

bool ProbeJitDirect(randomx_flags flags) {
    if (!(flags & RANDOMX_FLAG_JIT)) return true;
    randomx_cache* cache = randomx_alloc_cache(flags);
    if (!cache) return false;
    randomx_init_cache(cache, kRxProbeKey, sizeof(kRxProbeKey));
    randomx_vm* vm = randomx_create_vm(flags, cache, nullptr);
    if (!vm) {
        randomx_release_cache(cache);
        return false;
    }
    uint8_t hash[32];
    uint8_t header[80]{};
    randomx_calculate_hash(vm, header, sizeof(header), hash);
    randomx_destroy_vm(vm);
    randomx_release_cache(cache);
    return true;
}

bool ProbeJitRuntime(randomx_flags flags) {
#ifndef _WIN32
    if (!(flags & RANDOMX_FLAG_JIT)) return true;
    const pid_t pid = fork();
    if (pid == 0) {
        _exit(ProbeJitDirect(flags) ? 0 : 1);
    }
    if (pid < 0) return false;
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return false;
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
#else
    return ProbeJitDirect(flags);
#endif
}

randomx_vm* CreateMiningVm(randomx_flags flags, randomx_cache* cache, randomx_dataset* dataset) {
    if (!cache) return nullptr;
    randomx_vm* vm = nullptr;
    // Prefer a large-page scratchpad (consistent with the dataset; avoids TLB
    // misses on the hot 2 MiB scratchpad). Falls back to normal pages if huge
    // pages are exhausted.
    const randomx_flags lp = static_cast<randomx_flags>(flags | RANDOMX_FLAG_LARGE_PAGES);
    if (dataset) {
        vm = randomx_create_vm(static_cast<randomx_flags>(lp | RANDOMX_FLAG_FULL_MEM), nullptr, dataset);
        if (!vm) {
            vm = randomx_create_vm(static_cast<randomx_flags>(flags | RANDOMX_FLAG_FULL_MEM), nullptr, dataset);
        }
    }
    if (!vm) {
        vm = randomx_create_vm(flags, cache, nullptr);
    }
    if (!vm && (flags & RANDOMX_FLAG_JIT)) {
        const randomx_flags soft =
            static_cast<randomx_flags>(flags & ~(RANDOMX_FLAG_JIT | RANDOMX_FLAG_SECURE));
        if (dataset) {
            vm = randomx_create_vm(static_cast<randomx_flags>(soft | RANDOMX_FLAG_FULL_MEM), nullptr,
                                   dataset);
        }
        if (!vm) vm = randomx_create_vm(soft, cache, nullptr);
    }
    return vm;
}

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
            if (!ProbeJitRuntime(flags)) {
                std::cout << "RandomX JIT unavailable here - using interpreter (slower but stable).\n";
                std::cout.flush();
                flags = static_cast<randomx_flags>(flags & ~(RANDOMX_FLAG_JIT | RANDOMX_FLAG_SECURE));
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
std::mutex g_apply_mu;
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
        bool large_pages = true;
        randomx_dataset* raw =
            randomx_alloc_dataset(static_cast<randomx_flags>(flags | RANDOMX_FLAG_LARGE_PAGES));
        if (!raw) {
            large_pages = false;
            raw = randomx_alloc_dataset(flags);
        }
        if (!raw) {
            std::cout << "Fast mode unavailable (needs ~2.3 GB free RAM) - staying in light mode.\n";
            std::cout.flush();
            g_fast_mode = false; // don't retry every epoch
            g_dataset_building.store(false);
            return;
        }
        if (large_pages) {
            std::cout << "RandomX dataset using HUGE PAGES - full speed.\n";
        } else {
            std::cout << "RandomX dataset on normal 4K pages - this is SLOW on many-core CPUs.\n"
                         "  For full speed reserve huge pages once, then restart the miner:\n"
                         "    sudo sysctl -w vm.nr_hugepages=1280\n";
        }
        std::cout.flush();

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
    std::lock_guard<std::mutex> apply_lock(g_apply_mu);

    auto prefix = pool::HexDecode(mj.header_prefix_hex);
    auto key = pool::HexDecode(mj.rx_key_hex);
    if (prefix.size() < 76 || key.size() != 32) {
        std::cerr << "Ignored invalid job " << mj.job_id << " (header=" << prefix.size()
                  << "B key=" << key.size() << "B)\n";
        return false;
    }

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

    std::cout << "New job: " << mj.job_id << " - mining.\n";
    std::cout.flush();
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
            vm = CreateMiningVm(flags, cache_holder->ptr, vm_dataset ? vm_dataset->ptr : nullptr);
            if (!vm) {
                vm_dataset.reset();
                std::cerr << "RandomX VM init failed on thread " << thread_id << "\n";
                std::cerr.flush();
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
        for (int i = 0; i < 100 && !g_stop.load(); ++i) {  // ~10s report interval
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
        bool have_job;
        {
            std::lock_guard<std::mutex> lock(g_job_mu);
            have_job = static_cast<bool>(g_job.cache);
        }
        const uint64_t acc = g_client ? g_client->AcceptedShares() : 0;
        const uint64_t rej = g_client ? g_client->RejectedShares() : 0;

        // Avoid the confusing "0 H/s (light)" during start-up. Tell the user
        // exactly what the miner is doing so nobody thinks it is broken.
        if (!have_job) {
            std::printf("Connected - waiting for first job from pool...\n");
            std::fflush(stdout);
            continue;
        }
        // Always print the live hashrate so the user can see real numbers (and
        // so wrapper scripts can detect that mining is alive). Label the mode:
        // building the dataset, light, or full fast mode.
        const char* mode;
        if (g_fast_mode && !fast && g_dataset_building.load()) {
            mode = "building dataset, fast soon";
        } else {
            mode = fast ? "fast" : "light";
        }
        std::printf("Hashrate: %.0f H/s (%s) | shares: %llu accepted",
                    rate, mode, static_cast<unsigned long long>(acc));
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

    // Don't attempt the 2 GB fast-mode dataset on machines that can't hold it.
    // Trying anyway thrashes swap and freezes mining at 0 H/s on small VPS.
    if (g_fast_mode) {
        const uint64_t avail = AvailableMemoryMiB();
        if (avail > 0 && avail < kFastModeMinMiB) {
            std::cout << "Only ~" << avail << " MiB RAM available - using light mode "
                         "(fast mode needs ~3 GB). Slower but stable.\n";
            std::cout.flush();
            g_fast_mode = false;
        }
    }

    if (worker.find("bz1") != 0 || worker.find('.') == std::string::npos) {
        std::fprintf(stderr, "Worker must be bz1ADDRESS.rigname (got: %s)\n", worker.c_str());
        std::fprintf(stderr, "Delete miner.conf and run again, or fix BZ1_ADDRESS.\n");
        ix::uninitNetSystem();
        PauseBeforeExit(1);
        return 1;
    }

    const randomx_flags diag_flags = MiningFlags();
    const uint64_t diag_ram = AvailableMemoryMiB();
    std::cout << "bz-pool-miner v" << kMinerVersion << "\n";
    std::cout << "Connecting to pool...\n";
    std::cout << "Pool:    " << url << "\n";
    std::cout << "Worker:  " << worker << "\n";
    std::cout << "Threads: " << threads << "\n";
    std::cout << "Mode:    " << (g_fast_mode ? "fast (RandomX dataset)" : "light") << "\n";
    std::cout << "RandomX: JIT=" << ((diag_flags & RANDOMX_FLAG_JIT) ? "on" : "off")
              << " HARD_AES=" << ((diag_flags & RANDOMX_FLAG_HARD_AES) ? "on" : "off")
              << " | RAM avail: " << (diag_ram ? std::to_string(diag_ram) + " MiB" : "unknown")
              << " | cores: " << std::thread::hardware_concurrency() << "\n";
    std::cout << "Config:  " << conf_path << "\n";
    if (threads > 32) {
        std::cout << "Tip: RandomX fast mode is usually fastest at your PHYSICAL core count, "
                     "not every SMT thread. If the hashrate looks low, try fewer threads "
                     "(e.g. -Threads = number of physical cores).\n";
    }
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
