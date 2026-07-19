#!/usr/bin/env python3
"""Measure distinct HDMI content cadence from a saved capture report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def load_small(path: Path) -> np.ndarray:
    frame = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if frame is None or frame.size == 0:
        raise ValueError(f"failed to decode capture frame: {path}")
    return cv2.resize(frame, (96, 54), interpolation=cv2.INTER_AREA).astype(np.float32)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--out-json", type=Path, required=True)
    parser.add_argument("--min-fps", type=float, default=29.5)
    parser.add_argument("--min-distinct-frames", type=int, default=120)
    parser.add_argument("--change-threshold", type=float, default=2.0)
    args = parser.parse_args()

    report = json.loads(args.report.read_text(encoding="utf-8"))
    saved = report.get("saved", [])
    if len(saved) < 2:
        raise SystemExit("at least two captured frames are required")

    previous = None
    changes = 0
    deltas: list[float] = []
    frames: list[dict[str, object]] = []
    for index, item in enumerate(saved):
        path = Path(str(item["file"]))
        if not path.is_absolute():
            path = args.report.parent / path
        current = load_small(path)
        delta = 0.0 if previous is None else float(np.mean(np.abs(current - previous)))
        if previous is not None and delta >= args.change_threshold:
            changes += 1
            deltas.append(delta)
        frames.append({
            "index": int(item.get("index", index)),
            "captured_ms": float(item.get("captured_ms", 0.0)),
            "mean_abs_delta": round(delta, 4),
            "content_changed": bool(previous is not None and delta >= args.change_threshold),
        })
        previous = current

    timestamps = [float(item.get("captured_ms", 0.0)) for item in saved]
    duration_ms = max(0.0, timestamps[-1] - timestamps[0])
    distinct_frames = changes + 1
    effective_fps = (changes * 1000.0 / duration_ms) if duration_ms > 0.0 else 0.0
    result = {
        "schema": "hdmi-content-cadence-v1",
        "status": "pass" if effective_fps >= args.min_fps and distinct_frames >= args.min_distinct_frames else "fail",
        "capture_frames": len(saved),
        "distinct_content_frames": distinct_frames,
        "content_changes": changes,
        "duration_ms": round(duration_ms, 3),
        "effective_content_fps": round(effective_fps, 3),
        "change_threshold": args.change_threshold,
        "min_fps": args.min_fps,
        "min_distinct_frames": args.min_distinct_frames,
        "change_delta_min": round(min(deltas), 4) if deltas else None,
        "change_delta_median": round(float(np.median(deltas)), 4) if deltas else None,
        "frames": frames,
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
    marker = "HDMI_CONTENT_CADENCE_OK" if result["status"] == "pass" else "HDMI_CONTENT_CADENCE_FAIL"
    print(
        f"{marker} capture_frames={len(saved)} distinct_content_frames={distinct_frames} "
        f"effective_content_fps={effective_fps:.3f} report={args.out_json}"
    )
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
