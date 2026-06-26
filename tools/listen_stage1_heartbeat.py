#!/usr/bin/env python3
"""Listen for stage-1 board UDP heartbeat packets."""

from __future__ import annotations

import argparse
import socket
import time


DEFAULT_PORT = 5006


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0", help="local IPv4 bind address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--max-packets", type=int, default=3)
    args = parser.parse_args()

    if args.timeout <= 0:
        raise SystemExit("timeout must be positive")
    if args.max_packets <= 0:
        raise SystemExit("max-packets must be positive")

    deadline = time.monotonic() + args.timeout
    received = 0

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((args.bind, args.port))
        sock.settimeout(min(args.timeout, 1.0))

        while received < args.max_packets and time.monotonic() < deadline:
            try:
                payload, addr = sock.recvfrom(2048)
            except TimeoutError:
                continue
            received += 1
            text = payload.decode("ascii", errors="replace")
            print(f"heartbeat[{received}] from={addr[0]}:{addr[1]} {text}", flush=True)

    if received == 0:
        print(f"HEARTBEAT_TIMEOUT port={args.port} timeout_s={args.timeout}")
        return 1

    print(f"HEARTBEAT_OK packets={received}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
