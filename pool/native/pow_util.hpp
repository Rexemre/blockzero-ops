#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace pool {

std::vector<uint8_t> HexDecode(const std::string& hex);
void HexToTargetBe(const std::string& hex, uint8_t target_be[32]);
bool HashMeetsTarget(const uint8_t hash_le[32], const uint8_t target_be[32]);

} // namespace pool
