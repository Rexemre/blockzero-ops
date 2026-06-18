"""Block Zero RandomX proof-of-work helpers."""
from __future__ import annotations

import os
import struct
import subprocess
import sys
from typing import Optional

# Early-chain bootstrap key (see pow_randomx.cpp / RandomXBootstrapKey()).
# Bitcoin uint256 SetHex reverses byte order vs literal hex.
RX_BOOTSTRAP_KEY_HEX = (
    "426c6f636b5a65726f2d52616e646f6d582d626f6f7473747261702d6b657976"
)
RX_BOOTSTRAP_KEY = bytes.fromhex(RX_BOOTSTRAP_KEY_HEX)[::-1]
RX_EPOCH_BLOCKS = 2048
RX_EPOCH_LAG = 64
POW_LIMIT = int(
    "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16
)

_NATIVE_HASH = os.environ.get(
    "BLOZ_POW_HASH",
    "/opt/blockzero-pool/bin/bz-pow-hash",
)


def _native_hash(key: bytes, header: bytes) -> Optional[bytes]:
    if len(key) != 32 or len(header) != 80:
        return None
    if not os.path.isfile(_NATIVE_HASH):
        return None
    try:
        proc = subprocess.run(
            [_NATIVE_HASH, key.hex(), header.hex()],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    out = (proc.stdout or "").strip().lower()
    if proc.returncode != 0 or len(out) != 64:
        return None
    return bytes.fromhex(out)


def compact_to_target(nbits: int) -> int:
    exponent = nbits >> 24
    mantissa = nbits & 0xFFFFFF
    if exponent <= 3:
        return mantissa >> (8 * (3 - exponent))
    return mantissa << (8 * (exponent - 3))


def target_to_compact(target: int) -> int:
    if target <= 0:
        raise ValueError("target must be positive")
    size = (target.bit_length() + 7) // 8
    if size <= 3:
        compact = target << (8 * (3 - size))
    else:
        compact = target >> (8 * (size - 3))
        compact |= (size + 1) << 24
    return compact & 0xFFFFFFFF


def pool_target(network_target: int, share_difficulty: int = 1000) -> int:
    """Easier target for pool shares (higher value = easier)."""
    return min(network_target * share_difficulty, POW_LIMIT)


def hashrate_from_share_work(
    difficulty_sum: float,
    seconds: float,
    network_hashps: float,
    ref_share_difficulty: int = 1000,
) -> float:
    """
    Estimate RandomX H/s from submitted pool shares.

    A share at difficulty D is D times easier than a full block, so the pool's
    average hashrate is: (difficulty per second) * (network H/s / D).
    Calibrated against the node's network hashrate (derived from block targets).
    """
    if seconds <= 0 or difficulty_sum <= 0 or network_hashps <= 0:
        return 0.0
    return (difficulty_sum / seconds) * (network_hashps / ref_share_difficulty)


def rx_seed_height(height: int) -> Optional[int]:
    """Height of the seed block for the RandomX key, None during bootstrap era."""
    if height <= RX_EPOCH_BLOCKS + RX_EPOCH_LAG:
        return None
    # Matches GetRandomXKey in pow.cpp (epoch is a power of two).
    return (height - RX_EPOCH_LAG - 1) & ~(RX_EPOCH_BLOCKS - 1)


def rx_key_for_height(height: int, seed_hash_hex: Optional[str] = None) -> bytes:
    """RandomX key bytes for a block at `height`.

    seed_hash_hex: display-order block hash of rx_seed_height(height), required
    once past the bootstrap era. Node keys are uint256 internal bytes, i.e.
    reversed display hex (same convention as RX_BOOTSTRAP_KEY).
    """
    if rx_seed_height(height) is None:
        return RX_BOOTSTRAP_KEY
    if not seed_hash_hex:
        raise ValueError(f"height {height} requires the seed block hash for key rotation")
    return bytes.fromhex(seed_hash_hex)[::-1]


def serialize_header(
    version: int,
    prev_hash_hex: str,
    merkle_root_hex: str,
    ntime: int,
    nbits: int,
    nonce: int = 0,
) -> bytes:
    """Bitcoin 80-byte block header (internal byte order for hashes)."""
    return struct.pack(
        "<I",
        version,
    ) + bytes.fromhex(prev_hash_hex)[::-1] + bytes.fromhex(merkle_root_hex)[
        ::-1
    ] + struct.pack("<III", ntime, nbits, nonce)


class RandomXHasher:
    """RandomX hasher: in-process VM (fast, cached) with native CLI fallback.

    pip randomx and the node's RandomX produce identical hashes for the same
    key bytes; the VM avoids a subprocess + cache re-init on every share.
    """

    def __init__(self, key: bytes):
        self._key = key
        self._vm = None
        try:
            import randomx
            self._vm = randomx.RandomX(key)
        except ImportError:
            if not os.path.isfile(_NATIVE_HASH):
                raise ImportError(
                    "Install native bz-pow-hash on the pool node or pip install randomx."
                ) from None

    def hash(self, header: bytes) -> bytes:
        if self._vm is not None:
            return bytes(self._vm(header))
        native = _native_hash(self._key, header)
        if native is None:
            raise RuntimeError("bz-pow-hash failed and no randomx module available")
        return native

    def hash_int(self, header: bytes) -> int:
        return int.from_bytes(self.hash(header), "little")


def hash_meets_target(hash_int: int, target: int) -> bool:
    return hash_int <= target
