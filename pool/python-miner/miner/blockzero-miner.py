#!/usr/bin/env python3
"""BLOZ pool miner — Stratum client with RandomX grind loop."""
from __future__ import annotations

import argparse
import json
import logging
import os
import socket
import struct
import sys
import threading
import time
from typing import Callable, Optional
from urllib.parse import urlparse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "engine"))

from bloz_pow import RandomXHasher

LOG = logging.getLogger("blockzero-miner")


def _split_json_lines(raw: str) -> list[str]:
    """Split one WebSocket frame that may contain multiple JSON objects."""
    lines: list[str] = []
    buf = ""
    for ch in raw:
        if ch in "\r\n":
            if buf.strip():
                lines.append(buf.strip())
            buf = ""
            continue
        if ch == "{" and buf and buf.rstrip().endswith("}"):
            lines.append(buf.strip())
            buf = ch
        else:
            buf += ch
    if buf.strip():
        lines.append(buf.strip())
    return lines


class LineTransport:
    def send_line(self, line: str) -> None:
        raise NotImplementedError

    def read_loop(self, on_line: Callable[[str], None]) -> None:
        raise NotImplementedError

    def close(self) -> None:
        pass


class TcpTransport(LineTransport):
    def __init__(self, host: str, port: int):
        self.sock = socket.create_connection((host, port), timeout=30)
        self.sock.settimeout(None)

    def send_line(self, line: str) -> None:
        self.sock.sendall((line + "\n").encode())

    def read_loop(self, on_line: Callable[[str], None]) -> None:
        buf = b""
        while True:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("eof")
            buf += chunk
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                if raw.strip():
                    on_line(raw.decode())

    def close(self) -> None:
        self.sock.close()


class WsTransport(LineTransport):
    def __init__(self, url: str):
        import websocket

        self._ws = websocket.create_connection(url, timeout=30)
        self._ws.settimeout(None)

    def send_line(self, line: str) -> None:
        self._ws.send(line)

    def read_loop(self, on_line: Callable[[str], None]) -> None:
        while True:
            msg = self._ws.recv()
            if not msg:
                raise ConnectionError("eof")
            if isinstance(msg, bytes):
                msg = msg.decode()
            for line in _split_json_lines(msg):
                on_line(line)

    def close(self) -> None:
        self._ws.close()


class StratumClient:
    def __init__(self, url: str, worker: str, password: str, threads: int):
        self.url = url
        self.worker = worker
        self.password = password
        self.threads = max(1, threads)
        self.transport: Optional[LineTransport] = None
        self.job_id: Optional[str] = None
        self.header_prefix: Optional[bytes] = None
        self.rx_key: Optional[bytes] = None
        self.pool_target = 0
        self._stop = threading.Event()
        self._req_id = 1
        self._lock = threading.Lock()
        self._grind_started = False
        self._grind_lock = threading.Lock()

    def _connect(self) -> LineTransport:
        parsed = urlparse(
            self.url.replace("stratum+tcp://", "tcp://").replace("stratum+ssl://", "wss://")
        )
        scheme = parsed.scheme or "tcp"
        if scheme in ("ws", "wss"):
            path = parsed.path or "/stratum"
            if path == "/":
                path = "/stratum"
            host = parsed.hostname or "pool.bloz.org"
            port = parsed.port or (443 if scheme == "wss" else 80)
            netloc = f"{host}:{port}" if port not in (80, 443) else host
            ws_url = f"{scheme}://{netloc}{path}"
            LOG.info("websocket %s", ws_url)
            return WsTransport(ws_url)
        host = parsed.hostname or parsed.path
        port = parsed.port or 3333
        LOG.info("tcp %s:%s", host, port)
        return TcpTransport(host, port)

    def _send(self, method: str, params: list, req_id: Optional[int] = None) -> None:
        with self._lock:
            if not self.transport:
                raise ConnectionError("not connected")
            rid = req_id if req_id is not None else self._req_id
            if req_id is None:
                self._req_id += 1
            transport = self.transport
        payload = json.dumps(
            {"method": method, "params": params, "id": rid},
            separators=(",", ":"),
        )
        transport.send_line(payload)

    def connect(self) -> None:
        while not self._stop.is_set():
            try:
                transport = self._connect()
                with self._lock:
                    self.transport = transport
                    self.job_id = None
                    self.header_prefix = None
                    self.rx_key = None
                LOG.info("connected")
                self._send("mining.subscribe", [])
                time.sleep(0.05)
                self._send("mining.authorize", [self.worker, self.password])
                return
            except OSError as exc:
                LOG.warning("connect failed: %s", exc)
                time.sleep(10)

    def _disconnect(self) -> None:
        with self._lock:
            self.job_id = None
            self.header_prefix = None
            self.rx_key = None
            transport = self.transport
            self.transport = None
        if transport:
            try:
                transport.close()
            except OSError:
                pass

    def _apply_job(self, params: list) -> None:
        job_id, header_prefix_hex, rx_key_hex, _nbits, pool_target_hex, *_rest = params[:8]
        with self._lock:
            self.job_id = job_id
            self.header_prefix = bytes.fromhex(header_prefix_hex)
            self.rx_key = bytes.fromhex(rx_key_hex)
            self.pool_target = int(pool_target_hex, 16)
        LOG.info("new job %s", job_id)

    def _on_line(self, line: str) -> None:
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            return
        if msg.get("method") == "mining.notify":
            self._apply_job(msg.get("params", []))

    def _submit(self, nonce: int) -> None:
        with self._lock:
            job_id = self.job_id
            if not job_id or not self.transport:
                return
        try:
            self._send("mining.submit", [self.worker, job_id, f"{nonce:08x}"])
        except Exception as exc:
            LOG.warning("submit failed nonce=%08x: %s", nonce, exc)

    def _grind_thread(self, thread_id: int) -> None:
        nonce = thread_id
        hashes = 0
        t0 = time.time()
        hasher: Optional[RandomXHasher] = None
        active_key: Optional[bytes] = None
        while not self._stop.is_set():
            try:
                with self._lock:
                    prefix = self.header_prefix
                    key = self.rx_key
                    pool_target = self.pool_target
                    job_id = self.job_id
                if not prefix or not key or not job_id:
                    time.sleep(0.05)
                    continue
                if key != active_key:
                    hasher = RandomXHasher(key)
                    active_key = key
                for _ in range(500):
                    header = prefix + struct.pack("<I", nonce & 0xFFFFFFFF)
                    if hasher.hash_int(header) <= pool_target:
                        LOG.info("share nonce=%08x", nonce)
                        self._submit(nonce)
                    nonce += self.threads
                    hashes += 1
                if hashes >= 20000:
                    elapsed = max(time.time() - t0, 0.001)
                    LOG.info("thread %d ~%.0f H/s", thread_id, hashes / elapsed)
                    hashes = 0
                    t0 = time.time()
            except Exception as exc:
                LOG.warning("grind thread %d error: %s", thread_id, exc)
                time.sleep(1)

    def _ensure_grind_threads(self) -> None:
        with self._grind_lock:
            if self._grind_started:
                return
            self._grind_started = True
            for t in range(self.threads):
                threading.Thread(target=self._grind_thread, args=(t,), daemon=True).start()

    def _reader_loop(self) -> None:
        with self._lock:
            transport = self.transport
        if not transport:
            return
        try:
            transport.read_loop(self._on_line)
        except Exception as exc:
            LOG.warning("reader lost: %s", exc)

    def run_forever(self) -> None:
        self._ensure_grind_threads()
        while not self._stop.is_set():
            try:
                self.connect()
                reader = threading.Thread(target=self._reader_loop, daemon=True)
                reader.start()
                while reader.is_alive() and not self._stop.is_set():
                    time.sleep(1)
            except Exception as exc:
                LOG.warning("session error: %s", exc)
            finally:
                self._disconnect()
            if not self._stop.is_set():
                LOG.warning("disconnected — reconnecting in 5s")
                time.sleep(5)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    parser = argparse.ArgumentParser(description="BLOZ pool miner")
    parser.add_argument(
        "-o",
        "--url",
        default=os.environ.get("POOL_URL", "wss://pool.bloz.org/stratum"),
    )
    parser.add_argument("-u", "--user", default=os.environ.get("POOL_USER", ""))
    parser.add_argument("-p", "--password", default=os.environ.get("POOL_PASS", "x"))
    parser.add_argument(
        "-t", "--threads", type=int, default=int(os.environ.get("MINER_THREADS", "4"))
    )
    args = parser.parse_args()

    worker = args.user
    if not worker:
        addr = os.environ.get("MINER_PAYOUT", "worker1")
        worker = f"{addr}.rig1"

    client = StratumClient(args.url, worker, args.password, args.threads)
    try:
        client.run_forever()
    except KeyboardInterrupt:
        client._stop.set()


if __name__ == "__main__":
    main()
