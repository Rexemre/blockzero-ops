#pragma once

#include <atomic>
#include <functional>
#include <mutex>
#include <string>

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
    bool IsDisconnected() const;

private:
    void OnMessage(const std::string& line);
    void SendLine(const std::string& line);
    static std::string ExtractNotifyParam(const std::string& json, int index);

    std::string url_;
    std::string worker_;
    std::string password_;
    JobCallback on_job_;
    std::mutex send_mu_;
    int req_id_{1};
    void* ws_{nullptr}; // ix::WebSocket*
    std::atomic<bool> connected_{false};
    std::atomic<bool> disconnected_{false};
};

} // namespace pool
