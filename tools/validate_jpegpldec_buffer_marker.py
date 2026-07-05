#!/usr/bin/env python3
"""Validate the jpegpldec top-left buffer marker in saved HDMI-return frames."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def analyze_frame(path: Path, crop_size: int) -> dict[str, object]:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        return {"path": str(path), "ok": False, "reason": "decode-failed"}

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    crop = gray[:crop_size, :crop_size]
    if crop.size == 0:
        return {"path": str(path), "ok": False, "reason": "empty-crop"}

    crop_min = int(crop.min())
    crop_max = int(crop.max())
    crop_std = float(crop.std())
    horizontal_edges = float(np.abs(np.diff(crop.astype(np.int16), axis=1)).mean())
    vertical_edges = float(np.abs(np.diff(crop.astype(np.int16), axis=0)).mean())

    return {
        "path": str(path),
        "ok": True,
        "width": int(image.shape[1]),
        "height": int(image.shape[0]),
        "crop_min": crop_min,
        "crop_max": crop_max,
        "crop_range": crop_max - crop_min,
        "crop_mean": round(float(crop.mean()), 3),
        "crop_std": round(crop_std, 3),
        "horizontal_edges": round(horizontal_edges, 3),
        "vertical_edges": round(vertical_edges, 3),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("frame_dir")
    parser.add_argument("--out", default="")
    parser.add_argument("--crop-size", type=int, default=80)
    parser.add_argument("--min-frames", type=int, default=24)
    parser.add_argument("--min-pass-frames", type=int, default=24)
    parser.add_argument("--min-range", type=float, default=180.0)
    parser.add_argument("--min-std", type=float, default=45.0)
    args = parser.parse_args()

    frame_dir = Path(args.frame_dir)
    frames = sorted(frame_dir.glob("mjpeg-frame-*.jpg"))
    if not frames:
        frames = sorted(frame_dir.glob("hdmi-motion-frame-*.jpg"))
    analyses = [analyze_frame(path, args.crop_size) for path in frames]
    pass_frames = [
        item for item in analyses
        if item.get("ok")
        and float(item.get("crop_range", 0.0)) >= args.min_range
        and float(item.get("crop_std", 0.0)) >= args.min_std
    ]
    result = {
        "frame_dir": str(frame_dir),
        "frames": len(frames),
        "pass_frames": len(pass_frames),
        "min_frames": args.min_frames,
        "min_pass_frames": args.min_pass_frames,
        "min_range": args.min_range,
        "min_std": args.min_std,
        "result": "pass"
        if len(frames) >= args.min_frames and len(pass_frames) >= args.min_pass_frames
        else "fail",
        "samples": analyses[:5],
    }

    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(result, indent=2), encoding="utf-8")

    if result["result"] == "pass":
        print(
            "JPEGPLDEC_BUFFER_MARKER_OK "
            f"frames={len(frames)} pass_frames={len(pass_frames)} "
            f"report={args.out or ''}"
        )
        return 0

    print(
        "JPEGPLDEC_BUFFER_MARKER_FAIL "
        f"frames={len(frames)} pass_frames={len(pass_frames)} "
        f"report={args.out or ''}"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
