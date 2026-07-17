#!/usr/bin/env python3
"""Capture and validate the official HelloFPGA VDMA HDMI color-bar demo."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np


BACKENDS = [
    ("dshow", cv2.CAP_DSHOW),
    ("msmf", cv2.CAP_MSMF),
    ("any", cv2.CAP_ANY),
]

BACKEND_BY_NAME = {name: backend for name, backend in BACKENDS}


def grab_frames(index: int, backend_name: str, backend: int, width: int, height: int, frames: int) -> tuple[bool, list[np.ndarray], dict]:
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

    samples: list[np.ndarray] = []
    for _ in range(frames):
        ok, frame = cap.read()
        if ok and frame is not None and frame.size:
            samples.append(frame)

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc_value = int(cap.get(cv2.CAP_PROP_FOURCC))
    capture_fourcc = "".join(chr((fourcc_value >> (8 * offset)) & 0xFF) for offset in range(4))
    cap.release()
    return bool(samples), samples, {
        "index": index,
        "backend": backend_name,
        "opened": True,
        "frames_read": len(samples),
        "width": actual_w,
        "height": actual_h,
        "fourcc": capture_fourcc,
    }


def roi_rgb(frame_bgr: np.ndarray, x_frac: float, y_frac: float = 0.5) -> np.ndarray:
    h, w = frame_bgr.shape[:2]
    x = int(round((w - 1) * x_frac))
    y = int(round((h - 1) * y_frac))
    radius = max(4, min(w, h) // 60)
    x0 = max(0, x - radius)
    x1 = min(w, x + radius + 1)
    y0 = max(0, y - radius)
    y1 = min(h, y + radius + 1)
    bgr = frame_bgr[y0:y1, x0:x1].mean(axis=(0, 1))
    return bgr[::-1]


def validate_frame(frame: np.ndarray) -> tuple[bool, list[dict]]:
    probes = [roi_rgb(frame, frac) for frac in (0.125, 0.375, 0.625, 0.875)]
    means = [[round(float(v), 2) for v in rgb] for rgb in probes]
    lumas = [float(rgb.mean()) for rgb in probes]
    chromas = [float(rgb.max() - rgb.min()) for rgb in probes]
    distances = [
        float(np.linalg.norm(probes[i] - probes[j]))
        for i in range(len(probes))
        for j in range(i + 1, len(probes))
    ]

    first_bar_bright = lumas[0] > 120 and chromas[0] < 90
    colored_bars_saturated = all(chroma > 70 for chroma in chromas[1:])
    bars_distinct = min(distances) > 45
    frame_not_black = float(frame.mean()) > 20
    vertical_structure = True
    for frac, rgb in zip((0.125, 0.375, 0.625, 0.875), probes):
        top = roi_rgb(frame, frac, 0.25)
        bottom = roi_rgb(frame, frac, 0.75)
        if float(np.linalg.norm(top - rgb)) > 55 or float(np.linalg.norm(bottom - rgb)) > 55:
            vertical_structure = False
            break

    checks = [
        {"name": "frame_not_black", "expected": "mean_gt_20", "mean": round(float(frame.mean()), 2), "pass": frame_not_black},
        {"name": "first_bar_bright", "expected": "bright_low_chroma", "rgb": means[0], "pass": first_bar_bright},
        {"name": "colored_bars_saturated", "expected": "last_three_chroma_gt_70", "chromas": [round(v, 2) for v in chromas], "pass": colored_bars_saturated},
        {"name": "bars_distinct", "expected": "min_pairwise_distance_gt_45", "min_distance": round(min(distances), 2), "pass": bars_distinct},
        {"name": "vertical_structure", "expected": "same_bar_color_top_mid_bottom", "pass": vertical_structure},
        {"name": "bar_rgb_means", "expected": "four_vertical_bars", "rgb": means, "pass": True},
    ]
    return all(item["pass"] for item in checks if item["name"] != "bar_rgb_means"), checks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default="auto", help="'auto' or a numeric OpenCV device index")
    parser.add_argument("--backend", default="dshow", choices=["all", *BACKEND_BY_NAME.keys()])
    parser.add_argument("--max-index", type=int, default=8)
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=600)
    parser.add_argument("--frames", type=int, default=60)
    parser.add_argument("--save-samples", type=int, default=3)
    parser.add_argument("--out-dir", default="build/reports/vdma-hdmi-capture")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    indices = range(args.max_index + 1) if args.device == "auto" else [int(args.device)]
    backends = BACKENDS if args.backend == "all" else [(args.backend, BACKEND_BY_NAME[args.backend])]
    attempts = []
    best = None

    for index in indices:
        for backend_name, backend in backends:
            ok, samples, meta = grab_frames(index, backend_name, backend, args.width, args.height, args.frames)
            if not ok:
                attempts.append({**meta, "validation_pass": False, "checks": []})
                continue

            backend_best = None
            for sample_idx, frame in enumerate(samples):
                passed, checks = validate_frame(frame)
                score = sum(1 for item in checks if item["pass"])
                if backend_best is None or score > backend_best["score"]:
                    backend_best = {"sample": sample_idx, "frame": frame, "passed": passed, "score": score, "checks": checks}

            attempts.append({**meta, "validation_pass": backend_best["passed"], "score": backend_best["score"], "checks": backend_best["checks"]})
            if best is None or backend_best["score"] > best["score"]:
                best = {**backend_best, "index": index, "backend": backend_name, "meta": meta, "sample_frames": samples}
            if backend_best["passed"]:
                break
        if best is not None and best["passed"]:
            break

    result = {"status": "fail", "selected_index": None, "attempts": attempts, "image": None}
    if best is not None:
        image_path = out_dir / "latest.png"
        cv2.imwrite(str(image_path), best["frame"])
        sample_paths = []
        sample_count = min(args.save_samples, len(best["sample_frames"]))
        for sample_num in range(sample_count):
            sample_idx = round(sample_num * (len(best["sample_frames"]) - 1) / max(1, sample_count - 1))
            sample_path = out_dir / f"latest-sample-{sample_num:02d}.png"
            cv2.imwrite(str(sample_path), best["sample_frames"][sample_idx])
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

    report_path = out_dir / "latest-validation.json"
    report_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(f"VDMA_COLORBAR_CAPTURE_IMAGE {result['image']}")
    print(f"VDMA_COLORBAR_CAPTURE_REPORT {report_path}")
    if result["status"] == "pass":
        print(f"VDMA_COLORBAR_CAPTURE_OK device_index={result['selected_index']} backend={result['selected_backend']} image={result['image']}")
        return 0

    print("VDMA_COLORBAR_CAPTURE_FAIL")
    print(json.dumps(result, indent=2))
    return 1


if __name__ == "__main__":
    sys.exit(main())
