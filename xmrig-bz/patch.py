#!/usr/bin/env python3
"""Patch stock XMRig (v6.26.0) to add the `rx/blockzero` algorithm.

Block Zero uses the standard tevador/RandomX hash function (= XMRig's reference
`RandomX_MoneroConfig`) but applied to an 80-byte Bitcoin-style block header with
the 4-byte nonce at offset 76 (instead of Monero's offset 39).

This adds a new algo `rx/blockzero` (id 0x72151276 = rx/0 config) whose only
difference from rx/0 is nonceOffset() == 76, and disables XMRig's dev donation.
Files touched:
  - src/base/crypto/Algorithm.h    : enum id + name decl
  - src/base/crypto/Algorithm.cpp  : name def + names/aliases/all() lists
  - src/base/net/stratum/Job.cpp   : nonceOffset() returns 76
  - src/donate.h                   : default + minimum donate level = 0
  - src/Summary.cpp                : remove the "DONATE" startup line

Each edit asserts it applied, so a source-layout drift fails the build loudly
instead of silently producing a broken miner.
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("xmrig")


def apply(path: str, label: str, fn) -> None:
    p = root / path
    src = p.read_text(encoding="utf-8")
    out = fn(src)
    if out == src:
        raise SystemExit(f"PATCH FAILED ({path}): {label} did not match")
    p.write_text(out, encoding="utf-8")
    print(f"  patched {path}: {label}")


def sub1(pattern, repl):
    return lambda s: re.sub(pattern, repl, s, count=1)


print("Patching XMRig -> rx/blockzero ...")

# --- Algorithm.h ---
apply("src/base/crypto/Algorithm.h", "enum RX_BLOCKZERO",
      sub1(r'(RX_YADA\s*=\s*0x72151279,[^\n]*\n)',
           r'\1        RX_BLOCKZERO    = 0x72151276,   // "rx/blockzero" Block Zero (80-byte header, nonce@76)\n'))
apply("src/base/crypto/Algorithm.h", "decl kRX_BLOCKZERO",
      sub1(r'(static const char \*kRX_YADA;\n)',
           r'\1    static const char *kRX_BLOCKZERO;\n'))

# --- Algorithm.cpp ---
apply("src/base/crypto/Algorithm.cpp", "def kRX_BLOCKZERO",
      sub1(r'(const char \*Algorithm::kRX_YADA\s*=\s*"rx/yada";\n)',
           r'\1const char *Algorithm::kRX_BLOCKZERO = "rx/blockzero";\n'))
apply("src/base/crypto/Algorithm.cpp", "names ALGO_NAME(RX_BLOCKZERO)",
      sub1(r'(ALGO_NAME\(RX_YADA\),\n)',
           r'\1    ALGO_NAME(RX_BLOCKZERO),\n'))
apply("src/base/crypto/Algorithm.cpp", "aliases RX_BLOCKZERO",
      sub1(r'(ALGO_ALIAS\(RX_YADA,\s*"randomyada"\),\n)',
           r'\1    ALGO_ALIAS_AUTO(RX_BLOCKZERO), ALGO_ALIAS(RX_BLOCKZERO, "randomx/blockzero"),\n    ALGO_ALIAS(RX_BLOCKZERO, "rx/bz"),\n'))
apply("src/base/crypto/Algorithm.cpp", "all() order RX_BLOCKZERO",
      sub1(r'(RX_SFX,\s*RX_YADA),', r'\1, RX_BLOCKZERO,'))

# --- Job.cpp ---
apply("src/base/net/stratum/Job.cpp", "nonceOffset() == 76",
      sub1(r'\n(\s*)return 39;',
           lambda m: ("\n{i}if (algorithm() == Algorithm::RX_BLOCKZERO) {{\n"
                      "{i}    return 76;\n{i}}}\n\n{i}return 39;").format(i=m.group(1))))

# --- donate.h : 0% donation ---
# Stock XMRig clamps --donate-level up to kMinimumDonateLevel (1), so the runtime
# flag alone can't reach 0%. Set both default and minimum to 0 so Block Zero
# miners donate nothing to XMRig's devs. (Block Zero's on-chain Dev & Growth Fund
# is a separate, consensus-level mechanism.)
apply("src/donate.h", "kDefaultDonateLevel = 0",
      sub1(r'(kDefaultDonateLevel\s*=\s*)\d+;', r'\g<1>0;'))
apply("src/donate.h", "kMinimumDonateLevel = 0",
      sub1(r'(kMinimumDonateLevel\s*=\s*)\d+;', r'\g<1>0;'))

# --- Summary.cpp : hide the "DONATE" startup line ---
# Even at 0% XMRig prints a "DONATE 0%" line in the startup summary, which
# confuses Block Zero miners (they think the pool/chain takes a cut). Remove the
# line entirely so it never shows.
apply("src/Summary.cpp", "remove DONATE summary line",
      sub1(r'(?s)\n[ \t]*Log::print\(GREEN_BOLD\(" \* "\) WHITE_BOLD\("%-13s"\) WHITE_BOLD\("%s%d%%"\),\s*"DONATE",.*?\);\n',
           "\n"))

print("OK - rx/blockzero patch applied.")
