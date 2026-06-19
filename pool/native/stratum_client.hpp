#pragma once

#include <atomic>
#include <functional>
#include <mutex>
#include <set>
#include <string>
#include <thread>

namespace pool {

struct MiningJob {
    std::string job_id;
    std::string header_prefix_hex;
    std::string rx_key_hex;
    std::string pool_target_hex;
    bool clean{false};
};

class StratumClient {
public:
    using JobCallback = std::function<void(const MiningJob&)>;

    StratumClient(std::string url, std::string worker, std::string password);
    ~StratumClient();

    void SetJobCallback(JobCallback cb);
    bool Start();
    void Stop();
    bool SubmitShare(const std::string& job_id, uint32_t nonce);
    bool IsConnected() const;

    uint64_t AcceptedShares() const { return accepted_.load(); }
    uint64_t RejectedShares() const { return rejected_.load(); }

private:
    void OnMessage(const std::string& raw);
    void ProcessLine(const std::string& line);
    void SendHello();
    void NoJobWatchdog();
    void SendLine(const std::string& line);
    void RunTcp(); // raw plain-TCP stratum transport (POSIX only)
    static std::string ExtractNotifyParam(const std::string& json, int index);

    std::string url_;
    std::string worker_;
    std::string password_;
    JobCallback on_job_;
    std::mutex send_mu_;
    std::mutex submit_mu_;
    std::set<int> submit_ids_;
    int req_id_{1};
    void* ws_{nullptr}; // ix::WebSocket*
    std::atomic<bool> connected_{false};
    std::atomic<uint64_t> jobs_received_{0};
    std::atomic<uint64_t> accepted_{0};
    std::atomic<uint64_t> rejected_{0};
    // Raw-TCP transport (used when the URL is stratum+tcp:// or tcp://). This
    // bypasses ixwebsocket entirely for environments where the WebSocket layer
    // misbehaves (some Linux/virtualized networks).
    bool tcp_mode_{false};
    std::atomic<long long> sock_{-1};
    std::atomic<bool> stop_{false};
    std::thread tcp_thread_;
};

} // namespace pool
