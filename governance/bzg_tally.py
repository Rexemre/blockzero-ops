#!/usr/bin/env python3
"""BZG1 reference tally for Block Zero community-fund governance (stage 1).

Reads proposals and votes from the chain via node RPC and computes the
result of one governance cycle deterministically. Strictly read-only: the
RPC client only allows getblockchaininfo, getblockcount, getblockhash and
getblock. No wallet access, nothing is sent.

Specification: blockzero-docs/konzepte/bzg1-spezifikation.md

Usage:
  python bzg_tally.py --params params/regtest.json --cycle 0 \
      --rpc-url http://127.0.0.1:18443 --rpc-user u --rpc-password p [--out result.json]
  (or --rpc-cookie <datadir>/regtest/.cookie)
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import sys
import urllib.request
from decimal import Decimal

MAGIC = b"BZG"
VERSION = 0x01
TYPE_PROPOSAL = ord("P")
TYPE_VOTE = ord("V")
CHOICES = ("no", "yes", "abstain")  # 0, 1, 2
MAX_VOTE_ENTRIES = 32
PREFIX_LEN = 8
COIN = 100_000_000

READ_ONLY_METHODS = {"getblockchaininfo", "getblockcount", "getblockhash", "getblock"}


class ReadOnlyRPC:
    def __init__(self, url: str, user: str, password: str):
        self.url = url
        self.auth = base64.b64encode(f"{user}:{password}".encode()).decode()
        self._id = 0

    def call(self, method: str, *params):
        if method not in READ_ONLY_METHODS:
            raise PermissionError(f"RPC method {method} is not allowed (read-only tally)")
        self._id += 1
        body = json.dumps({"jsonrpc": "1.0", "id": self._id, "method": method, "params": list(params)}).encode()
        req = urllib.request.Request(self.url, data=body, headers={
            "Content-Type": "application/json", "Authorization": f"Basic {self.auth}"})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:  # RPC errors arrive as HTTP 500 with a JSON body
            raw = e.read()
        # Amounts as Decimal so the conversion to satoshis is exact.
        reply = json.loads(raw, parse_float=Decimal)
        if reply.get("error"):
            raise RuntimeError(f"RPC {method}: {reply['error']}")
        return reply["result"]


def to_sat(value) -> int:
    sat = Decimal(value) * COIN
    if sat != sat.to_integral_value():
        raise ValueError(f"amount {value} is not a whole number of satoshis")
    return int(sat)


# --- payload parsing -------------------------------------------------------

def op_return_payload(spk_hex: str) -> bytes | None:
    """Payload of an OP_RETURN script with exactly one data push, else None."""
    try:
        s = bytes.fromhex(spk_hex)
    except ValueError:
        return None
    if len(s) < 2 or s[0] != 0x6A:
        return None
    op, rest = s[1], s[2:]
    if 0x01 <= op <= 0x4B:
        n, data = op, rest
    elif op == 0x4C and len(rest) >= 1:
        n, data = rest[0], rest[1:]
    elif op == 0x4D and len(rest) >= 2:
        n, data = int.from_bytes(rest[:2], "little"), rest[2:]
    else:
        return None
    return data if len(data) == n else None


def bzg_payload(tx) -> tuple[bytes | None, str | None]:
    """(payload, None) for exactly one BZG1 output; (None, reason) if malformed; (None, None) if no BZG."""
    found = []
    for out in tx["vout"]:
        p = op_return_payload(out["scriptPubKey"]["hex"])
        if p is not None and p[:3] == MAGIC:
            found.append(p)
    if not found:
        return None, None
    if len(found) > 1:
        return None, "mehrere_bzg_outputs"
    p = found[0]
    if len(p) < 5 or p[3] != VERSION:
        return None, "unbekannte_version"
    return p, None


def parse_proposal(p: bytes, max_tranches: int):
    # "BZG" 01 'P' | cycle u32 | doc_sha256 32 | amount u64 | n_tranches u8 | spk_len u8 | spk
    if len(p) < 52:
        return None
    cycle = int.from_bytes(p[5:9], "big")
    doc = p[9:41].hex()
    amount = int.from_bytes(p[41:49], "big")
    tranches = p[49]
    spk_len = p[50]
    spk = p[51:]
    if len(spk) != spk_len or not (1 <= spk_len <= 40) or spk[0] == 0x6A:
        return None
    if amount <= 0 or not (1 <= tranches <= max_tranches):
        return None
    return {"cycle": cycle, "doc_sha256": doc, "amount_sat": amount, "n_tranches": tranches, "payout_spk": spk.hex()}


def parse_vote(p: bytes):
    # "BZG" 01 'V' | cycle u32 | k u8 | k x (proposal_id_prefix 8, choice u8)
    if len(p) < 10:
        return None
    cycle = int.from_bytes(p[5:9], "big")
    k = p[9]
    if not (1 <= k <= MAX_VOTE_ENTRIES) or len(p) != 10 + k * (PREFIX_LEN + 1):
        return None
    entries = []
    for i in range(k):
        off = 10 + i * (PREFIX_LEN + 1)
        entries.append((p[off:off + PREFIX_LEN].hex(), p[off + PREFIX_LEN]))
    return {"cycle": cycle, "entries": entries}


# --- payload building (used by tests and later by the wallet) --------------

def build_proposal(cycle: int, doc_sha256: bytes, amount_sat: int, n_tranches: int, payout_spk: bytes) -> bytes:
    return (MAGIC + bytes([VERSION, TYPE_PROPOSAL]) + cycle.to_bytes(4, "big") + doc_sha256
            + amount_sat.to_bytes(8, "big") + bytes([n_tranches, len(payout_spk)]) + payout_spk)


def build_vote(cycle: int, entries: list[tuple[str, int]]) -> bytes:
    """entries: (proposal txid hex, choice 0/1/2); the first 8 bytes of the txid as displayed are used."""
    out = MAGIC + bytes([VERSION, TYPE_VOTE]) + cycle.to_bytes(4, "big") + bytes([len(entries)])
    for txid, choice in entries:
        out += bytes.fromhex(txid)[:PREFIX_LEN] + bytes([choice])
    return out


# --- tally -----------------------------------------------------------------

def windows(params, cycle: int):
    start = params["cycle0"] + cycle * params["cycle_len"]
    snap = start + params["submit_len"] - 1
    vote_end = snap + params["vote_len"]
    end = start + params["cycle_len"] - 1
    assert vote_end < end, "rest period must be at least one block"
    return {"start": start, "snapshot": snap, "vote_start": snap + 1, "vote_end": vote_end, "end": end}


def tally(rpc: ReadOnlyRPC, params: dict, cycle: int) -> dict:
    w = windows(params, cycle)
    tip = rpc.call("getblockcount")
    if tip < w["snapshot"]:
        raise RuntimeError(f"chain height {tip} is below the snapshot height {w['snapshot']}; submission phase still running")
    excluded = set(params["excluded_scripts"])
    fund = params["fund_script"]
    min_h = w["snapshot"] - params["min_age"]
    maturity_h = w["snapshot"] - params["coinbase_maturity"]

    def eligible_coin(height: int, coinbase: bool, spk: str) -> bool:
        return height <= min_h and not (coinbase and height > maturity_h) and spk not in excluded

    utxo: dict[tuple[str, int], tuple[int, int, str, bool]] = {}
    prev_inflow = 0
    proposals: dict[str, dict] = {}
    ignored: list[dict] = []
    ballots: list[dict] = []
    last = min(tip, w["end"])  # rest period is scanned only to report late votes
    hashes = {}

    for h in range(1, last + 1):  # genesis outputs are not spendable
        bhash = rpc.call("getblockhash", h)
        hashes[h] = bhash
        in_vote = h >= w["vote_start"]
        block = rpc.call("getblock", bhash, 3 if in_vote else 2)
        for pos, tx in enumerate(block["tx"]):
            is_cb = "coinbase" in tx["vin"][0]
            if h <= w["snapshot"]:
                if not is_cb:
                    for vin in tx["vin"]:
                        utxo.pop((vin["txid"], vin["vout"]), None)
                for out in tx["vout"]:
                    spk = out["scriptPubKey"]["hex"]
                    if spk.startswith("6a"):
                        continue
                    val = to_sat(out["value"])
                    utxo[(tx["txid"], out["n"])] = (val, h, spk, is_cb)
                    if spk == fund and w["start"] - params["cycle_len"] <= h < w["start"]:
                        prev_inflow += val
            if is_cb:
                continue
            payload, err = bzg_payload(tx)
            if payload is None and err is None:
                continue
            if err:
                ignored.append({"txid": tx["txid"], "height": h, "grund": err})
                continue
            kind = payload[4]
            if kind == TYPE_PROPOSAL:
                prop = parse_proposal(payload, params["max_tranches"])
                if prop is None:
                    ignored.append({"txid": tx["txid"], "height": h, "grund": "vorschlag_ungueltig"})
                    continue
                if prop["cycle"] != cycle:
                    continue
                if not (w["start"] <= h <= w["snapshot"]):
                    ignored.append({"txid": tx["txid"], "height": h, "grund": "vorschlag_ausserhalb_einreichphase"})
                    continue
                fee = sum(to_sat(o["value"]) for o in tx["vout"] if o["scriptPubKey"]["hex"] == fund)
                if fee < params["proposal_fee_sat"]:
                    ignored.append({"txid": tx["txid"], "height": h, "grund": "vorschlagsgebuehr_fehlt"})
                    continue
                prop.update({"proposal_id": tx["txid"], "height": h, "pos": pos, "fee_sat": fee})
                proposals[tx["txid"]] = prop
            elif kind == TYPE_VOTE:
                vote = parse_vote(payload)
                if vote is None:
                    ignored.append({"txid": tx["txid"], "height": h, "grund": "stimme_ungueltig"})
                    continue
                if vote["cycle"] != cycle:
                    continue
                if not (w["vote_start"] <= h <= w["vote_end"]):
                    ignored.append({"txid": tx["txid"], "height": h, "grund": "stimme_ausserhalb_abstimmungsphase"})
                    continue
                inputs = []
                for vin in tx["vin"]:
                    po = vin["prevout"]
                    spk = po["scriptPubKey"]["hex"]
                    if eligible_coin(po["height"], po["generated"], spk):
                        inputs.append((spk, to_sat(po["value"])))
                ballots.append({"txid": tx["txid"], "height": h, "inputs": inputs, "entries": vote["entries"]})
            else:
                ignored.append({"txid": tx["txid"], "height": h, "grund": "unbekannter_typ"})

    # Snapshot figures
    eligible_supply = sum(v for (v, ht, spk, cb) in utxo.values() if eligible_coin(ht, cb, spk))
    fund_balance = sum(v for (v, ht, spk, cb) in utxo.values() if spk == fund)
    quorum_sat = (eligible_supply * params["quorum_pct"] + 99) // 100
    tx_cap = eligible_supply * params["whale_tx_cap_pct"] // 100
    proposal_cap = fund_balance * params["proposal_cap_pct"] // 100
    budget = prev_inflow + fund_balance * params["cycle_budget_pct"] // 100

    # Admission: at most max_proposals, highest fee first, then chain order
    order = sorted(proposals.values(), key=lambda p: (-p["fee_sat"], p["height"], p["pos"]))
    admitted = {p["proposal_id"]: p for p in order[:params["max_proposals"]]}
    for p in order[params["max_proposals"]:]:
        ignored.append({"txid": p["proposal_id"], "height": p["height"], "grund": "vorschlag_nicht_zugelassen_limit"})
    by_prefix: dict[str, list[str]] = {}
    for pid in admitted:
        by_prefix.setdefault(pid[:2 * PREFIX_LEN], []).append(pid)

    res = {pid: {"yes": 0, "no": 0, "abstain": 0, "yes_tx": 0, "no_tx": 0, "abstain_tx": 0, "gekappt_sat": 0}
           for pid in admitted}
    ballot_log = []
    for b in ballots:
        seen = set()
        counted = []
        for prefix, choice in b["entries"]:
            if choice > 2:
                ignored.append({"txid": b["txid"], "height": b["height"], "grund": "eintrag_ungueltige_wahl"})
                continue
            match = by_prefix.get(prefix, [])
            if len(match) != 1:
                ignored.append({"txid": b["txid"], "height": b["height"],
                                "grund": "eintrag_unbekannter_vorschlag" if not match else "eintrag_mehrdeutig"})
                continue
            pid = match[0]
            if pid in seen:
                ignored.append({"txid": b["txid"], "height": b["height"], "grund": "eintrag_doppelt"})
                continue
            seen.add(pid)
            payout = admitted[pid]["payout_spk"]
            raw = sum(v for spk, v in b["inputs"] if spk != payout)  # conflict of interest rule
            weight = min(raw, tx_cap)
            r = res[pid]
            key = CHOICES[choice]
            r[key] += weight
            r["gekappt_sat"] += raw - weight
            if weight > 0:
                r[key + "_tx"] += 1
            counted.append({"proposal_id": pid, "wahl": key, "gewicht_sat": weight, "roh_sat": raw})
        ballot_log.append({"txid": b["txid"], "height": b["height"], "stimmen": counted})

    # Decision
    out_props = []
    candidates = []
    for pid, p in admitted.items():
        r = res[pid]
        yn = r["yes"] + r["no"]
        if yn * 100 < eligible_supply * params["quorum_pct"]:
            status = "abgelehnt_quorum"
        elif r["yes"] * 100 < yn * params["majority_pct"]:
            status = "abgelehnt_mehrheit"
        elif r["yes_tx"] < params["min_yes_tx"]:
            status = "abgelehnt_breite"
        elif p["amount_sat"] > proposal_cap:
            status = "abgelehnt_deckel"
        else:
            status = None
            candidates.append(pid)
        out_props.append({**{k: p[k] for k in ("proposal_id", "height", "fee_sat", "amount_sat", "n_tranches",
                                               "payout_spk", "doc_sha256")}, **r, "status": status})
    candidates.sort(key=lambda pid: (-(res[pid]["yes"] - res[pid]["no"]), -res[pid]["yes"], pid))
    remaining = budget
    rank = {}
    for i, pid in enumerate(candidates, 1):
        rank[pid] = i
    for o in out_props:
        o["rang"] = rank.get(o["proposal_id"])
    for pid in candidates:
        o = next(x for x in out_props if x["proposal_id"] == pid)
        if o["amount_sat"] <= remaining:
            o["status"] = "angenommen"
            remaining -= o["amount_sat"]
        else:
            o["status"] = "abgelehnt_budget"
    out_props.sort(key=lambda o: (o["height"], o["proposal_id"]))
    ignored.sort(key=lambda x: (x["height"], x["txid"], x["grund"]))

    result = {
        "spec": "BZG1",
        "network": params["network"],
        "cycle": cycle,
        "fenster": w,
        "final": tip >= w["end"],
        "snapshot_blockhash": hashes.get(w["snapshot"]),
        "vote_end_blockhash": hashes.get(w["vote_end"]),
        "stimmberechtigte_menge_sat": eligible_supply,
        "quorum_sat": quorum_sat,
        "wal_bremse_pro_tx_sat": tx_cap,
        "fonds_bestand_sat": fund_balance,
        "fonds_zufluss_vorzyklus_sat": prev_inflow,
        "deckel_pro_vorschlag_sat": proposal_cap,
        "budget_sat": budget,
        "budget_verwendet_sat": budget - remaining,
        "vorschlaege": out_props,
        "stimmzettel": ballot_log,
        "ignoriert": ignored,
    }
    canonical = json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return {"result": result, "result_sha256": hashlib.sha256(canonical.encode()).hexdigest(), "tip": tip}


def fmt(sat: int) -> str:
    return f"{sat // COIN:,}.{sat % COIN:08d}".replace(",", "'")


def summary(t: dict) -> str:
    r = t["result"]
    lines = [f"BZG1 Zyklus {r['cycle']} ({r['network']}), Stichtag {r['fenster']['snapshot']}, "
             f"Abstimmung {r['fenster']['vote_start']}-{r['fenster']['vote_end']}, "
             f"{'FINAL' if r['final'] else 'VORLAEUFIG'} (Tip {t['tip']})",
             f"Stimmberechtigt {fmt(r['stimmberechtigte_menge_sat'])} BLOZ, Quorum {fmt(r['quorum_sat'])}, "
             f"Wal-Bremse/Tx {fmt(r['wal_bremse_pro_tx_sat'])}",
             f"Fonds {fmt(r['fonds_bestand_sat'])}, Deckel/Vorschlag {fmt(r['deckel_pro_vorschlag_sat'])}, "
             f"Budget {fmt(r['budget_sat'])} (verwendet {fmt(r['budget_verwendet_sat'])})"]
    for p in r["vorschlaege"]:
        lines.append(f"  {p['proposal_id'][:16]} {fmt(p['amount_sat']):>18} BLOZ  ja {fmt(p['yes'])} ({p['yes_tx']} Tx)"
                     f"  nein {fmt(p['no'])}  enth. {fmt(p['abstain'])}  -> {p['status']}")
    lines.append(f"Ignoriert: {len(r['ignoriert'])}  Ergebnis-Hash: {t['result_sha256']}")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--params", required=True)
    ap.add_argument("--cycle", type=int, required=True)
    ap.add_argument("--rpc-url", default="http://127.0.0.1:8332")
    ap.add_argument("--rpc-user")
    ap.add_argument("--rpc-password")
    ap.add_argument("--rpc-cookie", help="path to the node's .cookie file")
    ap.add_argument("--out", help="write the full result as JSON")
    a = ap.parse_args(argv)
    if a.rpc_cookie:
        user, password = open(a.rpc_cookie, encoding="ascii").read().strip().split(":", 1)
    else:
        user, password = a.rpc_user, a.rpc_password
    with open(a.params, encoding="utf-8") as f:
        params = json.load(f)
    t = tally(ReadOnlyRPC(a.rpc_url, user, password), params, a.cycle)
    print(summary(t))
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(t, f, indent=2, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
