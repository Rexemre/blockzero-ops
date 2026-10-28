# BZG1 governance tally (stage 1, draft)

Reference tally for the Block Zero community-fund vote. Spec (German): `blockzero-docs/konzepte/bzg1-spezifikation.md`.

- `bzg_tally.py`: read-only tally over node RPC (only `getblockcount`, `getblockhash`, `getblock`).
- `params/mainnet.json`, `params/regtest.json`: parameters. Mainnet `cycle0` and the bridge/pool exclusion list are still open.
- `regtest_demo.py`: end-to-end test on two local regtest nodes (proposals, votes, tally, hash comparison).

```
python regtest_demo.py --bindir <dir with bitcoind> --workdir <scratch dir> [--out result.json]
python bzg_tally.py --params params/regtest.json --cycle 0 --rpc-url http://127.0.0.1:<port> --rpc-cookie <datadir>/regtest/.cookie
```

Regtest only. Nothing here sends transactions to mainnet.
