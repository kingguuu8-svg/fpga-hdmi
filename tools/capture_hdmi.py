#!/usr/bin/env python3
"""Capture and validate HDMI output through a UVC adapter."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np


BACKENDS = [
    ("dshow", cv2.CAP_DSHOW),
    ("msmf", cv2.CAP_MSMF),
    ("any", cv2.CAP_ANY),
]

BACKEND_BY_NAME = {name: backend for name, backend in BACKENDS}


def classify(kind: str, rgb: np.ndarray) -> bool:
    r, g, b = [float(v) for v in rgb]
    if kind == "dark_panel":
        return 0 <= r <= 70 and 15 <= g <= 95 and 25 <= b <= 120
    if kind == "white":
        return r > 150 and g > 150 and b > 150 and max(r, g, b) - min(r, g, b) < 90
    if kind == "red":
        return r > 130 and r > g * 1.35 and r > b * 1.35
    if kind == "green":
        return g > 120 and g > r * 1.35 and g > b * 1.35
    raise ValueError(f"unknown kind: {kind}")


def color_mask(frame_bgr: np.ndarray, kind: str) -> np.ndarray:
    b = frame_bgr[:, :, 0].astype(np.float32)
    g = frame_bgr[:, :, 1].astype(np.float32)
    r = frame_bgr[:, :, 2].astype(np.float32)
    if kind == "white":
        return (r > 150) & (g > 150) & (b > 150) & ((np.maximum.reduce([r, g, b]) - np.minimum.reduce([r, g, b])) < 90)
    if kind == "red":
        return (r > 130) & (r > g * 1.35) & (r > b * 1.35)
    if kind == "green":
        return (g > 120) & (g > r * 1.35) & (g > b * 1.35)
    raise ValueError(f"unknown mask kind: {kind}")


def roi_rgb(frame_bgr: np.ndarray, x: int, y: int, nominal_w: int = 640, nominal_h: int = 480) -> np.ndarray:
    h, w = frame_bgr.shape[:2]
    sx = int(round(x * (w - 1) / (nominal_w - 1)))
    sy = int(round(y * (h - 1) / (nominal_h - 1)))
    radius = max(2, min(w, h) // 160)
    x0 = max(0, sx - radius)
    x1 = min(w, sx + radius + 1)
    y0 = max(0, sy - radius)
    y1 = min(h, sy + radius + 1)
    bgr = frame_bgr[y0:y1, x0:x1].mean(axis=(0, 1))
    return bgr[::-1]


def grab_frames(index: int, backend_name: str, backend: int, width: int, height: int, frames: int, read_interval_ms: int) -> tuple[bool, list[np.ndarray], dict]:
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
                30,
            ],
        )
    else:
        cap = cv2.VideoCapture(index, backend)
    if not cap.isOpened():
        return False, [], {"index": index, "backend": backend_name, "opened": False}

    if backend_name != "dshow":
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        cap.set(cv2.CAP_PROP_FPS, 30)

    samples = []
    ok_count = 0
    for _ in range(frames):
        ok, candidate = cap.read()
        if ok and candidate is not None and candidate.size:
            samples.append(candidate)
            ok_count += 1
        if read_interval_ms > 0:
            time.sleep(read_interval_ms / 1000.0)
    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc_value = int(cap.get(cv2.CAP_PROP_FOURCC))
    capture_fourcc = "".join(chr((fourcc_value >> (8 * offset)) & 0xFF) for offset in range(4))
    cap.release()
    return len(samples) > 0, samples, {
        "index": index,
        "backend": backend_name,
        "opened": True,
        "frames_read": ok_count,
        "samples": len(samples),
        "width": actual_w,
        "height": actual_h,
        "fourcc": capture_fourcc,
    }


def validate_pip_frame(frame: np.ndarray) -> tuple[bool, list[dict]]:
    bg_rgb = roi_rgb(frame, 80, 80)
    background_ok = classify("dark_panel", bg_rgb)
    mean_luma = float(frame.mean())
    nonblack_ok = mean_luma > 8.0
    white_count = int(color_mask(frame, "white").sum())
    red_count = int(color_mask(frame, "red").sum())
    green_count = int(color_mask(frame, "green").sum())
    results = [
        {
            "name": "background_dark_panel",
            "nominal_xy": [80, 80],
            "expected": "dark_panel",
            "rgb_mean": [round(float(v), 2) for v in bg_rgb],
            "pass": bool(background_ok),
        },
        {
            "name": "image_not_black",
            "expected": "mean_luma_gt_8",
            "mean_luma": round(mean_luma, 2),
            "pass": bool(nonblack_ok),
        },
        {
            "name": "pip_border_white_pixels",
            "expected": "white_pixels_gt_200",
            "pixels": white_count,
            "pass": bool(white_count > 200),
        },
        {
            "name": "pip_red_marker_pixels",
            "expected": "red_pixels_gt_50",
            "pixels": red_count,
            "pass": bool(red_count > 50),
        },
        {
            "name": "pip_green_marker_pixels",
            "expected": "green_pixels_gt_50",
            "pixels": green_count,
            "pass": bool(green_count > 50),
        },
    ]
    return all(item["pass"] for item in results), results


def scale_rect(frame: np.ndarray, rect: tuple[int, int, int, int], nominal_w: int = 800, nominal_h: int = 600) -> tuple[int, int, int, int]:
    h, w = frame.shape[:2]
    x, y, rw, rh = rect
    sx0 = int(round(x * w / nominal_w))
    sy0 = int(round(y * h / nominal_h))
    sx1 = int(round((x + rw) * w / nominal_w))
    sy1 = int(round((y + rh) * h / nominal_h))
    return sx0, sy0, max(sx0 + 1, sx1), max(sy0 + 1, sy1)


def white_mask(frame_bgr: np.ndarray) -> np.ndarray:
    b = frame_bgr[:, :, 0].astype(np.float32)
    g = frame_bgr[:, :, 1].astype(np.float32)
    r = frame_bgr[:, :, 2].astype(np.float32)
    return (r > 150) & (g > 150) & (b > 150) & ((np.maximum.reduce([r, g, b]) - np.minimum.reduce([r, g, b])) < 90)


def yellow_mask(frame_bgr: np.ndarray) -> np.ndarray:
    b = frame_bgr[:, :, 0].astype(np.float32)
    g = frame_bgr[:, :, 1].astype(np.float32)
    r = frame_bgr[:, :, 2].astype(np.float32)
    return (r > 130) & (g > 110) & (b < 120) & (r > b * 1.4) & (g > b * 1.3)


PIP_OVERLAY_PRESETS = {
    "small": ((1088, 598, 160, 90), "native_720p_quarter_pip_window_1088_598_160_90"),
    "large": ((928, 508, 320, 180), "native_720p_half_pip_window_928_508_320_180"),
}


def validate_pip_overlay_frame(frame: np.ndarray, preset: str = "small") -> tuple[bool, list[dict]]:
    rect, expected_roi = PIP_OVERLAY_PRESETS[preset]
    x0, y0, x1, y1 = scale_rect(frame, rect, nominal_w=1280, nominal_h=720)
    border = max(1, int(round(2 * frame.shape[1] / 1280)))
    pip = frame[y0:y1, x0:x1]
    if pip.size == 0:
        return False, [{
            "name": "pip_roi_present",
            "expected": "roi_inside_captured_frame",
            "roi": [x0, y0, x1, y1],
            "pass": False,
        }]

    top = pip[:border, :, :]
    bottom = pip[-border:, :, :]
    left = pip[:, :border, :]
    right = pip[:, -border:, :]
    border_pixels = int(white_mask(np.concatenate([
        top.reshape((-1, 1, 3)),
        bottom.reshape((-1, 1, 3)),
        left.reshape((-1, 1, 3)),
        right.reshape((-1, 1, 3)),
    ], axis=0)).sum())
    interior = pip[border:-border, border:-border, :]
    if interior.size == 0:
        interior = pip
    interior_yellow = int(yellow_mask(interior).sum())
    interior_white = int(white_mask(interior).sum())
    interior_luma = float(interior.mean()) if interior.size else 0.0
    full_yellow = int(yellow_mask(frame).sum())
    full_uniqueish = int(np.std(interior.astype(np.float32))) if interior.size else 0

    results = [
        {
            "name": "pip_overlay_roi",
            "expected": expected_roi,
            "roi": [x0, y0, x1, y1],
            "pass": True,
        },
        {
            "name": "pip_white_border",
            "expected": "white_border_pixels_gt_250",
            "pixels": border_pixels,
            "pass": bool(border_pixels > 250),
        },
        {
            "name": "pip_interior_not_black",
            "expected": "interior_mean_luma_gt_15",
            "mean_luma": round(interior_luma, 2),
            "pass": bool(interior_luma > 15.0),
        },
        {
            "name": "pip_interior_has_source_highlight",
            "expected": "yellow_or_white_pixels_gt_10",
            "yellow_pixels": interior_yellow,
            "white_pixels": interior_white,
            "pass": bool(interior_yellow + interior_white > 10),
        },
        {
            "name": "frame_has_dynamic_source_highlight",
            "expected": "yellow_pixels_gt_50",
            "yellow_pixels": full_yellow,
            "pass": bool(full_yellow > 50),
        },
        {
            "name": "pip_interior_has_texture",
            "expected": "interior_stddev_gt_10",
            "stddev_int": full_uniqueish,
            "pass": bool(full_uniqueish > 10),
        },
    ]
    return all(item["pass"] for item in results), results


def validate_rgb_stripes(frame: np.ndarray) -> tuple[bool, list[dict]]:
    h, w = frame.shape[:2]
    x0 = w // 8
    x1 = w - x0
    stripe_rois = [
        ("top_blue", frame[h // 12 : h // 4, x0:x1], 2),
        ("middle_green", frame[5 * h // 12 : 7 * h // 12, x0:x1], 1),
        ("bottom_red", frame[3 * h // 4 : 11 * h // 12, x0:x1], 0),
    ]
    results = []
    for name, roi, dominant_index in stripe_rois:
        rgb = roi.mean(axis=(0, 1))[::-1]
        dominant = float(rgb[dominant_index])
        others = [float(rgb[index]) for index in range(3) if index != dominant_index]
        passed = dominant > 180 and max(others) < 60
        results.append({
            "name": name,
            "expected": "dominant_channel_gt_180_and_other_channels_lt_60",
            "rgb_mean": [round(float(value), 2) for value in rgb],
            "pass": bool(passed),
        })
    return all(item["pass"] for item in results), results


def validate_inverted_rgb_stripes(frame: np.ndarray) -> tuple[bool, list[dict]]:
    h, w = frame.shape[:2]
    x0 = w // 8
    x1 = w - x0
    stripe_rois = [
        ("top_yellow", frame[h // 12 : h // 4, x0:x1], (0, 1), 2),
        ("middle_magenta", frame[5 * h // 12 : 7 * h // 12, x0:x1], (0, 2), 1),
        ("bottom_cyan", frame[3 * h // 4 : 11 * h // 12, x0:x1], (1, 2), 0),
    ]
    results = []
    for name, roi, high_indices, low_index in stripe_rois:
        rgb = roi.mean(axis=(0, 1))[::-1]
        highs = [float(rgb[index]) for index in high_indices]
        low = float(rgb[low_index])
        passed = min(highs) > 180 and low < 60
        results.append({
            "name": name,
            "expected": "two_channels_gt_180_and_remaining_channel_lt_60",
            "rgb_mean": [round(float(value), 2) for value in rgb],
            "pass": bool(passed),
        })
    return all(item["pass"] for item in results), results


def validate_any_frame(frame: np.ndarray) -> tuple[bool, list[dict]]:
    mean_luma = float(frame.mean()) if frame.size else 0.0
    return frame.size > 0, [
        {
            "name": "frame_available",
            "expected": "captured_frame_has_pixels",
            "shape": list(frame.shape),
            "mean_luma": round(mean_luma, 2),
            "pass": bool(frame.size > 0),
        }
    ]


def validate_non_black(frame: np.ndarray) -> tuple[bool, list[dict]]:
    mean_luma = float(frame.mean()) if frame.size else 0.0
    non_black = frame.size > 0 and mean_luma > 8.0
    return non_black, [
        {
            "name": "frame_non_black",
            "expected": "mean_luma_gt_8",
            "shape": list(frame.shape),
            "mean_luma": round(mean_luma, 2),
            "pass": bool(non_black),
        }
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default="auto", help="'auto' or a numeric OpenCV device index")
    parser.add_argument("--backend", default="dshow", choices=["all", *BACKEND_BY_NAME.keys()])
    parser.add_argument("--max-index", type=int, default=8)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--frames", type=int, default=45)
    parser.add_argument("--read-interval-ms", type=int, default=0, help="delay between capture reads for temporal sampling")
    parser.add_argument("--save-samples", type=int, default=0, help="save N evenly spaced captured frames")
    parser.add_argument("--validation-profile", default="pip", choices=["none", "non-black", "pip", "pip-overlay", "rgb-stripes", "inverted-rgb-stripes"])
    parser.add_argument("--out-dir", default="build/reports/hdmi-capture")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    indices = range(args.max_index + 1) if args.device == "auto" else [int(args.device)]
    backends = BACKENDS if args.backend == "all" else [(args.backend, BACKEND_BY_NAME[args.backend])]
    attempts = []
    best = None
    if args.validation_profile == "none":
        validator = validate_any_frame
    elif args.validation_profile == "non-black":
        validator = validate_non_black
    elif args.validation_profile == "pip":
        validator = validate_pip_frame
    elif args.validation_profile == "pip-overlay":
        validator = validate_pip_overlay_frame
    elif args.validation_profile == "rgb-stripes":
        validator = validate_rgb_stripes
    else:
        validator = validate_inverted_rgb_stripes

    for index in indices:
        for backend_name, backend in backends:
            ok, samples, meta = grab_frames(index, backend_name, backend, args.width, args.height, args.frames, args.read_interval_ms)
            if not ok or not samples:
                attempts.append({**meta, "validation_pass": False, "checks": []})
                continue
            backend_best = None
            for sample_idx, frame in enumerate(samples):
                passed, checks = validator(frame)
                score = sum(1 for item in checks if item["pass"])
                if backend_best is None or score > backend_best["score"]:
                    backend_best = {
                        "sample": sample_idx,
                        "frame": frame,
                        "passed": passed,
                        "score": score,
                        "checks": checks,
                    }
            attempts.append({**meta, "validation_pass": backend_best["passed"], "score": backend_best["score"], "checks": backend_best["checks"]})
            if best is None or backend_best["score"] > best["score"]:
                best = {
                    "index": index,
                    "backend": backend_name,
                    "sample": backend_best["sample"],
                    "frame": backend_best["frame"],
                    "sample_frames": samples,
                    "passed": backend_best["passed"],
                    "score": backend_best["score"],
                    "checks": backend_best["checks"],
                    "meta": meta,
                }
            if backend_best["passed"]:
                break
        if best is not None and best["passed"]:
            break

    result = {
        "status": "fail",
        "validation_profile": args.validation_profile,
        "selected_index": None,
        "attempts": attempts,
        "image": None,
    }

    if best is not None:
        image_path = out_dir / "latest.png"
        cv2.imwrite(str(image_path), best["frame"])
        sample_paths = []
        if args.save_samples > 0:
            sample_frames = best.get("sample_frames", [])
            sample_count = min(args.save_samples, len(sample_frames))
            for sample_num in range(sample_count):
                if sample_count == 1:
                    sample_idx = 0
                else:
                    sample_idx = round(sample_num * (len(sample_frames) - 1) / (sample_count - 1))
                sample_path = out_dir / f"latest-sample-{sample_num:02d}.png"
                cv2.imwrite(str(sample_path), sample_frames[sample_idx])
                sample_paths.append(str(sample_path))
        result.update({
            "status": "pass" if best["passed"] else "fail",
            "selected_index": best["index"],
            "selected_backend": best["backend"],
            "selected_sample": best["sample"],
            "score": best["score"],
            "checks": best["checks"],
            "image": str(image_path),
            "samples": sample_paths,
            "frame": best["meta"],
        })

    json_path = out_dir / "latest-validation.json"
    json_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(f"HDMI_CAPTURE_IMAGE {result['image']}")
    print(f"HDMI_CAPTURE_REPORT {json_path}")
    if result["status"] == "pass":
        print(f"HDMI_CAPTURE_OK device_index={result['selected_index']} backend={result['selected_backend']} image={result['image']}")
        return 0

    print("HDMI_CAPTURE_FAIL")
    print(json.dumps(result, indent=2))
    return 1


if __name__ == "__main__":
    sys.exit(main())
