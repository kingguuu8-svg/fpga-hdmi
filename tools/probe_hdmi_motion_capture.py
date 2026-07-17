#!/usr/bin/env python3
"""Capture raw HDMI adapter frames for markerless motion validation."""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import time
from pathlib import Path

import cv2


BACKENDS = {
    "dshow": cv2.CAP_DSHOW,
    "msmf": cv2.CAP_MSMF,
    "any": cv2.CAP_ANY,
}


def open_capture(
    device: str,
    backend_name: str,
    width: int,
    height: int,
    requested_fps: float,
) -> tuple[cv2.VideoCapture, int, float]:
    backend = BACKENDS.get(backend_name, cv2.CAP_DSHOW)
    indices = range(9) if device == "auto" else [int(device)]
    last_detail = ""
    for index in indices:
        if backend_name == "dshow":
            cap = cv2.VideoCapture(
                index,
                backend,
                [
                    cv2.CAP_PROP_FRAME_WIDTH,
                    width,
                    cv2.CAP_PROP_FRAME_HEIGHT,
                    height,
                    cv2.CAP_PROP_FOURCC,
                    cv2.VideoWriter_fourcc(*"MJPG"),
                    cv2.CAP_PROP_FPS,
                    int(round(requested_fps)),
                ],
            )
        else:
            cap = cv2.VideoCapture(index, backend)
        if not cap.isOpened():
            cap.release()
            last_detail = f"device {index} did not open"
            continue
        if backend_name != "dshow":
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            cap.set(cv2.CAP_PROP_FPS, requested_fps)
        actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        if actual_w == width and actual_h == height:
            return cap, index, float(cap.get(cv2.CAP_PROP_FPS))
        actual_fps = float(cap.get(cv2.CAP_PROP_FPS))
        last_detail = f"device {index} opened as {actual_w}x{actual_h}@{actual_fps:g}"
        cap.release()
    raise RuntimeError(f"no HDMI capture device matched {width}x{height}: {last_detail}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="1")
    parser.add_argument("--backend", default="dshow", choices=sorted(BACKENDS))
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=600)
    parser.add_argument("--frames", type=int, default=120)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--timeout-sec", type=float, default=180.0)
    parser.add_argument("--out-dir", default="build/hdmi-motion-capture")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    cap, index, actual_fps = open_capture(args.device, args.backend, args.width, args.height, args.fps)
    cap_fourcc = cap.get(cv2.CAP_PROP_FOURCC)
    saved: list[dict[str, object]] = []
    read_times_ms: list[float] = []
    period = 1.0 / max(1.0, args.fps)
    started = time.monotonic()
    next_save = started
    try:
        while len(saved) < args.frames and time.monotonic() - started < args.timeout_sec:
            ok, frame = cap.read()
            if not ok or frame is None or not frame.size:
                continue
            now = time.monotonic()
            read_times_ms.append((now - started) * 1000.0)
            if now < next_save:
                continue
            next_save = max(next_save + period, now)
            ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
            if not ok:
                continue
            payload = encoded.tobytes()
            frame_index = len(saved)
            frame_path = out_dir / f"hdmi-motion-frame-{frame_index:03d}.jpg"
            frame_path.write_bytes(payload)
            saved.append(
                {
                    "index": frame_index,
                    "file": frame_path.name,
                    "sha256": hashlib.sha256(payload).hexdigest(),
                    "bytes": len(payload),
                    "captured_ms": round((now - started) * 1000.0, 3),
                }
            )
    finally:
        cap.release()

    unique_hashes = len({str(item["sha256"]) for item in saved})
    read_intervals = [b - a for a, b in zip(read_times_ms, read_times_ms[1:])]
    report = {
        "schema": "hdmi-motion-capture-v1",
        "device": index,
        "backend": args.backend,
        "width": args.width,
        "height": args.height,
        "requested_fps": args.fps,
        "capture_fps_reported": actual_fps,
        "capture_fourcc": "".join(
            chr((int(cap_fourcc) >> (8 * index)) & 0xFF) for index in range(4)
        ),
        "read_interval_ms_median": round(statistics.median(read_intervals), 3) if read_intervals else None,
        "frames": len(saved),
        "unique_hashes": unique_hashes,
        "saved": saved,
        "status": "pass" if len(saved) >= args.frames and unique_hashes >= 2 else "fail",
    }
    report_path = out_dir / "mjpeg-stream-probe.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    marker = "HDMI_MOTION_CAPTURE_OK" if report["status"] == "pass" else "HDMI_MOTION_CAPTURE_FAIL"
    print(f"{marker} frames={len(saved)} unique={unique_hashes} report={report_path}")
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
