#!/usr/bin/env python3
"""Probe an MJPEG endpoint and save returned JPEG frames."""

from __future__ import annotations

import argparse
import hashlib
import json
import time
import urllib.request
from pathlib import Path

from dashboard.demo_source import COLOR_BLOCKS


def extract_jpegs(buffer: bytearray) -> list[bytes]:
    frames: list[bytes] = []
    while True:
        start = buffer.find(b"\xff\xd8")
        if start < 0:
            del buffer[:-1]
            break
        end = buffer.find(b"\xff\xd9", start + 2)
        if end < 0:
            if start > 0:
                del buffer[:start]
            break
        frame = bytes(buffer[start : end + 2])
        frames.append(frame)
        del buffer[: end + 2]
    return frames


def classify_color_block(payload: bytes, threshold: float) -> dict[str, object]:
    try:
        import cv2
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("OpenCV and NumPy are required for color-block classification") from exc

    encoded = np.frombuffer(payload, dtype=np.uint8)
    bgr = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
    if bgr is None or not bgr.size:
        return {
            "color": "decode-failed",
            "rgb_mean": [0.0, 0.0, 0.0],
            "distance": 999.0,
            "pass": False,
        }

    rgb_mean = bgr[:, :, ::-1].mean(axis=(0, 1))
    best_name = ""
    best_distance = 999999.0
    for name, rgb in COLOR_BLOCKS:
        target = np.array(rgb, dtype=np.float32)
        distance = float(np.linalg.norm(rgb_mean.astype(np.float32) - target))
        if distance < best_distance:
            best_name = name
            best_distance = distance

    return {
        "color": best_name,
        "rgb_mean": [round(float(value), 2) for value in rgb_mean],
        "distance": round(best_distance, 2),
        "pass": best_distance <= threshold,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--out-dir", default="build/mjpeg-stream-probe")
    parser.add_argument("--frames", type=int, default=12)
    parser.add_argument("--min-unique", type=int, default=2)
    parser.add_argument("--expect-color-blocks", action="store_true")
    parser.add_argument("--min-colors", type=int, default=3)
    parser.add_argument("--color-distance-threshold", type=float, default=90.0)
    parser.add_argument("--timeout-sec", type=float, default=20.0)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    live_status_path = out_dir / "probe-live-status.json"

    request = urllib.request.Request(args.url, headers={"User-Agent": "fpga-hdmi-mjpeg-probe"})
    deadline = time.monotonic() + args.timeout_sec
    started_at = time.monotonic()
    buffer = bytearray()
    saved: list[dict[str, str | int]] = []
    with urllib.request.urlopen(request, timeout=args.timeout_sec) as response:
        while len(saved) < args.frames and time.monotonic() < deadline:
            chunk = response.read(4096)
            if not chunk:
                break
            buffer.extend(chunk)
            for payload in extract_jpegs(buffer):
                frame_index = len(saved)
                frame_path = out_dir / f"mjpeg-frame-{frame_index:02d}.jpg"
                frame_path.write_bytes(payload)
                saved.append({
                    "index": frame_index,
                    "file": str(frame_path),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                    "bytes": len(payload),
                    "captured_ms": round((time.monotonic() - started_at) * 1000.0, 3),
                })
                if args.expect_color_blocks:
                    saved[-1]["color_block"] = classify_color_block(payload, args.color_distance_threshold)
                live_status_path.write_text(
                    json.dumps(
                        {
                            "status": "capturing",
                            "saved_frames": len(saved),
                            "latest_captured_ms": saved[-1]["captured_ms"],
                            "latest_file": saved[-1]["file"],
                        },
                        indent=2,
                    ),
                    encoding="utf-8",
                )
                if len(saved) >= args.frames:
                    break

    unique_hashes = sorted({str(item["sha256"]) for item in saved})
    colors = [
        str(item.get("color_block", {}).get("color"))
        for item in saved
        if isinstance(item.get("color_block"), dict) and item["color_block"].get("pass")
    ]
    unique_colors = sorted(set(colors))
    color_pass = (not args.expect_color_blocks) or len(unique_colors) >= args.min_colors
    report = {
        "url": args.url,
        "frames": len(saved),
        "unique_hashes": len(unique_hashes),
        "min_unique": args.min_unique,
        "expect_color_blocks": args.expect_color_blocks,
        "unique_colors": unique_colors,
        "min_colors": args.min_colors,
        "color_distance_threshold": args.color_distance_threshold,
        "saved": saved,
        "status": "pass" if len(saved) >= args.frames and len(unique_hashes) >= args.min_unique and color_pass else "fail",
    }
    report_path = out_dir / "mjpeg-stream-probe.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    if report["status"] == "pass":
        color_text = ",".join(unique_colors) if args.expect_color_blocks else "not-checked"
        print(f"MJPEG_STREAM_PROBE_OK frames={len(saved)} unique={len(unique_hashes)} colors={color_text} report={report_path}")
        return 0

    print(f"MJPEG_STREAM_PROBE_FAIL frames={len(saved)} unique={len(unique_hashes)} colors={','.join(unique_colors)} report={report_path}")
    print(json.dumps(report, indent=2))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
