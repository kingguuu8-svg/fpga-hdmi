#!/usr/bin/env python3
"""Validate textured-motion HDMI captures for row-wise tearing."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from send_motion_video_udp import make_motion_frame


WIDTH = 800
HEIGHT = 600
PHASE_PERIOD = 32


def load_gray(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if image is None or image.size == 0:
        raise ValueError(f"failed to decode image: {path}")
    return image.astype(np.float32)


def gray_from_rgb_bytes(payload: bytes, width: int = WIDTH, height: int = HEIGHT) -> np.ndarray:
    rgb = np.frombuffer(payload, dtype=np.uint8).reshape((height, width, 3))
    return rgb[:, :, 0].astype(np.float32)


def make_torn_gray(frame_id: int, start_frame_id: int = 100) -> np.ndarray:
    top = gray_from_rgb_bytes(make_motion_frame(WIDTH, HEIGHT, frame_id, start_frame_id))
    bottom = np.roll(top, shift=14, axis=1)
    torn = top.copy()
    torn[HEIGHT // 2 :, :] = bottom[HEIGHT // 2 :, :]
    return torn


def row_phase(row: np.ndarray) -> tuple[int, float]:
    centered = row - float(np.mean(row))
    best_phase = 0
    best_score = -1.0
    x = np.arange(row.shape[0], dtype=np.int32)
    for phase in range(PHASE_PERIOD):
        template = np.where((((x + phase) // 16) & 1) != 0, 1.0, -1.0).astype(np.float32)
        score = float(np.dot(centered, template))
        if score > best_score:
            best_score = score
            best_phase = phase
    return best_phase, best_score


def circular_distance(a: int, b: int, period: int = PHASE_PERIOD) -> int:
    distance = abs(a - b) % period
    return min(distance, period - distance)


def analyze_gray(gray: np.ndarray) -> dict[str, Any]:
    if gray.shape[0] < 100 or gray.shape[1] < 100:
        raise ValueError(f"image too small: {gray.shape}")

    # Avoid capture borders and dashboard overlays; the board output itself is 800x600.
    y0 = max(0, int(gray.shape[0] * 0.10))
    y1 = min(gray.shape[0], int(gray.shape[0] * 0.90))
    x0 = max(0, int(gray.shape[1] * 0.08))
    x1 = min(gray.shape[1], int(gray.shape[1] * 0.92))
    crop = gray[y0:y1, x0:x1]

    contrast = float(np.percentile(crop, 95) - np.percentile(crop, 5))
    texture_std = float(np.std(crop))
    motion_like = contrast >= 80.0 and texture_std >= 35.0

    phases: list[int] = []
    scores: list[float] = []
    for y in range(0, crop.shape[0], 3):
        phase, score = row_phase(crop[y, :])
        phases.append(phase)
        scores.append(score)

    median_phase = int(round(float(np.median(phases)))) if phases else 0
    phase_errors = [circular_distance(phase, median_phase) for phase in phases]
    anomalous_rows = sum(1 for err in phase_errors if err >= 6)
    max_error = max(phase_errors) if phase_errors else 0
    tear_score = anomalous_rows / max(1, len(phase_errors))
    tearing = motion_like and anomalous_rows >= 16 and tear_score >= 0.08

    return {
        "motion_like": bool(motion_like),
        "contrast": round(contrast, 3),
        "texture_std": round(texture_std, 3),
        "median_phase": median_phase,
        "anomalous_rows": anomalous_rows,
        "sampled_rows": len(phases),
        "tear_score": round(tear_score, 6),
        "max_phase_error": max_error,
        "tearing": bool(tearing),
    }


def run_calibration(out_dir: Path) -> dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    good = [analyze_gray(gray_from_rgb_bytes(make_motion_frame(WIDTH, HEIGHT, 100 + i, 100))) for i in range(8)]
    bad = [analyze_gray(make_torn_gray(100 + i, 100)) for i in range(8)]
    known_good_pass = all(item["motion_like"] and not item["tearing"] for item in good)
    known_bad_torn_fail = all(item["motion_like"] and item["tearing"] for item in bad)
    result = {
        "schema": "motion-tearing-calibration-v1",
        "status": "pass" if known_good_pass and known_bad_torn_fail else "fail",
        "tearing_validator_calibrated": 1 if known_good_pass and known_bad_torn_fail else 0,
        "known_good_pass": 1 if known_good_pass else 0,
        "known_bad_torn_fail": 1 if known_bad_torn_fail else 0,
        "good": good,
        "bad": bad,
    }
    (out_dir / "motion-tearing-calibration.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def frame_duration_stddev_ms(timestamps_ms: list[float]) -> float:
    if len(timestamps_ms) < 3:
        return float("inf")
    deltas = np.diff(np.array(timestamps_ms, dtype=np.float64))
    return float(np.std(deltas))


def validate_mjpeg_report(report_path: Path, result_json: Path | None) -> dict[str, Any]:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    saved = report.get("saved", [])
    frame_results: list[dict[str, Any]] = []
    timestamps: list[float] = []
    for item in saved:
        image_path = Path(str(item["file"]))
        if not image_path.is_absolute():
            image_path = report_path.parent / image_path
        analysis = analyze_gray(load_gray(image_path))
        analysis["file"] = str(image_path)
        analysis["index"] = int(item.get("index", len(frame_results)))
        frame_results.append(analysis)
        if "captured_ms" in item:
            timestamps.append(float(item["captured_ms"]))

    captured_motion_frames = sum(1 for item in frame_results if item["motion_like"])
    tearing_frames = sum(1 for item in frame_results if item["tearing"])
    duration_stddev = frame_duration_stddev_ms(timestamps)
    result = {
        "schema": "motion-tearing-validation-v1",
        "validator_status": "pass" if captured_motion_frames >= 60 and tearing_frames == 0 else "fail",
        "captured_motion_frames": captured_motion_frames,
        "tearing_frames": tearing_frames,
        "mjpeg_frames": len(saved),
        "frame_duration_stddev_ms_from_capture": None if math.isinf(duration_stddev) else round(duration_stddev, 3),
        "frames": frame_results,
    }
    if result_json is not None:
        result_json.parent.mkdir(parents=True, exist_ok=True)
        result_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calibration", action="store_true")
    parser.add_argument("--mjpeg-report")
    parser.add_argument("--out-dir", default="build/motion-tearing-validator")
    parser.add_argument("--result-json")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    exit_ok = True
    if args.calibration:
        calibration = run_calibration(out_dir)
        if calibration["status"] == "pass":
            print(
                "MOTION_TEARING_CALIBRATION_OK "
                f"known_good_pass={calibration['known_good_pass']} "
                f"known_bad_torn_fail={calibration['known_bad_torn_fail']} "
                f"report={out_dir / 'motion-tearing-calibration.json'}"
            )
        else:
            print(json.dumps(calibration, indent=2))
            print(f"MOTION_TEARING_CALIBRATION_FAIL report={out_dir / 'motion-tearing-calibration.json'}")
            exit_ok = False

    if args.mjpeg_report:
        result_json = Path(args.result_json) if args.result_json else out_dir / "motion-tearing-validation.json"
        result = validate_mjpeg_report(Path(args.mjpeg_report), result_json)
        marker = "MOTION_TEARING_VALIDATION_OK" if result["validator_status"] == "pass" else "MOTION_TEARING_VALIDATION_FAIL"
        print(
            f"{marker} captured_motion_frames={result['captured_motion_frames']} "
            f"tearing_frames={result['tearing_frames']} "
            f"validator_status={result['validator_status']} report={result_json}"
        )
        exit_ok = exit_ok and result["validator_status"] == "pass"

    if not args.calibration and not args.mjpeg_report:
        parser.error("use --calibration, --mjpeg-report, or both")
    return 0 if exit_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
