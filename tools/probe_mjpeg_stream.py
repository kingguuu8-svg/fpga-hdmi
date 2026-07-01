#!/usr/bin/env python3
"""Probe an MJPEG endpoint and save returned JPEG frames."""

from __future__ import annotations

import argparse
import hashlib
import json
import time
import urllib.request
from pathlib import Path


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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--out-dir", default="build/mjpeg-stream-probe")
    parser.add_argument("--frames", type=int, default=12)
    parser.add_argument("--min-unique", type=int, default=2)
    parser.add_argument("--timeout-sec", type=float, default=20.0)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    request = urllib.request.Request(args.url, headers={"User-Agent": "fpga-hdmi-mjpeg-probe"})
    deadline = time.monotonic() + args.timeout_sec
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
                })
                if len(saved) >= args.frames:
                    break

    unique_hashes = sorted({str(item["sha256"]) for item in saved})
    report = {
        "url": args.url,
        "frames": len(saved),
        "unique_hashes": len(unique_hashes),
        "min_unique": args.min_unique,
        "saved": saved,
        "status": "pass" if len(saved) >= args.frames and len(unique_hashes) >= args.min_unique else "fail",
    }
    report_path = out_dir / "mjpeg-stream-probe.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    if report["status"] == "pass":
        print(f"MJPEG_STREAM_PROBE_OK frames={len(saved)} unique={len(unique_hashes)} report={report_path}")
        return 0

    print(f"MJPEG_STREAM_PROBE_FAIL frames={len(saved)} unique={len(unique_hashes)} report={report_path}")
    print(json.dumps(report, indent=2))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
