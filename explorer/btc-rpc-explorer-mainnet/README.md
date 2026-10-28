# BLOZ mainnet explorer patches (explorer.bloz.org)

The mainnet explorer runs upstream [btc-rpc-explorer](https://github.com/janoside/btc-rpc-explorer) (MIT)
at commit `26e282a06e87b645c6e0687e2503d26d1e623dea` with local BLOZ changes.

- `bloz-mainnet.patch` – `git diff --binary` of the live checkout (BLOZ coin config and units, supply/tx stats,
  BLOZ branding and icons, unified bloz.org suite header, Ask AI dock in `views/layout.pug`).
- `bloz-theme.css` – copy to `public/style/bloz-theme.css`.

Apply on a clean checkout:

```
git clone https://github.com/janoside/btc-rpc-explorer.git && cd btc-rpc-explorer
git checkout 26e282a06e87b645c6e0687e2503d26d1e623dea
git apply --binary ../bloz-mainnet.patch
cp ../bloz-theme.css public/style/bloz-theme.css
```

Runtime settings come from `systemd/blockzero-mainnet-explorer.env.example` (never commit the real `.env`).
Snapshot taken 2026-10-28.
