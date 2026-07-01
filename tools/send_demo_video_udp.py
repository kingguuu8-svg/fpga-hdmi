#!/usr/bin/env python3
"""Send the fixed built-in non-camera demo video over the project UDP protocol."""

from __future__ import annotations

import argparse
import json
import socket
import struct
import time
from pathlib import Path

from dashboard.demo_source import frame_sha256, make_demo_frame


MAGIC = b"ZVID"
VERSION = 1
HEADER_LEN = 24
DEFAULT_PORT = 5005
DEFAULT_PAYLOAD = 1200


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


def run_sender(args: argparse.Namespace) -> int:
    if args.width <= 0 or args.height <= 0:
        raise SystemExit("width and height must be positive")
    if args.payload <= 0 or args.payload > 1400:
        raise SystemExit("payload must be in range 1..1400")
    if args.frames < 0:
        raise SystemExit("frames must be non-negative; use 0 for continuous")
    if args.fps <= 0:
        raise SystemExit("fps must be positive")

    target = (args.host, args.port)
    frame_period = 1.0 / args.fps
    inter_packet_delay = args.inter_packet_us / 1_000_000.0
    total_packets = 0

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        index = 0
        while args.frames == 0 or index < args.frames:
            frame_id = args.start_frame_id + index
            started = time.perf_counter()
            frame = make_demo_frame(args.width, args.height, frame_id)
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
                f"demo_frame={frame_id} bytes={len(frame)} packets={packets} "
                f"sha256={frame_sha256(frame)} elapsed_s={elapsed:.3f}",
                flush=True,
            )
            remaining = frame_period - elapsed
            index += 1
            if (args.frames == 0 or index != args.frames) and remaining > 0:
                time.sleep(remaining)

    frame_count = "continuous" if args.frames == 0 else str(args.frames)
    print(f"DEMO_VIDEO_SEND_OK frames={frame_count} packets={total_packets} target={args.host}:{args.port}")
    return 0


def run_self_test(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    width = 80
    height = 60
    payload_size = 480
    frame0 = make_demo_frame(width, height, 0)
    frame1 = make_demo_frame(width, height, 1)
    if len(frame0) != width * height * 3:
        raise AssertionError("unexpected frame size")
    if frame0 == frame1:
        raise AssertionError("demo frames are not dynamic")

    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiver.bind(("127.0.0.1", 0))
    receiver.settimeout(2)
    target = ("127.0.0.1", receiver.getsockname()[1])

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
        packet_count = send_frame(sender, target, frame0, width, height, 42, payload_size, 0.0)

    received_payload = 0
    received_packets = 0
    received_frame_ids: set[int] = set()
    try:
        while received_packets < packet_count:
            packet, _ = receiver.recvfrom(2048)
            if packet[:4] != MAGIC:
                raise AssertionError("bad magic")
            received_frame_ids.add(struct.unpack_from("<I", packet, 12)[0])
            received_payload += struct.unpack_from("<H", packet, 20)[0]
            received_packets += 1
    finally:
        receiver.close()

    if received_packets != packet_count:
        raise AssertionError("packet count mismatch")
    if received_payload != len(frame0):
        raise AssertionError("payload byte count mismatch")
    if received_frame_ids != {42}:
        raise AssertionError("frame id mismatch")

    result = {
        "status": "pass",
        "source": "built-in-generated-demo",
        "camera_input": False,
        "custom_file_input": False,
        "width": width,
        "height": height,
        "frame0_sha256": frame_sha256(frame0),
        "frame1_sha256": frame_sha256(frame1),
        "packet_count": packet_count,
        "received_packets": received_packets,
        "received_payload": received_payload,
    }
    out_dir.joinpath("self-test.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"DEMO_VIDEO_SENDER_SELF_TEST_OK out={out_dir} packets={packet_count}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Send a fixed built-in generated demo video. No camera/webcam or custom file input is supported in MVP."
    )
    parser.add_argument("host", nargs="?", help="target board IPv4 address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=600)
    parser.add_argument("--fps", type=float, default=1.0)
    parser.add_argument("--frames", type=int, default=5, help="frame count; 0 sends continuously until stopped")
    parser.add_argument("--start-frame-id", type=int, default=0)
    parser.add_argument("--payload", type=int, default=DEFAULT_PAYLOAD)
    parser.add_argument("--inter-packet-us", type=float, default=200.0)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--out-dir", default="build/fixed-demo-video-sender")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.self_test:
        return run_self_test(Path(args.out_dir))
    if not args.host:
        parser.error("host is required unless --self-test is used")
    return run_sender(args)


if __name__ == "__main__":
    raise SystemExit(main())
