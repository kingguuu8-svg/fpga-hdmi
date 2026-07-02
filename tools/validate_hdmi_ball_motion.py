#!/usr/bin/env python3
"""Validate HDMI samples for GStreamer videotestsrc ball motion."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np


def frame_hash(gray: np.ndarray) -> str:
    small = cv2.resize(gray, (64, 48), interpolation=cv2.INTER_AREA)
    return hashlib.sha256(small.tobytes()).hexdigest()


def analyze_frame(path: Path, threshold: int, raw_width: int, raw_height: int, raw_format: str) -> dict:
    if raw_width > 0 and raw_height > 0:
        data = path.read_bytes()
        expected = raw_width * raw_height * 3
        if len(data) != expected:
            frame = None
        else:
            raw = np.frombuffer(data, dtype=np.uint8).reshape((raw_height, raw_width, 3))
            if raw_format == "rgb":
                frame = raw[:, :, ::-1].copy()
            elif raw_format == "bgr":
                frame = raw.copy()
            else:
                raise ValueError(f"unsupported raw format: {raw_format}")
    else:
        frame = cv2.imread(str(path))

    if frame is None or frame.size == 0:
        return {
            "path": str(path),
            "readable": False,
            "mean_luma": 0.0,
            "bright_pixels": 0,
            "centroid": None,
            "hash": None,
        }

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    mask = gray >= threshold
    ys, xs = np.where(mask)
    centroid = None
    if len(xs) > 0:
        centroid = [round(float(xs.mean()), 3), round(float(ys.mean()), 3)]

    return {
        "path": str(path),
        "readable": True,
        "shape": list(frame.shape),
        "mean_luma": round(float(gray.mean()), 3),
        "bright_pixels": int(len(xs)),
        "centroid": centroid,
        "hash": frame_hash(gray),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("samples_glob")
    parser.add_argument("--out-json", default="")
    parser.add_argument("--threshold", type=int, default=180)
    parser.add_argument("--min-samples", type=int, default=12)
    parser.add_argument("--min-unique-hashes", type=int, default=4)
    parser.add_argument("--min-frames-with-ball", type=int, default=8)
    parser.add_argument("--min-bright-pixels", type=int, default=50)
    parser.add_argument("--min-centroid-span", type=float, default=20.0)
    parser.add_argument("--raw-width", type=int, default=0)
    parser.add_argument("--raw-height", type=int, default=0)
    parser.add_argument("--raw-format", default="rgb", choices=["rgb", "bgr"])
    args = parser.parse_args()

    paths = sorted(Path().glob(args.samples_glob))
    frames = [
        analyze_frame(path, args.threshold, args.raw_width, args.raw_height, args.raw_format)
        for path in paths
    ]
    readable = [item for item in frames if item["readable"]]
    hashes = {item["hash"] for item in readable if item["hash"]}
    ball_frames = [
        item for item in readable
        if item["bright_pixels"] >= args.min_bright_pixels and item["centroid"] is not None
    ]
    xs = [item["centroid"][0] for item in ball_frames]
    ys = [item["centroid"][1] for item in ball_frames]
    x_span = max(xs) - min(xs) if xs else 0.0
    y_span = max(ys) - min(ys) if ys else 0.0
    centroid_span = max(x_span, y_span)

    checks = {
        "sample_count_ok": len(readable) >= args.min_samples,
        "unique_hashes_ok": len(hashes) >= args.min_unique_hashes,
        "frames_with_ball_ok": len(ball_frames) >= args.min_frames_with_ball,
        "centroid_motion_ok": centroid_span >= args.min_centroid_span,
    }
    status = "pass" if all(checks.values()) else "fail"
    result = {
        "status": status,
        "samples_glob": args.samples_glob,
        "sample_count": len(readable),
        "unique_hashes": len(hashes),
        "frames_with_ball": len(ball_frames),
        "x_span": round(float(x_span), 3),
        "y_span": round(float(y_span), 3),
        "centroid_span": round(float(centroid_span), 3),
        "threshold": args.threshold,
        "checks": checks,
        "frames": frames,
    }

    if args.out_json:
        out_path = Path(args.out_json)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(json.dumps({
        "status": status,
        "sample_count": result["sample_count"],
        "unique_hashes": result["unique_hashes"],
        "frames_with_ball": result["frames_with_ball"],
        "x_span": result["x_span"],
        "y_span": result["y_span"],
        "checks": checks,
    }, indent=2))
    if status == "pass":
        print(
            "HDMI_BALL_MOTION_OK "
            f"samples={result['sample_count']} unique_hashes={result['unique_hashes']} "
            f"frames_with_ball={result['frames_with_ball']} "
            f"x_span={result['x_span']} y_span={result['y_span']}"
        )
        return 0

    print("HDMI_BALL_MOTION_FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
