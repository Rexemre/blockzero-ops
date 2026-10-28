#!/usr/bin/env python3
"""BZG1 regtest end-to-end test: two nodes, test wallets, proposals, votes, tally.

Regtest only. Starts two local regtest nodes (node2 has no wallet and only
syncs), creates proposals and votes with test wallets on node1, then runs the
read-only tally (bzg_tally.py) on both nodes and checks the expected result
and that both nodes produce the same result hash. Both nodes are stopped at
the end.

Usage:
  python regtest_demo.py --bindir <dir with bitcoind.exe/bitcoind> --workdir <empty dir> [--out result.json]
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import random
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bzg_tally as bzg  # noqa: E402

USER, PASSWORD = "bzg", "bzg-regtest"
VOTE_FEE = Decimal("0.0001")
EXE = ".exe" if os.name == "nt" else ""


class RPC:
    """Full RPC client for the test harness (wallet calls allowed, regtest only)."""

    def __init__(self, port: int, wallet: str | None = None):
        self.port, self.wallet = port, wallet
        self.auth = base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()

    def w(self, wallet: str) -> "RPC":
        return RPC(self.port, wallet)

    def __getattr__(self, method):
        def call(*params):
            url = f"http://127.0.0.1:{self.port}" + (f"/wallet/{self.wallet}" if self.wallet else "")
            body = json.dumps({"jsonrpc": "1.0", "id": 1, "method": method, "params": list(params)}).encode()
            req = urllib.request.Request(url, data=body, headers={"Authorization": f"Basic {self.auth}"})
            try:
                with urllib.request.urlopen(req, timeout=300) as r:
                    raw = r.read()
            except urllib.error.HTTPError as e:
                raw = e.read()
            reply = json.loads(raw, parse_float=Decimal)
            if reply.get("error"):
                raise RuntimeError(f"{method}{params}: {reply['error']}")
            return reply["result"]
        return call


def start_node(bindir: Path, datadir: Path, rpcport: int, p2pport: int, extra: list[str]):
    datadir.mkdir(parents=True, exist_ok=True)
    args = [str(bindir / f"bitcoind{EXE}"), "-regtest", f"-datadir={datadir}", f"-rpcport={rpcport}",
            f"-port={p2pport}", "-bind=127.0.0.1", f"-rpcuser={USER}", f"-rpcpassword={PASSWORD}",
            "-testactivationheight=devfund@1", "-fallbackfee=0.0001", "-dnsseed=0", "-listenonion=0",
            "-printtoconsole=0"] + extra
    log = open(datadir / "stdout.log", "w")
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    proc = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, creationflags=flags)
    rpc = RPC(rpcport)
    for _ in range(120):
        try:
            rpc.getblockcount()
            return proc, rpc
        except Exception:
            if proc.poll() is not None:
                raise RuntimeError(f"bitcoind exited, see {datadir / 'stdout.log'}")
            time.sleep(1)
    raise RuntimeError("bitcoind did not come up")


def log(msg):
    print(msg, flush=True)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--bindir", required=True)
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    bindir, work = Path(a.bindir), Path(a.workdir)
    if work.exists():
        shutil.rmtree(work)
    here = Path(__file__).resolve().parent
    params = json.loads((here / "params" / "regtest.json").read_text(encoding="utf-8"))
    cycle = 0
    win = bzg.windows(params, cycle)
    log(f"Fenster Zyklus 0: {win}")

    base = random.randint(21000, 29000)
    p1, r1 = start_node(bindir, work / "node1", base, base + 1, [])
    p2 = None
    try:
        p2, r2 = start_node(bindir, work / "node2", base + 2, base + 3,
                            ["-disablewallet", f"-connect=127.0.0.1:{base + 1}"])
        log(r1.getnetworkinfo()["subversion"])

        names = ["miner", "alice", "bob", "carol", "dave", "erin", "frank", "gina", "wal", "bridge"]
        W = {}
        for n in names:
            r1.createwallet(n)
            W[n] = r1.w(n)
        addr = {n: W[n].getnewaddress() for n in names}
        spk = {n: W[n].getaddressinfo(addr[n])["scriptPubKey"] for n in names}
        fund_addr = r1.decodescript(params["fund_script"])["address"]
        log(f"Fondsadresse auf Regtest: {fund_addr}")

        def mine_to(height):
            n = height - r1.getblockcount()
            if n > 0:
                r1.generatetoaddress(n, addr["miner"])

        mine_to(250)
        cb = r1.getblock(r1.getblockhash(250), 2)["tx"][0]["vout"]
        assert any(o["scriptPubKey"]["hex"] == params["fund_script"] for o in cb), "devfund output missing in coinbase"

        holdings = {"alice": 300, "bob": 200, "carol": 150, "dave": 100, "erin": 60, "gina": 40, "wal": 2000, "bridge": 1000}
        W["miner"].sendmany("", {addr[n]: v for n, v in holdings.items()})
        mine_to(win["start"] - 1)

        # Bridge reserve is excluded like on mainnet; on regtest it is a test wallet.
        params["excluded_scripts"][spk["bridge"]] = "Bridge-Reserve (Test)"
        params_path = work / "params-regtest-run.json"
        params_path.write_text(json.dumps(params, indent=2), encoding="utf-8")

        # --- submission phase -------------------------------------------
        def propose(key, amount, payout_name, fee=Decimal(1)):
            doc = hashlib.sha256(f"BZG1 Testvorschlag {key}".encode()).digest()
            payload = bzg.build_proposal(cycle, doc, amount * bzg.COIN, 1, bytes.fromhex(spk[payout_name]))
            outs = [{"data": payload.hex()}]
            if fee:
                outs.insert(0, {fund_addr: str(fee)})
            return W["miner"].send(outs)["txid"]

        mine_to(win["start"])
        P = {}
        P["P1"] = propose("P1 Explorer-Uebersetzung", 100, "bob")
        P["P2"] = propose("P2 Wal-Projekt", 100, "miner")
        P["P3"] = propose("P3 Merch", 50, "miner")
        P["P4"] = propose("P4 Meetup", 30, "miner")
        P["P5"] = propose("P5 Audit", 200, "miner")
        P["P6"] = propose("P6 Grossprojekt", 500, "miner")
        P["P7"] = propose("P7 Uebersetzung", 80, "gina")
        nofee = propose("PX ohne Gebuehr", 10, "alice", fee=None)
        mine_to(win["start"] + 2)
        # frank gets coins too late (younger than MIN_AGE at the snapshot)
        mine_to(win["snapshot"] - params["min_age"] + 2)
        W["miner"].sendtoaddress(addr["frank"], 500)
        mine_to(win["snapshot"])
        log(f"Vorschlaege: {json.dumps(P, indent=1)}")

        # --- voting phase -------------------------------------------------
        mine_to(win["vote_start"])
        late_prop = propose("PL zu spaet", 10, "alice")

        def vote(name, entries):
            utxos = W[name].listunspent(1)
            total = sum(Decimal(u["amount"]) for u in utxos)
            payload = bzg.build_vote(cycle, entries)
            raw = r1.createrawtransaction([{"txid": u["txid"], "vout": u["vout"]} for u in utxos],
                                          [{"data": payload.hex()}, {W[name].getrawchangeaddress(): str(total - VOTE_FEE)}])
            signed = W[name].signrawtransactionwithwallet(raw)
            assert signed["complete"]
            return r1.sendrawtransaction(signed["hex"])

        Y, N, A = 1, 0, 2
        V = {}
        V["alice"] = vote("alice", [(P["P1"], Y), (P["P3"], N), (P["P5"], Y), (P["P6"], Y), (P["P7"], A)])
        V["bob"] = vote("bob", [(P["P1"], Y), (P["P3"], Y), (P["P5"], Y), (P["P6"], Y), (P["P7"], Y)])
        V["carol"] = vote("carol", [(P["P1"], Y), (P["P3"], N), (P["P5"], Y), (P["P6"], Y), (P["P7"], Y)])
        V["dave"] = vote("dave", [(P["P1"], N), (P["P3"], Y), (P["P5"], N)])
        V["erin"] = vote("erin", [(P["P1"], Y), (P["P2"], Y), (P["P3"], Y), (P["P4"], Y), (P["P5"], Y),
                                  (P["P6"], Y), (P["P7"], Y), ("00" * 32, Y), (P["P5"], N)])
        V["wal"] = vote("wal", [(P["P2"], Y), (P["P5"], Y)])
        V["bridge"] = vote("bridge", [(P["P2"], Y), (P["P5"], Y)])
        V["frank"] = vote("frank", [(P["P4"], Y)])
        mine_to(win["vote_start"] + 2)
        V["alice_2"] = vote("alice", [(P["P3"], Y)])  # change output is newer than the snapshot -> weight 0
        mine_to(win["vote_end"] + 1)
        V["gina_late"] = vote("gina", [(P["P3"], Y)])  # rest period -> ignored
        mine_to(win["end"])

        # sync node2 and tally on both
        for _ in range(120):
            if r2.getblockcount() == r1.getblockcount() and r2.getbestblockhash() == r1.getbestblockhash():
                break
            time.sleep(1)
        else:
            raise RuntimeError("node2 did not sync")
        ro1 = bzg.ReadOnlyRPC(f"http://127.0.0.1:{base}", USER, PASSWORD)
        ro2 = bzg.ReadOnlyRPC(f"http://127.0.0.1:{base + 2}", USER, PASSWORD)
        t1 = bzg.tally(ro1, params, cycle)
        t1b = bzg.tally(ro1, params, cycle)
        t2 = bzg.tally(ro2, params, cycle)
        log(bzg.summary(t1))
        try:
            ro1.call("sendrawtransaction", "00")
            readonly_ok = False
        except PermissionError:
            readonly_ok = True

        # --- expectations (independent arithmetic from the holdings above) ---
        r = t1["result"]
        cap = r["wal_bremse_pro_tx_sat"]
        C = bzg.COIN
        props = {p["proposal_id"]: p for p in r["vorschlaege"]}
        name_of = {v: k for k, v in P.items()}
        got = {name_of.get(pid, pid): p for pid, p in props.items()}
        def wt(blz):  # weight of one ballot after the whale brake
            return min(blz * C, cap)

        expect = {
            # bob's yes does not count: the payout goes to his own address (conflict of interest)
            "P1": ("abgelehnt_budget", wt(300) + wt(150) + wt(60), wt(100), 3),
            "P2": ("abgelehnt_breite", wt(2000) + wt(60), 0, 2),      # whale capped, bridge excluded
            "P3": ("abgelehnt_mehrheit", wt(200) + wt(100) + wt(60), wt(300) + wt(150), 3),
            "P4": ("abgelehnt_quorum", wt(60), 0, 1),                 # frank's coins too young
            "P5": ("angenommen", wt(300) + wt(200) + wt(150) + wt(60) + wt(2000), wt(100), 5),
            "P6": ("abgelehnt_deckel", wt(300) + wt(200) + wt(150) + wt(60), 0, 4),
            "P7": ("angenommen", wt(200) + wt(150) + wt(60), 0, 3),   # ranks before P1 (higher net yes)
        }
        checks = []

        def check(label, cond):
            checks.append((label, bool(cond)))
            log(f"  [{'OK' if cond else 'FEHLER'}] {label}")

        log("Pruefungen:")
        check("genau 7 gueltige Vorschlaege", set(got) == set(expect))
        for k, (status, yes, no, ytx) in expect.items():
            g = got.get(k, {})
            check(f"{k}: {status}, ja {yes}, nein {no}, Ja-Tx {ytx}",
                  g.get("status") == status and g.get("yes") == yes and g.get("no") == no and g.get("yes_tx") == ytx)
        check("Wal-Bremse hat gekappt", got["P2"]["gekappt_sat"] == 2000 * C - cap)
        check("Wal-Stimme groesser als Kappung", 2000 * C > cap)
        reasons = {(i["txid"], i["grund"]) for i in r["ignoriert"]}
        check("Vorschlag ohne Gebuehr ignoriert", (nofee, "vorschlagsgebuehr_fehlt") in reasons)
        check("Vorschlag in Abstimmungsphase ignoriert", (late_prop, "vorschlag_ausserhalb_einreichphase") in reasons)
        check("Stimme in Ruhefrist ignoriert", (V["gina_late"], "stimme_ausserhalb_abstimmungsphase") in reasons)
        check("unbekannter Vorschlag im Stimmzettel ignoriert", (V["erin"], "eintrag_unbekannter_vorschlag") in reasons)
        check("doppelter Eintrag im Stimmzettel ignoriert", (V["erin"], "eintrag_doppelt") in reasons)
        sz = {b["txid"]: b for b in r["stimmzettel"]}
        check("zweite Stimme von alice hat Gewicht 0", all(s["gewicht_sat"] == 0 for s in sz[V["alice_2"]]["stimmen"]))
        check("Bridge-Reserve hat Gewicht 0", all(s["gewicht_sat"] == 0 for s in sz[V["bridge"]]["stimmen"]))
        check("frank (zu junge Coins) hat Gewicht 0", all(s["gewicht_sat"] == 0 for s in sz[V["frank"]]["stimmen"]))
        check("Budget eingehalten", r["budget_verwendet_sat"] <= r["budget_sat"])
        check("Ergebnis final", r["final"])
        check("zweimal ausgezaehlt, gleicher Hash", t1["result_sha256"] == t1b["result_sha256"])
        check("node2 zaehlt denselben Hash", t1["result_sha256"] == t2["result_sha256"])
        check("Auszaehler verweigert schreibende RPC-Aufrufe", readonly_ok)
        ok = all(c for _, c in checks)
        log(f"Ergebnis: {sum(c for _, c in checks)}/{len(checks)} Pruefungen OK -> {'BESTANDEN' if ok else 'FEHLGESCHLAGEN'}")
        if a.out:
            Path(a.out).write_text(json.dumps({"bestanden": ok, "pruefungen": checks, "vorschlaege_namen": P,
                                               "stimmen_txids": V, "node1": t1, "node2_hash": t2["result_sha256"]},
                                              indent=2, sort_keys=True), encoding="utf-8")
        return 0 if ok else 1
    finally:
        for port, proc in ((base, p1), (base + 2, p2)):
            if proc is None:
                continue
            try:
                RPC(port).stop()
            except Exception:
                pass
            try:
                proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                proc.kill()


if __name__ == "__main__":
    sys.exit(main())
