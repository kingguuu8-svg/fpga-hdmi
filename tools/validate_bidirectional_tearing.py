#!/usr/bin/env python3
"""Validate row and column frame-boundary artifacts in HDMI captures."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import cv2
import numpy as np


X_PERIOD = 128
X_HALF_PERIOD = 64
Y_PERIOD = 96
Y_HALF_PERIOD = 48
VERTICAL_ROI = (40, 40, 760, 460)
HORIZONTAL_ROI = (820, 40, 1240, 460)


def load_gray(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if image is None or image.size == 0:
        raise ValueError(f"failed to decode image: {path}")
    return image.astype(np.float32)


def phase_for_series(
    series: np.ndarray, period: int, half_period: int
) -> tuple[np.ndarray, np.ndarray]:
    matrix = np.asarray(series, dtype=np.float32)
    axis = np.arange(matrix.shape[1], dtype=np.int32)
    templates = np.where(
        ((((axis[None, :] + np.arange(period)[:, None]) // half_period) & 1) != 0),
        1.0,
        -1.0,
    ).astype(np.float32)
    templates -= templates.mean(axis=1, keepdims=True)
    centered = matrix - matrix.mean(axis=1, keepdims=True)
    denominators = np.linalg.norm(centered, axis=1)
    template_norms = np.linalg.norm(templates, axis=1)
    scores = centered @ templates.T
    scores /= np.maximum(1.0, denominators[:, None] * template_norms[None, :])
    phases = np.argmax(scores, axis=1).astype(np.int32)
    best_scores = scores[np.arange(scores.shape[0]), phases]
    return phases, best_scores


def circular_distance(a: int, b: int, period: int) -> int:
    distance = abs(a - b) % period
    return min(distance, period - distance)


def circular_center(phases: list[int], period: int) -> int:
    if not phases:
        return 0
    angles = np.asarray(phases, dtype=np.float64) * (2.0 * math.pi / period)
    center = math.atan2(float(np.sin(angles).mean()), float(np.cos(angles).mean()))
    return int(round((center % (2.0 * math.pi)) * period / (2.0 * math.pi))) % period


def analyze_series(
    series: np.ndarray, period: int, half_period: int
) -> dict[str, Any]:
    phases_array, scores_array = phase_for_series(series, period, half_period)
    phases = [int(value) for value in phases_array]
    scores = [float(value) for value in scores_array]
    reference = circular_center(phases, period)
    errors = [circular_distance(phase, reference, period) for phase in phases]
    anomalous = sum(1 for error in errors if error >= 4)
    return {
        "reference_phase": reference,
        "anomalous_units": anomalous,
        "sampled_units": len(phases),
        "anomalous_fraction": round(anomalous / max(1, len(phases)), 6),
        "min_correlation": round(min(scores), 4) if scores else 0.0,
        "median_correlation": round(float(np.median(scores)), 4) if scores else 0.0,
    }


def analyze_gray(gray: np.ndarray) -> dict[str, Any]:
    vx0, vy0, vx1, vy1 = VERTICAL_ROI
    hx0, hy0, hx1, hy1 = HORIZONTAL_ROI
    vertical = gray[vy0:vy1, vx0:vx1]
    horizontal = gray[hy0:hy1, hx0:hx1]
    row_result = analyze_series(vertical, X_PERIOD, X_HALF_PERIOD)
    column_result = analyze_series(horizontal.T, Y_PERIOD, Y_HALF_PERIOD)
    contrast = float(np.percentile(np.concatenate([vertical.ravel(), horizontal.ravel()]), 95) - np.percentile(np.concatenate([vertical.ravel(), horizontal.ravel()]), 5))
    texture_std = float(np.std(np.concatenate([vertical.ravel(), horizontal.ravel()])))
    row_motion = contrast >= 80.0 and texture_std >= 35.0 and row_result["median_correlation"] >= 0.45
    column_motion = contrast >= 80.0 and texture_std >= 35.0 and column_result["median_correlation"] >= 0.45
    row_tearing = row_motion and row_result["anomalous_units"] >= 8 and row_result["anomalous_fraction"] >= 0.04
    column_tearing = column_motion and column_result["anomalous_units"] >= 8 and column_result["anomalous_fraction"] >= 0.04
    return {
        "row_motion_like": bool(row_motion),
        "column_motion_like": bool(column_motion),
        "contrast": round(contrast, 3),
        "texture_std": round(texture_std, 3),
        "row_phase": row_result,
        "column_phase": column_result,
        "content_hash": hashlib.sha256(cv2.resize(gray.astype(np.uint8), (64, 48), interpolation=cv2.INTER_AREA).tobytes()).hexdigest(),
        "row_tearing": bool(row_tearing),
        "column_tearing": bool(column_tearing),
        "tearing": bool(row_tearing or column_tearing),
    }


def frame_duration_stddev_ms(timestamps_ms: list[float]) -> float:
    if len(timestamps_ms) < 3:
        return float("inf")
    deltas = np.diff(np.asarray(timestamps_ms, dtype=np.float64))
    return float(np.std(deltas))


def validate_report(report_path: Path, result_json: Path | None) -> dict[str, Any]:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    frame_results: list[dict[str, Any]] = []
    timestamps: list[float] = []
    for item in report.get("saved", []):
        image_path = Path(str(item["file"]))
        if not image_path.is_absolute():
            image_path = report_path.parent / image_path
        analysis = analyze_gray(load_gray(image_path))
        analysis["file"] = str(image_path)
        analysis["index"] = int(item.get("index", len(frame_results)))
        frame_results.append(analysis)
        if "captured_ms" in item:
            timestamps.append(float(item["captured_ms"]))

    row_motion_frames = sum(1 for item in frame_results if item["row_motion_like"])
    column_motion_frames = sum(1 for item in frame_results if item["column_motion_like"])
    tearing_frames = sum(1 for item in frame_results if item["tearing"])
    unique_content_hashes = len({item["content_hash"] for item in frame_results})
    duration_stddev = frame_duration_stddev_ms(timestamps)
    result = {
        "schema": "bidirectional-motion-tearing-validation-v1",
        "validator_status": "pass" if len(frame_results) >= 60 and unique_content_hashes >= 8 and row_motion_frames >= 60 and column_motion_frames >= 60 and tearing_frames == 0 else "fail",
        "mjpeg_frames": len(frame_results),
        "unique_content_hashes": unique_content_hashes,
        "row_motion_frames": row_motion_frames,
        "column_motion_frames": column_motion_frames,
        "tearing_frames": tearing_frames,
        "frame_duration_stddev_ms_from_capture": None if math.isinf(duration_stddev) else round(duration_stddev, 3),
        "regions": {
            "vertical_stripe": VERTICAL_ROI,
            "horizontal_stripe": HORIZONTAL_ROI,
        },
        "expected_periods": {"x": X_PERIOD, "y": Y_PERIOD},
        "frames": frame_results,
    }
    if result_json is not None:
        result_json.parent.mkdir(parents=True, exist_ok=True)
        result_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mjpeg_report")
    parser.add_argument("--result-json", default="")
    args = parser.parse_args()
    result_json = Path(args.result_json) if args.result_json else None
    result = validate_report(Path(args.mjpeg_report), result_json)
    marker = "BIDIRECTIONAL_TEARING_VALIDATION_OK" if result["validator_status"] == "pass" else "BIDIRECTIONAL_TEARING_VALIDATION_FAIL"
    print(
        f"{marker} frames={result['mjpeg_frames']} "
        f"row_motion={result['row_motion_frames']} column_motion={result['column_motion_frames']} "
        f"tearing={result['tearing_frames']} report={result_json or 'none'}"
    )
    return 0 if result["validator_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
