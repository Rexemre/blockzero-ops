#include "miner_config.hpp"



#include <algorithm>

#include <cctype>

#include <fstream>

#include <iostream>

#include <thread>



#ifdef _WIN32

#ifndef NOMINMAX

#define NOMINMAX

#endif

#include <windows.h>

#endif



namespace {



std::string Trim(std::string s) {

    auto not_space = [](unsigned char c) { return !std::isspace(c); };

    s.erase(s.begin(), std::find_if(s.begin(), s.end(), not_space));

    s.erase(std::find_if(s.rbegin(), s.rend(), not_space).base(), s.end());

    return s;

}



bool ParseKeyValue(const std::string& line, std::string& key, std::string& value) {

    if (line.empty() || line[0] == '#') return false;

    const auto pos = line.find('=');

    if (pos == std::string::npos) return false;

    key = Trim(line.substr(0, pos));

    value = Trim(line.substr(pos + 1));

    return !key.empty();

}



bool IsValidAddress(const std::string& addr) {

    if (addr.size() < 10 || addr.rfind("bz1", 0) != 0) return false;

    for (size_t i = 3; i < addr.size(); ++i) {

        const unsigned char c = static_cast<unsigned char>(addr[i]);

        if (!std::isalnum(c)) return false;

    }

    return true;

}

} // namespace

void SetupConsole() {
#ifdef _WIN32
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    if (out != INVALID_HANDLE_VALUE) {
        DWORD mode = 0;
        if (GetConsoleMode(out, &mode)) {
            SetConsoleMode(out, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
    }
#endif
}

void PauseBeforeExit(int exit_code) {
    if (exit_code == 0) return;
    std::cerr << "\nPress Enter to exit...\n";
    std::cerr.flush();
    std::cin.clear();
    std::string line;
    std::getline(std::cin, line);
}

std::string GetExeDirectory() {

#ifdef _WIN32

    char buf[MAX_PATH]{};

    const DWORD len = GetModuleFileNameA(nullptr, buf, MAX_PATH);

    if (len == 0 || len >= MAX_PATH) return ".";

    std::string path(buf, len);

    const auto pos = path.find_last_of("\\/");

    return pos == std::string::npos ? "." : path.substr(0, pos);

#else

    return ".";

#endif

}



std::string DefaultConfigPath() {

#ifdef _WIN32

    return GetExeDirectory() + "\\miner.conf";

#else

    return GetExeDirectory() + "/miner.conf";

#endif

}



bool LoadConfig(const std::string& path, MinerConfig& out) {

    std::ifstream in(path);

    if (!in) return false;



    MinerConfig cfg;

    std::string line;

    while (std::getline(in, line)) {

        std::string key, value;

        if (!ParseKeyValue(line, key, value)) continue;

        if (key == "POOL_URL") cfg.pool_url = value;

        else if (key == "BZ1_ADDRESS") cfg.bz1_address = value;

        else if (key == "WORKER_NAME") cfg.worker_name = value;

        else if (key == "THREADS") cfg.threads = std::atoi(value.c_str());

    }



    if (!IsValidAddress(cfg.bz1_address)) return false;

    if (cfg.worker_name.empty()) cfg.worker_name = "pc";

    if (cfg.pool_url.empty()) cfg.pool_url = "wss://pool.bloz.org/stratum";

    out = std::move(cfg);

    return true;

}



bool SaveConfig(const std::string& path, const MinerConfig& cfg) {

    std::ofstream out(path, std::ios::trunc);

    if (!out) return false;



    const int threads = ResolveThreads(cfg);

    out << "# BLOZ pool miner - saved next to bz-pool-miner.exe\n"
        << "# Edit BZ1_ADDRESS or THREADS anytime, then restart the miner.\n"

        << "POOL_URL=" << cfg.pool_url << "\n"

        << "BZ1_ADDRESS=" << cfg.bz1_address << "\n"

        << "WORKER_NAME=" << cfg.worker_name << "\n"

        << "THREADS=" << threads << "\n";

    return static_cast<bool>(out);

}



std::string BuildWorker(const MinerConfig& cfg) {

    return cfg.bz1_address + "." + cfg.worker_name;

}



int ResolveThreads(const MinerConfig& cfg) {
    if (cfg.threads > 0) return cfg.threads;
    int n = static_cast<int>(std::thread::hardware_concurrency());
    if (n < 1) n = 4;
    if (n > 16) n = 16;
    return n;
}


