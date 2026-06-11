#pragma once

#include <string>

struct MinerConfig {
    std::string pool_url = "wss://pool.bloz.org/stratum";
    std::string bz1_address;
    std::string worker_name = "pc";
    int threads = 0; // 0 = auto-detect
};

std::string GetExeDirectory();
std::string DefaultConfigPath();
bool LoadConfig(const std::string& path, MinerConfig& out);
bool SaveConfig(const std::string& path, const MinerConfig& cfg);
std::string BuildWorker(const MinerConfig& cfg);
int ResolveThreads(const MinerConfig& cfg);
void SetupConsole();
void PauseBeforeExit(int exit_code);
