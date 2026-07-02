#!/usr/bin/env python3
"""Send an image-decodable UDP video pattern for unified pass-through tests."""

from __future__ import annotations

import argparse
import hashlib
import json
import socket
import time
from pathlib import Path

from send_demo_video_udp import DEFAULT_PAYLOAD, DEFAULT_PORT, packet_header, send_frame


UNIFIED_COLORS: tuple[tuple[str, tuple[int, int, int]], ...] = (
    ("red", (255, 0, 0)),
    ("green", (0, 255, 0)),
    ("blue", (0, 0, 255)),
    ("white", (255, 255, 255)),
    ("yellow", (255, 255, 0)),
    ("cyan", (0, 255, 255)),
    ("magenta", (255, 0, 255)),
    ("orange", (255, 128, 0)),
)

MARKER_BITS = 12
MARKER_SYNC_CELLS = 2
MARKER_X = 32
MARKER_Y = 32
MARKER_CELL = 32
MARKER_INNER = 20


def color_for_frame(
    frame_id: int,
    content_hold_frames: int = 1,
    content_start_frame_id: int = 0,
) -> tuple[str, tuple[int, int, int]]:
    if content_hold_frames <= 0:
        raise ValueError("content_hold_frames must be positive")
    content_index = max(0, frame_id - content_start_frame_id) // content_hold_frames
    return UNIFIED_COLORS[content_index % len(UNIFIED_COLORS)]


def content_id_for_frame(frame_id: int, color_name: str) -> str:
    return f"frame-{frame_id:06d}-{color_name}"


def marker_geometry() -> dict[str, int]:
    return {
        "bits": MARKER_BITS,
        "sync_cells": MARKER_SYNC_CELLS,
        "x": MARKER_X,
        "y": MARKER_Y,
        "cell": MARKER_CELL,
        "inner": MARKER_INNER,
    }


def draw_marker(frame: bytearray, width: int, height: int, frame_id: int) -> None:
    marker_width = (MARKER_SYNC_CELLS + MARKER_BITS) * MARKER_CELL
    if width < MARKER_X + marker_width or height < MARKER_Y + MARKER_CELL:
        raise ValueError("frame is too small for the unified frame marker")

    pad = max(0, (MARKER_CELL - MARKER_INNER) // 2)
    cell_values = [0, 1] + [(frame_id >> bit_index) & 1 for bit_index in range(MARKER_BITS)]
    for cell_index, cell_value in enumerate(cell_values):
        rgb = (255, 255, 255) if cell_value else (0, 0, 0)
        x0 = MARKER_X + (cell_index * MARKER_CELL) + pad
        y0 = MARKER_Y + pad
        for y in range(y0, y0 + MARKER_INNER):
            row = y * width * 3
            for x in range(x0, x0 + MARKER_INNER):
                offset = row + (x * 3)
                frame[offset : offset + 3] = bytes(rgb)


def decode_marker_from_frame(frame: bytes, width: int, height: int) -> int:
    marker_width = (MARKER_SYNC_CELLS + MARKER_BITS) * MARKER_CELL
    if width < MARKER_X + marker_width or height < MARKER_Y + MARKER_CELL:
        raise ValueError("frame is too small for the unified frame marker")

    pad = max(0, (MARKER_CELL - MARKER_INNER) // 2)
    cell_lumas: list[float] = []
    for cell_index in range(MARKER_SYNC_CELLS + MARKER_BITS):
        x0 = MARKER_X + (cell_index * MARKER_CELL) + pad
        y0 = MARKER_Y + pad
        total = 0
        count = 0
        for y in range(y0, y0 + MARKER_INNER):
            row = y * width * 3
            for x in range(x0, x0 + MARKER_INNER):
                offset = row + (x * 3)
                red, green, blue = frame[offset : offset + 3]
                total += (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                count += 1
        cell_lumas.append(total / count)
    if cell_lumas[0] >= 64.0 or cell_lumas[1] <= 192.0:
        raise ValueError("frame marker sync cells are invalid")

    decoded = 0
    for bit_index in range(MARKER_BITS):
        if cell_lumas[MARKER_SYNC_CELLS + bit_index] >= 128.0:
            decoded |= 1 << bit_index
    return decoded


def make_color_frame(width: int, height: int, rgb: tuple[int, int, int], frame_id: int) -> bytes:
    frame = bytearray(bytes(rgb) * (width * height))
    draw_marker(frame, width, height, frame_id)
    return bytes(frame)


def frame_sha256(frame: bytes) -> str:
    return hashlib.sha256(frame).hexdigest()


def write_live_state(path: Path | None, state: dict[str, object]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    temporary.replace(path)


def send_frame_spread(
    sock: socket.socket,
    target: tuple[str, int],
    frame: bytes,
    width: int,
    height: int,
    frame_id: int,
    payload_size: int,
    packet_window_s: float,
) -> int:
    sent = 0
    frame_size = len(frame)
    packet_count = (frame_size + payload_size - 1) // payload_size
    start = time.perf_counter()
    interval = packet_window_s / max(1, packet_count - 1)
    for offset in range(0, frame_size, payload_size):
        payload = frame[offset : offset + payload_size]
        end = offset + len(payload) >= frame_size
        flags = 0x03 if end else 0x02
        packet = packet_header(width, height, frame_id, offset, len(payload), flags)
        sock.sendto(packet + payload, target)
        sent += 1

        next_due = start + (sent * interval)
        while True:
            remaining = next_due - time.perf_counter()
            if remaining <= 0:
                break
            if remaining > 0.002:
                time.sleep(remaining - 0.001)
            elif remaining > 0.0002:
                time.sleep(0)
            else:
                pass
    return sent


def run_sender(args: argparse.Namespace) -> int:
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.frames < 0:
        raise SystemExit("frames must be zero (continuous) or positive")
    if args.fps <= 0:
        raise SystemExit("fps must be positive")
    if args.hold_repeats <= 0:
        raise SystemExit("hold-repeats must be positive")
    if args.payload <= 0 or args.payload > 1400:
        raise SystemExit("payload must be in range 1..1400")
    if args.content_hold_frames <= 0:
        raise SystemExit("content-hold-frames must be positive")

    frame_period = 1.0 / args.fps
    inter_packet_delay = args.inter_packet_us / 1_000_000.0
    packet_window_s = frame_period * args.packet_window_fraction
    sent: list[dict[str, object]] = []
    total_packets = 0
    origin = time.perf_counter()
    live_state_path = Path(args.live_state_json) if args.live_state_json else None

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        target = (args.host, args.port)
        for warmup_index in range(args.warmup_frames):
            frame_id = args.warmup_start_frame_id + warmup_index
            color_name, rgb = color_for_frame(
                frame_id,
                args.content_hold_frames,
                args.start_frame_id,
            )
            frame = make_color_frame(args.width, args.height, rgb, frame_id)
            started = time.perf_counter()
            if args.burst or args.inter_packet_us > 0:
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
            else:
                packets = send_frame_spread(
                    sock,
                    target,
                    frame,
                    args.width,
                    args.height,
                    frame_id,
                    args.payload,
                    packet_window_s,
                )
            total_packets += packets
            elapsed = time.perf_counter() - started
            print(
                f"unified_warmup_frame={frame_id} color={color_name} "
                f"bytes={len(frame)} packets={packets} elapsed_s={elapsed:.3f}",
                flush=True,
            )
            remaining = frame_period - elapsed
            if remaining > 0:
                time.sleep(remaining)

        index = 0
        while args.frames == 0 or index < args.frames:
            frame_id = args.start_frame_id + index
            color_name, rgb = color_for_frame(
                frame_id,
                args.content_hold_frames,
                args.start_frame_id,
            )
            frame = make_color_frame(args.width, args.height, rgb, frame_id)
            sent_ms = round((time.perf_counter() - origin) * 1000.0, 3)
            packets_for_frame = 0
            elapsed = 0.0
            for repeat_index in range(args.hold_repeats):
                started = time.perf_counter()
                if args.burst or args.inter_packet_us > 0:
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
                else:
                    packets = send_frame_spread(
                        sock,
                        target,
                        frame,
                        args.width,
                        args.height,
                        frame_id,
                        args.payload,
                        packet_window_s,
                    )
                total_packets += packets
                packets_for_frame += packets
                elapsed = time.perf_counter() - started
                print(
                    f"unified_demo_frame={frame_id} repeat={repeat_index + 1}/{args.hold_repeats} "
                    f"color={color_name} sent_ms={sent_ms:.3f} bytes={len(frame)} "
                    f"packets={packets} elapsed_s={elapsed:.3f}",
                    flush=True,
                )
                remaining = frame_period - elapsed
                more_frames = args.frames == 0 or index + 1 < args.frames
                if (repeat_index + 1 < args.hold_repeats or more_frames) and remaining > 0:
                    time.sleep(remaining)
            sent_item = {
                "frame_id": frame_id,
                "sent_ms": sent_ms,
                "content_id": content_id_for_frame(frame_id, color_name),
                "color": color_name,
                "rgb": list(rgb),
                "sha256": frame_sha256(frame),
                "packets": packets_for_frame,
                "hold_repeats": args.hold_repeats,
                "elapsed_s": round(elapsed, 6),
            }
            if args.frames > 0:
                sent.append(sent_item)
            write_live_state(
                live_state_path,
                {
                    "schema": "unified-sender-live-v1",
                    "sender_kind": "unified",
                    "frame_id": frame_id,
                    "first_frame_id": args.start_frame_id,
                    "fps": args.fps,
                    "content_hold_frames": args.content_hold_frames,
                    "content_dwell_seconds": args.content_hold_frames / args.fps,
                    "width": args.width,
                    "height": args.height,
                    **sent_item,
                },
            )
            index += 1

    metadata = {
        "schema": "unified-test-sender-v1",
        "host": args.host,
        "port": args.port,
        "width": args.width,
        "height": args.height,
        "fps": args.fps,
        "frames": len(sent),
        "payload": args.payload,
        "inter_packet_us": args.inter_packet_us,
        "burst": args.burst,
        "packet_window_fraction": args.packet_window_fraction,
        "hold_repeats": args.hold_repeats,
        "content_hold_frames": args.content_hold_frames,
        "content_dwell_seconds": args.content_hold_frames / args.fps,
        "warmup_frames": args.warmup_frames,
        "warmup_start_frame_id": args.warmup_start_frame_id,
        "frame_marker": marker_geometry(),
        "palette": [{"name": name, "rgb": list(rgb)} for name, rgb in UNIFIED_COLORS],
        "sent": sent,
        "total_packets": total_packets,
    }
    metadata_path = out_dir / "sender-trace.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(
        f"UNIFIED_TEST_VIDEO_SEND_OK fps={args.fps:g} frames={len(sent)} "
        f"packets={total_packets} target={args.host}:{args.port} report={metadata_path}",
        flush=True,
    )
    return 0


def run_self_test(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    frame_id = 129
    frame = make_color_frame(800, 600, UNIFIED_COLORS[-1][1], frame_id)
    if len(frame) != 800 * 600 * 3:
        raise AssertionError("unexpected frame size")
    if decode_marker_from_frame(frame, 800, 600) != frame_id:
        raise AssertionError("frame marker did not round-trip")
    if any(rgb == (0, 0, 0) for _, rgb in UNIFIED_COLORS):
        raise AssertionError("unified validation palette must not include black")
    if color_for_frame(74, 75)[0] != "red" or color_for_frame(75, 75)[0] != "green":
        raise AssertionError("content hold cadence is incorrect")
    result = {
        "status": "pass",
        "colors": [{"name": name, "rgb": list(rgb)} for name, rgb in UNIFIED_COLORS],
        "frame_marker": marker_geometry(),
        "frame_sha256": frame_sha256(frame),
    }
    out_dir.joinpath("self-test.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"UNIFIED_TEST_VIDEO_SENDER_SELF_TEST_OK out={out_dir}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", nargs="?", help="target board IPv4 address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=600)
    parser.add_argument("--fps", type=float, default=15.0)
    parser.add_argument("--frames", type=int, default=30)
    parser.add_argument("--start-frame-id", type=int, default=0)
    parser.add_argument("--warmup-frames", type=int, default=0)
    parser.add_argument("--warmup-start-frame-id", type=int, default=0)
    parser.add_argument("--payload", type=int, default=DEFAULT_PAYLOAD)
    parser.add_argument("--inter-packet-us", type=float, default=0.0)
    parser.add_argument("--packet-window-fraction", type=float, default=0.85)
    parser.add_argument("--hold-repeats", type=int, default=1)
    parser.add_argument("--content-hold-frames", type=int, default=1)
    parser.add_argument("--live-state-json", default="")
    parser.add_argument("--burst", action="store_true", help="send each frame as a burst instead of spreading packets")
    parser.add_argument("--out-dir", default="build/unified-15fps-image-evidence-pass-through/sender")
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
