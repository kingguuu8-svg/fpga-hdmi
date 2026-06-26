#!/usr/bin/env python3
"""Send one minimal packet for the stage-1 video UDP receiver."""

from __future__ import annotations

import argparse
import socket
import struct


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("host")
    parser.add_argument("--bind", default="192.168.1.2")
    parser.add_argument("--port", type=int, default=5005)
    args = parser.parse_args()

    packet = struct.pack(
        "<4sBBHHHIIHH",
        b"ZVID",
        1,
        2,
        24,
        640,
        480,
        123,
        0,
        0,
        0,
    )
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        if args.bind:
            sock.bind((args.bind, 0))
        sent = sock.sendto(packet, (args.host, args.port))
    print(
        f"SINGLE_UDP_SENT bytes={sent} source={args.bind or 'auto'} "
        f"target={args.host}:{args.port}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
