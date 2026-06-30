#!/usr/bin/env python3
"""Send deterministic RGB888 video frames using the project raw UDP protocol."""

from __future__ import annotations

import argparse
import socket
import struct
import time


MAGIC = b"ZVID"
VERSION = 1
HEADER_LEN = 24
DEFAULT_PORT = 5005
DEFAULT_PAYLOAD = 1200


def make_frame(width: int, height: int, frame_id: int, pattern: str) -> bytes:
    data = bytearray(width * height * 3)
    for y in range(height):
        for x in range(width):
            if pattern == "bars":
                bar = (x * 8) // max(1, width)
                colors = [
                    (255, 255, 255),
                    (255, 255, 0),
                    (0, 255, 255),
                    (0, 255, 0),
                    (255, 0, 255),
                    (255, 0, 0),
                    (0, 0, 255),
                    (0, 0, 0),
                ]
                r, g, b = colors[min(bar, len(colors) - 1)]
            elif pattern == "checker":
                on = ((x // 32) ^ (y // 32) ^ frame_id) & 1
                r, g, b = (245, 245, 245) if on else (20, 60, 110)
            elif pattern == "rgb-stripes":
                if y < height // 3:
                    r, g, b = (0, 0, 255)
                elif y < (2 * height) // 3:
                    r, g, b = (0, 255, 0)
                else:
                    r, g, b = (255, 0, 0)
            else:
                r = (x * 255) // max(1, width - 1)
                g = (y * 255) // max(1, height - 1)
                b = ((frame_id * 7) + x + y) & 0xFF
            index = (y * width + x) * 3
            data[index] = r
            data[index + 1] = g
            data[index + 2] = b
    return bytes(data)


def packet_header(
    width: int,
    height: int,
    frame_id: int,
    offset: int,
    payload_len: int,
    flags: int,
) -> bytes:
    return struct.pack(
        "<4sBBHHHIIHH",
        MAGIC,
        VERSION,
        flags,
        HEADER_LEN,
        width,
        height,
        frame_id,
        offset,
        payload_len,
        0,
    )


def send_frame(
    sock: socket.socket,
    target: tuple[str, int],
    frame: bytes,
    width: int,
    height: int,
    frame_id: int,
    payload_size: int,
    inter_packet_delay: float,
) -> int:
    sent = 0
    frame_size = len(frame)
    for offset in range(0, frame_size, payload_size):
        payload = frame[offset : offset + payload_size]
        end = offset + len(payload) >= frame_size
        flags = 0x03 if end else 0x02
        packet = packet_header(width, height, frame_id, offset, len(payload), flags)
        sock.sendto(packet + payload, target)
        sent += 1
        if inter_packet_delay:
            time.sleep(inter_packet_delay)
    return sent


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("host", help="target board IPv4 address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=600)
    parser.add_argument("--fps", type=float, default=1.0)
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--payload", type=int, default=DEFAULT_PAYLOAD)
    parser.add_argument("--pattern", choices=["bars", "checker", "gradient", "rgb-stripes"], default="bars")
    parser.add_argument(
        "--inter-packet-us",
        type=float,
        default=0.0,
        help="optional delay between UDP packets in microseconds",
    )
    args = parser.parse_args()

    if args.width <= 0 or args.height <= 0:
        raise SystemExit("width and height must be positive")
    if args.payload <= 0 or args.payload > 1400:
        raise SystemExit("payload must be in range 1..1400")
    if args.frames <= 0:
        raise SystemExit("frames must be positive")
    if args.fps <= 0:
        raise SystemExit("fps must be positive")

    target = (args.host, args.port)
    frame_period = 1.0 / args.fps
    inter_packet_delay = args.inter_packet_us / 1_000_000.0
    total_packets = 0

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        for frame_id in range(args.frames):
            started = time.perf_counter()
            frame = make_frame(args.width, args.height, frame_id, args.pattern)
            packets = send_frame(
                sock,
                target,
                frame,
                args.width,
                args.height,
                frame_id,
                args.payload,
                inter_packet_delay,
            )
            total_packets += packets
            elapsed = time.perf_counter() - started
            print(
                f"frame={frame_id} bytes={len(frame)} packets={packets} "
                f"elapsed_s={elapsed:.3f}",
                flush=True,
            )
            remaining = frame_period - elapsed
            if frame_id != args.frames - 1 and remaining > 0:
                time.sleep(remaining)

    print(f"SEND_OK frames={args.frames} packets={total_packets} target={args.host}:{args.port}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
