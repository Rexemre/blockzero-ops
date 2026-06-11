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

} // namespace

StratumClient::StratumClient(std::string url, std::string worker, std::string password)
    : url_(std::move(url)), worker_(std::move(worker)), password_(std::move(password)) {}

StratumClient::~StratumClient() { Stop(); }

void StratumClient::SetJobCallback(JobCallback cb) { on_job_ = std::move(cb); }

bool StratumClient::IsConnected() const { return connected_.load(); }

bool StratumClient::IsDisconnected() const { return disconnected_.load(); }

bool StratumClient::Start() {
    connected_.store(false);
    disconnected_.store(false);

    auto* ws = new ix::WebSocket();
    ws_ = ws;
    ws->setUrl(url_);
    ix::SocketTLSOptions tls;
    tls.caFile = "SYSTEM";
    ws->setTLSOptions(tls);
    ws->enableAutomaticReconnection();

    ws->setOnMessageCallback([this](const ix::WebSocketMessagePtr& msg) {
        if (msg->type == ix::WebSocketMessageType::Open) {
            connected_.store(true);
            disconnected_.store(false);
            std::cout << "Connected to pool.\n";
            std::cout.flush();
        } else if (msg->type == ix::WebSocketMessageType::Message) {
            OnMessage(msg->str);
        } else if (msg->type == ix::WebSocketMessageType::Error) {
            std::cerr << "Stratum error: " << msg->errorInfo.reason << std::endl;
            disconnected_.store(true);
        } else if (msg->type == ix::WebSocketMessageType::Close) {
            std::cerr << "Stratum connection closed." << std::endl;
            connected_.store(false);
            disconnected_.store(true);
        }
    });

    ws->start();
    for (int i = 0; i < 150 && !connected_.load() && !disconnected_.load(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    if (!connected_.load()) {
        std::cerr << "Failed to connect to pool: " << url_ << std::endl;
        std::cerr << "Check internet connection and firewall, then try again." << std::endl;
        ws->stop();
        delete ws;
        ws_ = nullptr;
        return false;
    }

    SendLine("{\"id\":" + std::to_string(req_id_++) + ",\"method\":\"mining.subscribe\",\"params\":[]}");
    SendLine("{\"id\":" + std::to_string(req_id_++) + ",\"method\":\"mining.authorize\",\"params\":[\"" +
             JsonEscape(worker_) + "\",\"" + JsonEscape(password_) + "\"]}");
    std::cout << "Subscribed and authorized. Waiting for work...\n";
    std::cout.flush();
    return true;
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
    char nonce_hex[16];
    std::snprintf(nonce_hex, sizeof(nonce_hex), "%08x", nonce);
    std::ostringstream oss;
    oss << "{\"id\":" << req_id_++ << ",\"method\":\"mining.submit\",\"params\":[\"" << worker_ << "\",\""
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

void StratumClient::OnMessage(const std::string& line) {
    if (line.find("mining.notify") == std::string::npos) return;
    MiningJob job;
    job.job_id = ExtractNotifyParam(line, 0);
    job.header_prefix_hex = ExtractNotifyParam(line, 1);
    job.rx_key_hex = ExtractNotifyParam(line, 2);
    job.pool_target_hex = ExtractNotifyParam(line, 4);
    const auto clean = ExtractNotifyParam(line, 7);
    job.clean = (clean == "true");
    if (job.job_id.empty() || job.header_prefix_hex.empty() || job.rx_key_hex.empty()) return;
    if (on_job_) on_job_(job);
}

} // namespace pool
