#!/usr/bin/env python3
from pathlib import Path

CORE = Path.home() / "blockzero-core"

h = CORE / "src/kernel/chainparams.h"
text = h.read_text()
if "CurrencyUnit()" not in text:
    text = text.replace(
        "    const std::string& Bech32HRP() const { return bech32_hrp; }",
        "    const std::string& Bech32HRP() const { return bech32_hrp; }\n"
        "    const std::string& CurrencyUnit() const { return m_currency_unit; }\n"
        "    const std::string& CurrencyAtom() const { return m_currency_atom; }",
    )
    text = text.replace(
        "    std::string bech32_hrp;",
        "    std::string bech32_hrp;\n"
        "    std::string m_currency_unit{\"BTC\"};\n"
        "    std::string m_currency_atom{\"sat\"};",
    )
    h.write_text(text)
    print("chainparams.h updated")

cpp = CORE / "src/kernel/chainparams.cpp"
text = cpp.read_text()
replacements = [
    (
        '        bech32_hrp = "bz";\n\n        vFixedSeeds',
        '        bech32_hrp = "bz";\n        m_currency_unit = "BLOZ";\n        m_currency_atom = "sat";\n\n        vFixedSeeds',
    ),
    (
        '        bech32_hrp = "tbz";\n\n        vFixedSeeds.clear();',
        '        bech32_hrp = "tbz";\n        m_currency_unit = "TBLOZ";\n        m_currency_atom = "tsat";\n\n        vFixedSeeds.clear();',
    ),
    (
        '        bech32_hrp = "bzrt";\n',
        '        bech32_hrp = "bzrt";\n        m_currency_unit = "TBLOZ";\n        m_currency_atom = "tsat";\n',
    ),
]
for old, new in replacements:
    if old not in text:
        print(f"WARN missing pattern: {old[:50]!r}")
        continue
    text = text.replace(old, new, 1)
cpp.write_text(text)
print("chainparams.cpp updated")

f = CORE / "src/policy/feerate.h"
text = f.read_text()
old = (
    'const std::string CURRENCY_UNIT = "BLOZ"; // One formatted unit\n'
    'const std::string CURRENCY_ATOM = "szat"; // One indivisible minimum value unit (1 BLOZ = 100,000,000 szat)'
)
new = (
    '#include <chainparams.h>\n\n'
    '/** Display unit for the active chain (BLOZ mainnet, TBLOZ testnet/regtest). */\n'
    'inline std::string CurrencyUnit() { return Params().CurrencyUnit(); }\n'
    '/** Smallest on-chain unit name for fee-rate strings (sat / tsat). */\n'
    'inline std::string CurrencyAtom() { return Params().CurrencyAtom(); }\n\n'
    '#define CURRENCY_UNIT CurrencyUnit()\n'
    '#define CURRENCY_ATOM CurrencyAtom()'
)
if old in text:
    text = text.replace(old, new)
    f.write_text(text)
    print("feerate.h updated")
else:
    print("feerate.h: pattern not found, skipping")
