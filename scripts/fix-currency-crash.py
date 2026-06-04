#!/usr/bin/env python3
from pathlib import Path

CORE = Path.home() / "blockzero-core"

# chainparams.h
h = CORE / "src/chainparams.h"
text = h.read_text()
if "IsChainParamsSet()" not in text:
    text = text.replace(
        "const CChainParams &Params();\n",
        "const CChainParams &Params();\n\n"
        "/** True after SelectParams() has been called. */\n"
        "bool IsChainParamsSet();\n",
    )
    h.write_text(text)
    print("chainparams.h: added IsChainParamsSet")

# chainparams.cpp
cpp = CORE / "src/chainparams.cpp"
text = cpp.read_text()
if "IsChainParamsSet()" not in text:
    text = text.replace(
        "const CChainParams &Params() {\n    assert(globalChainParams);\n    return *globalChainParams;\n}",
        "const CChainParams &Params() {\n    assert(globalChainParams);\n    return *globalChainParams;\n}\n\nbool IsChainParamsSet()\n{\n    return static_cast<bool>(globalChainParams);\n}",
    )
    cpp.write_text(text)
    print("chainparams.cpp: added IsChainParamsSet")

# feerate.h
f = CORE / "src/policy/feerate.h"
text = f.read_text()
old = """/** Display unit for the active chain (BLOZ mainnet, TBLOZ testnet/regtest). */
inline std::string CurrencyUnit() { return Params().CurrencyUnit(); }
/** Smallest on-chain unit name for fee-rate strings (sat / tsat). */
inline std::string CurrencyAtom() { return Params().CurrencyAtom(); }"""
new = """/** Display unit for the active chain (BLOZ mainnet, TBLOZ testnet/regtest). */
inline std::string CurrencyUnit()
{
    if (IsChainParamsSet()) return Params().CurrencyUnit();
    return "BLOZ";
}
/** Smallest on-chain unit name for fee-rate strings (sat / tsat). */
inline std::string CurrencyAtom()
{
    if (IsChainParamsSet()) return Params().CurrencyAtom();
    return "sat";
}"""
if old in text:
    text = text.replace(old, new)
    f.write_text(text)
    print("feerate.h: safe CurrencyUnit")
