#!/usr/bin/env python3
"""Send a textured grayscale motion sequence over the project UDP video protocol."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import socket
import time
from pathlib import Path

from send_demo_video_udp import DEFAULT_PAYLOAD, DEFAULT_PORT, packet_header


MOTION_CONTENT_TYPE = "textured-motion"


def make_motion_frame(width: int, height: int, frame_id: int, start_frame_id: int = 0) -> bytes:
    phase = ((frame_id - start_frame_id) * 7) % 32
    frame = bytearray(width * height * 3)
    for y in range(height):
        row_bias = 34 if ((y // 24) & 1) else 0
        for x in range(width):
            stripe = 210 if (((x + phase) // 16) & 1) else 35
            checker = 35 if ((((x + phase) // 48) ^ (y // 48)) & 1) else 0
            value = max(0, min(255, stripe + row_bias - checker))
            offset = (y * width + x) * 3
            frame[offset : offset + 3] = bytes((value, value, value))
    return bytes(frame)


def frame_sha256(frame: bytes) -> str:
    return hashlib.sha256(frame).hexdigest()


def wait_until(target_time: float) -> None:
    while True:
        remaining = target_time - time.perf_counter()
        if remaining <= 0:
            return
        if remaining > 0.002:
            time.sleep(remaining / 2.0)


def send_frame_precise(
    sock: socket.socket,
    target: tuple[str, int],
    frame: bytes,
    width: int,
    height: int,
    frame_id: int,
    payload_size: int,
    packet_spacing_s: float,
) -> int:
    sent = 0
    frame_size = len(frame)
    started = time.perf_counter()
    for offset in range(0, frame_size, payload_size):
        if sent > 0 and packet_spacing_s > 0.0:
            wait_until(started + (sent * packet_spacing_s))
        payload = frame[offset : offset + payload_size]
        end = offset + len(payload) >= frame_size
        flags = 0x03 if end else 0x02
        packet = packet_header(width, height, frame_id, offset, len(payload), flags)
        sock.sendto(packet + payload, target)
        sent += 1
    return sent


def run_sender(args: argparse.Namespace) -> int:
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    if args.frames <= 0:
        raise SystemExit("frames must be positive")
    if args.fps <= 0:
        raise SystemExit("fps must be positive")

    target = (args.host, args.port)
    frame_period = 1.0 / args.fps
    sent: list[dict[str, object]] = []
    total_packets = 0
    origin = time.perf_counter()

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for index in range(args.frames):
            frame_id = args.start_frame_id + index
            frame = make_motion_frame(args.width, args.height, frame_id, args.start_frame_id)
            expected_packets = int(math.ceil(len(frame) / args.payload))
            if args.inter_packet_us > 0:
                inter_packet_delay = args.inter_packet_us / 1_000_000.0
            else:
                inter_packet_delay = (frame_period * args.packet_window_fraction) / max(1, expected_packets)
            sent_ms = round((time.perf_counter() - origin) * 1000.0, 3)
            started = time.perf_counter()
            packets = send_frame_precise(
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
            sent.append(
                {
                    "frame_id": frame_id,
                    "sent_ms": sent_ms,
                    "content_id": f"motion-{frame_id:06d}",
                    "motion_phase": ((frame_id - args.start_frame_id) * 7) % 32,
                    "sha256": frame_sha256(frame),
                    "packets": packets,
                }
            )
            print(
                f"motion_frame={frame_id} phase={sent[-1]['motion_phase']} "
                f"bytes={len(frame)} packets={packets} elapsed_s={elapsed:.3f}",
                flush=True,
            )
            remaining = frame_period - elapsed
            if remaining > 0 and index + 1 < args.frames:
                time.sleep(remaining)

    metadata = {
        "schema": "motion-video-sender-v1",
        "motion_content_type": MOTION_CONTENT_TYPE,
        "host": args.host,
        "port": args.port,
        "width": args.width,
        "height": args.height,
        "fps": args.fps,
        "frames": len(sent),
        "payload": args.payload,
        "inter_packet_us": args.inter_packet_us,
        "packet_window_fraction": args.packet_window_fraction,
        "start_frame_id": args.start_frame_id,
        "sent": sent,
        "total_packets": total_packets,
    }
    metadata_path = out_dir / "sender-trace.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(
        f"MOTION_VIDEO_SEND_OK motion_content_type={MOTION_CONTENT_TYPE} "
        f"fps={args.fps:g} frames={len(sent)} packets={total_packets} "
        f"target={args.host}:{args.port} report={metadata_path}",
        flush=True,
    )
    return 0


def run_self_test(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    a = make_motion_frame(800, 600, 100, 100)
    b = make_motion_frame(800, 600, 101, 100)
    if len(a) != 800 * 600 * 3:
        raise AssertionError("unexpected frame size")
    if a == b:
        raise AssertionError("motion frames must differ")
    out_dir.joinpath("self-test.json").write_text(
        json.dumps(
            {
                "status": "pass",
                "motion_content_type": MOTION_CONTENT_TYPE,
                "frame_100_sha256": frame_sha256(a),
                "frame_101_sha256": frame_sha256(b),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"MOTION_VIDEO_SENDER_SELF_TEST_OK out={out_dir}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", nargs="?")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=600)
    parser.add_argument("--fps", type=float, default=15.0)
    parser.add_argument("--frames", type=int, default=60)
    parser.add_argument("--start-frame-id", type=int, default=100)
    parser.add_argument("--payload", type=int, default=DEFAULT_PAYLOAD)
    parser.add_argument("--inter-packet-us", type=float, default=0.0)
    parser.add_argument("--packet-window-fraction", type=float, default=0.85)
    parser.add_argument("--out-dir", default="build/drm-kms-vblank-motion-tearing/sender")
    parser.add_argument("--self-test", action="store_true")
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
