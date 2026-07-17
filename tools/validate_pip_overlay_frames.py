#!/usr/bin/env python3
"""Validate saved HDMI/JPEG frames for the current fixed PL PIP overlay."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2

from capture_hdmi import validate_pip_overlay_frame


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("frames_dir")
    parser.add_argument("--glob", default="*.jpg")
    parser.add_argument("--preset", choices=["small", "large"], default="small")
    parser.add_argument("--start-index", type=int, default=0, help="skip this many earliest frames as pipeline warm-up")
    parser.add_argument("--result-json", default="")
    args = parser.parse_args()

    frames_dir = Path(args.frames_dir)
    result_json = Path(args.result_json) if args.result_json else frames_dir / "pip-overlay-validation.json"
    results = []
    paths = sorted(frames_dir.glob(args.glob))[max(0, args.start_index) :]
    for path in paths:
        frame = cv2.imread(str(path))
        if frame is None or not frame.size:
            results.append({"file": str(path), "pass": False, "checks": [{"name": "image_decode", "pass": False}]})
            continue
        passed, checks = validate_pip_overlay_frame(frame, preset=args.preset)
        results.append({"file": str(path), "pass": bool(passed), "checks": checks})

    passed_frames = [item for item in results if item["pass"]]
    failed_frames = [item for item in results if not item["pass"]]
    report = {
        "start_index": max(0, args.start_index),
        "preset": args.preset,
        "status": "pass" if results and len(passed_frames) == len(results) else "fail",
        "frames_checked": len(results),
        "frames_passed": len(passed_frames),
        "first_pass": passed_frames[0] if passed_frames else None,
        "first_failure": failed_frames[0] if failed_frames else None,
    }
    result_json.parent.mkdir(parents=True, exist_ok=True)
    result_json.write_text(json.dumps(report, indent=2), encoding="utf-8")

    if report["status"] == "pass":
        print(
            "PIP_OVERLAY_FRAMES_OK "
            f"frames_checked={len(results)} frames_passed={len(passed_frames)} "
            f"report={result_json}"
        )
        return 0

    print(
        "PIP_OVERLAY_FRAMES_FAIL "
        f"frames_checked={len(results)} frames_passed={len(passed_frames)} "
        f"report={result_json}"
    )
    print(json.dumps(report, indent=2))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
