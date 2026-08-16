"""Tiny UDP DNS forwarder for VantaDNS on-phone mode.

Listens on 127.0.0.1:5353 (UDP) and forwards every raw DNS packet to
127.0.0.1:8533 where vanta-dns-core's UDP+TCP listeners run. This lets
Termux apps (nslookup, dig) and DNS-changing apps reach the VantaDNS
server without root.
"""

import socket
import threading
import sys

UPSTREAM = ("127.0.0.1", int(sys.argv[2]) if len(sys.argv) > 2 else 8533)
LOCAL = ("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 5353)
TIMEOUT = 5.0


def handle(pkt: bytes, addr):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(TIMEOUT)
            s.sendto(pkt, UPSTREAM)
            resp, _ = s.recvfrom(65535)
            UDP.sendto(resp, addr)
    except Exception:
        pass  # drop on upstream failure (server will be unreachable anyway)


UDP = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
UDP.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
UDP.bind(LOCAL)

threads = 0
lock = threading.Lock()


def worker(pkt, addr):
    global threads
    t = threading.Thread(target=handle, args=(pkt, addr), daemon=True)
    t.start()


print(f"DNS UDP forwarder listening on {LOCAL[0]}:{LOCAL[1]} -> {UPSTREAM[0]}:{UPSTREAM[1]}")

while True:
    pkt, addr = UDP.recvfrom(65535)
    worker(pkt, addr)
