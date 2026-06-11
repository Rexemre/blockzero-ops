#include "pow_util.hpp"

#include <cctype>

namespace pool {

std::vector<uint8_t> HexDecode(const std::string& hex) {
    std::vector<uint8_t> out;
    out.reserve(hex.size() / 2);
    auto nybble = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    for (size_t i = 0; i + 1 < hex.size(); i += 2) {
        int hi = nybble(hex[i]);
        int lo = nybble(hex[i + 1]);
        if (hi < 0 || lo < 0) continue;
        out.push_back(static_cast<uint8_t>((hi << 4) | lo));
    }
    return out;
}

void HexToTargetBe(const std::string& hex, uint8_t target_be[32]) {
    std::string h = hex;
    if (h.size() < 64) h = std::string(64 - h.size(), '0') + h;
    if (h.size() > 64) h = h.substr(h.size() - 64);
    for (int i = 0; i < 32; ++i) {
        auto nybble = [](char c) -> uint8_t {
            if (c >= '0' && c <= '9') return static_cast<uint8_t>(c - '0');
            if (c >= 'a' && c <= 'f') return static_cast<uint8_t>(c - 'a' + 10);
            if (c >= 'A' && c <= 'F') return static_cast<uint8_t>(c - 'A' + 10);
            return 0;
        };
        target_be[i] = static_cast<uint8_t>((nybble(h[i * 2]) << 4) | nybble(h[i * 2 + 1]));
    }
}

bool HashMeetsTarget(const uint8_t hash_le[32], const uint8_t target_be[32]) {
    for (int i = 0; i < 32; ++i) {
        const uint8_t hb = hash_le[31 - i];
        if (hb < target_be[i]) return true;
        if (hb > target_be[i]) return false;
    }
    return true;
}

} // namespace pool
