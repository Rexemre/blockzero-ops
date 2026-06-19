#include "stratum_client.hpp"

#include <ixwebsocket/IXSocketTLSOptions.h>
#include <ixwebsocket/IXWebSocket.h>

#include <chrono>
#include <iostream>
#include <sstream>
#include <thread>

namespace pool {

namespace {

std::string JsonEscape(const std::string& s) {
    return s;
}

// Minimal "id":N extractor for stratum responses.
int ExtractId(const std::string& json) {
    auto pos = json.find("\"id\"");
    if (pos == std::string::npos) return -1;
    pos = json.find(':', pos);
    if (pos == std::string::npos) return -1;
    ++pos;
    while (pos < json.size() && json[pos] == ' ') ++pos;
    if (pos >= json.size() || !isdigit(static_cast<unsigned char>(json[pos]))) return -1;
    return std::atoi(json.c_str() + pos);
}

} // namespace

StratumClient::StratumClient(std::string url, std::string worker, std::string password)
    : url_(std::move(url)), worker_(std::move(worker)), password_(std::move(password)) {}

StratumClient::~StratumClient() { Stop(); }

void StratumClient::SetJobCallback(JobCallback cb) { on_job_ = std::move(cb); }

bool StratumClient::IsConnected() const { return connected_.load(); }

void StratumClient::SendHello() {
    // Each Stratum line must be its own TCP record. ixwebsocket may coalesce rapid
    // send() calls into one WebSocket frame; trailing newlines let the pool bridge
    // split them even when they arrive in a single frame.
    SendLine("{\"id\":" + std::to_string(req_id_++) + ",\"method\":\"mining.subscribe\",\"params\":[]}");
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    SendLine("{\"id\":" + std::to_string(req_id_++) + ",\"method\":\"mining.authorize\",\"params\":[\"" +
             JsonEscape(worker_) + "\",\"" + JsonEscape(password_) + "\"]}");
}

bool StratumClient::Start() {
    connected_.store(false);

    auto* ws = new ix::WebSocket();
    ws_ = ws;
    ws->setUrl(url_);
    ix::SocketTLSOptions tls;
    tls.caFile = "SYSTEM";
    ws->setTLSOptions(tls);
    // NOTE: do NOT disable permessage-deflate here. Disabling it made some
    // builds of ixwebsocket never surface the first mining.notify (the pool
    // sends the job immediately on subscribe, verified server-side), leaving the
    // miner stuck on "waiting for first job" and falling back to the slow Python
    // miner. ixwebsocket's default deflate path is well-tested and reliable.
    ws->enableAutomaticReconnection();
    ws->setMinWaitBetweenReconnectionRetries(2000);
    ws->setMaxWaitBetweenReconnectionRetries(30000);

    ws->setOnMessageCallback([this](const ix::WebSocketMessagePtr& msg) {
        if (msg->type == ix::WebSocketMessageType::Open) {
            const bool was_connected = connected_.exchange(true);
            std::cout << (was_connected ? "Reconnected to pool.\n" : "Connected to pool.\n");
            std::cout.flush();
            // Re-subscribe + authorize on every (re)connect so mining resumes
            // automatically after network drops or pool restarts.
            SendHello();
            // NOTE: no NoJobWatchdog here anymore. It spawned a new watchdog
            // thread on every (re)connect without stopping the old ones; on fast
            // many-core boxes the threads piled up and kept force-closing the
            // socket, so the connection never stayed up long enough to receive
            // the first job (endless reconnect churn, never mining). The pool now
            // sends a job immediately on both subscribe AND authorize, and
            // ixwebsocket already auto-reconnects on real drops - so just wait.
        } else if (msg->type == ix::WebSocketMessageType::Message) {
            OnMessage(msg->str);
        } else if (msg->type == ix::WebSocketMessageType::Error) {
            std::cerr << "Pool connection error: " << msg->errorInfo.reason
                      << " - retrying...\n";
            connected_.store(false);
        } else if (msg->type == ix::WebSocketMessageType::Close) {
            std::cerr << "Pool connection lost - reconnecting automatically...\n";
            connected_.store(false);
        }
    });

    ws->start();
    for (int i = 0; i < 300 && !connected_.load(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    if (!connected_.load()) {
        std::cerr << "Could not connect to pool within 30s: " << url_ << "\n";
        std::cerr << "Check internet connection and firewall. The miner keeps retrying.\n";
        // Keep the websocket alive - automatic reconnection continues in the
        // background and mining starts as soon as the pool is reachable.
    } else {
        std::cout << "Connected to pool - waiting for first job...\n";
        std::cout.flush();
    }
    return true;
}

void StratumClient::NoJobWatchdog() {
    int waited = 0;
    while (connected_.load() && jobs_received_.load() == 0) {
        std::this_thread::sleep_for(std::chrono::seconds(5));
        if (jobs_received_.load() != 0 || !connected_.load()) return;
        waited += 5;
        if (waited == 10) {
            std::cout << "No job yet - re-subscribing to pool...\n";
            std::cout.flush();
            SendHello();
        }
        if (waited >= 20) {
            std::cout << "Still no job - reconnecting to pool for fresh work...\n";
            std::cout.flush();
            // Force-close: ixwebsocket auto-reconnects, the Open callback runs
            // SendHello() again and starts a new watchdog.
            if (ws_) static_cast<ix::WebSocket*>(ws_)->close();
            return;
        }
    }
}

void StratumClient::Stop() {
    if (!ws_) return;
    auto* ws = static_cast<ix::WebSocket*>(ws_);
    ws->stop();
    delete ws;
    ws_ = nullptr;
    connected_.store(false);
}

void StratumClient::SendLine(const std::string& line) {
    if (!ws_) return;
    std::lock_guard<std::mutex> lock(send_mu_);
    static_cast<ix::WebSocket*>(ws_)->send(line + "\n");
}

bool StratumClient::SubmitShare(const std::string& job_id, uint32_t nonce) {
    if (!connected_.load()) return false;
    char nonce_hex[16];
    std::snprintf(nonce_hex, sizeof(nonce_hex), "%08x", nonce);
    int id;
    {
        std::lock_guard<std::mutex> lock(submit_mu_);
        id = req_id_++;
        submit_ids_.insert(id);
        if (submit_ids_.size() > 256) submit_ids_.erase(submit_ids_.begin());
    }
    std::ostringstream oss;
    oss << "{\"id\":" << id << ",\"method\":\"mining.submit\",\"params\":[\"" << worker_ << "\",\""
        << job_id << "\",\"" << nonce_hex << "\"]}";
    SendLine(oss.str());
    return true;
}

std::string StratumClient::ExtractNotifyParam(const std::string& json, int index) {
    auto method_pos = json.find("\"mining.notify\"");
    if (method_pos == std::string::npos) return {};
    auto params_pos = json.find("\"params\"", method_pos);
    if (params_pos == std::string::npos) return {};
    auto bracket = json.find('[', params_pos);
    if (bracket == std::string::npos) return {};

    int current = 0;
    size_t i = bracket + 1;
    while (i < json.size() && current <= index) {
        while (i < json.size() && (json[i] == ' ' || json[i] == ',')) ++i;
        if (i >= json.size()) break;
        if (json[i] == '"') {
            if (current == index) {
                auto end = json.find('"', i + 1);
                return json.substr(i + 1, end - i - 1);
            }
            auto end = json.find('"', i + 1);
            i = end + 1;
            ++current;
        } else if (json.substr(i, 4) == "true" || json.substr(i, 5) == "false") {
            if (current == index) {
                return json.substr(i, json.substr(i, 4) == "true" ? 4 : 5);
            }
            i += json.substr(i, 4) == "true" ? 4 : 5;
            ++current;
        } else {
            auto end = json.find_first_of(",]", i);
            if (current == index) return json.substr(i, end - i);
            i = end + 1;
            ++current;
        }
    }
    return {};
}

void StratumClient::ProcessLine(const std::string& line) {
    if (line.find("mining.notify") != std::string::npos) {
        MiningJob job;
        job.job_id = ExtractNotifyParam(line, 0);
        job.header_prefix_hex = ExtractNotifyParam(line, 1);
        job.rx_key_hex = ExtractNotifyParam(line, 2);
        job.pool_target_hex = ExtractNotifyParam(line, 4);
        const auto clean = ExtractNotifyParam(line, 7);
        job.clean = (clean == "true");
        if (job.job_id.empty() || job.header_prefix_hex.empty() || job.rx_key_hex.empty()) {
            std::cerr << "Ignored malformed mining.notify (missing job fields)\n";
            return;
        }
        jobs_received_.fetch_add(1, std::memory_order_relaxed);
        if (on_job_) {
            // RandomX init can take seconds; never block the websocket thread
            // (also keeps server ping/pong handling responsive).
            std::thread([cb = on_job_, job]() { cb(job); }).detach();
        }
        return;
    }

    // Track share accept/reject responses for submitted ids.
    const int id = ExtractId(line);
    if (id < 0) return;
    bool is_submit;
    {
        std::lock_guard<std::mutex> lock(submit_mu_);
        is_submit = submit_ids_.erase(id) > 0;
    }
    if (!is_submit) return;

    if (line.find("\"result\":true") != std::string::npos) {
        const auto n = accepted_.fetch_add(1) + 1;
        std::cout << "Share accepted (" << n << " total)\n";
        std::cout.flush();
    } else {
        rejected_.fetch_add(1);
        std::string reason = "rejected";
        auto err = line.find("\"error\":[");
        if (err != std::string::npos) {
            auto q1 = line.find('"', err + 9);
            if (q1 != std::string::npos) {
                auto q2 = line.find('"', q1 + 1);
                if (q2 != std::string::npos) reason = line.substr(q1 + 1, q2 - q1 - 1);
            }
        }
        std::cerr << "Share rejected: " << reason << "\n";
    }
}

void StratumClient::OnMessage(const std::string& raw) {
    // Pool may deliver multiple JSON lines in one WebSocket text frame.
    std::string line;
    line.reserve(raw.size());
    for (size_t i = 0; i < raw.size(); ++i) {
        const char c = raw[i];
        if (c == '\n' || c == '\r') {
            if (!line.empty()) {
                ProcessLine(line);
                line.clear();
            }
            continue;
        }
        if (c == '{' && !line.empty() && line.back() == '}') {
            ProcessLine(line);
            line.clear();
        }
        line += c;
    }
    if (!line.empty()) ProcessLine(line);
}

} // namespace pool
