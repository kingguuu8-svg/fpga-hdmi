#!/usr/bin/env python3
"""Build a unified pass-through trace from saved HDMI MJPEG evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import cv2
import numpy as np


SCHEMA = "unified-passthrough-trace-v1"
PALETTE: tuple[tuple[str, tuple[int, int, int]], ...] = (
    ("red", (255, 0, 0)),
    ("green", (0, 255, 0)),
    ("blue", (0, 0, 255)),
    ("white", (255, 255, 255)),
    ("yellow", (255, 255, 0)),
    ("cyan", (0, 255, 255)),
    ("magenta", (255, 0, 255)),
    ("orange", (255, 128, 0)),
)

MARKER_BITS = 12
MARKER_SYNC_CELLS = 2
MARKER_X = 32
MARKER_Y = 32
MARKER_CELL = 32
MARKER_INNER = 20
MARKER_THRESHOLD = 128.0


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def mean_luma(rgb: np.ndarray) -> float:
    red, green, blue = [float(value) for value in rgb]
    return round((0.2126 * red) + (0.7152 * green) + (0.0722 * blue), 3)


def content_id_for_capture(frame_id: int, color_name: str, sent_content_id: str) -> str:
    color_prefix = f"frame-{frame_id:06d}-"
    if sent_content_id.startswith(color_prefix):
        return f"{color_prefix}{color_name}"
    return f"frame-{frame_id:06d}"


def decode_frame_marker(rgb_frame: np.ndarray) -> dict[str, Any]:
    height, width = rgb_frame.shape[:2]
    marker_width = (MARKER_SYNC_CELLS + MARKER_BITS) * MARKER_CELL
    if width < MARKER_X + marker_width or height < MARKER_Y + MARKER_CELL:
        return {
            "marker_pass": False,
            "decoded_frame_id": None,
            "marker_sync_luma": [],
            "marker_luma": [],
            "marker_bits": "",
            "marker_error": "image_too_small",
        }

    pad = max(0, (MARKER_CELL - MARKER_INNER) // 2)
    cell_lumas: list[float] = []
    for cell_index in range(MARKER_SYNC_CELLS + MARKER_BITS):
        x0 = MARKER_X + (cell_index * MARKER_CELL) + pad
        y0 = MARKER_Y + pad
        patch = rgb_frame[y0 : y0 + MARKER_INNER, x0 : x0 + MARKER_INNER, :]
        patch_luma = (
            (0.2126 * patch[:, :, 0])
            + (0.7152 * patch[:, :, 1])
            + (0.0722 * patch[:, :, 2])
        )
        cell_lumas.append(float(patch_luma.mean()))

    sync_lumas = cell_lumas[:MARKER_SYNC_CELLS]
    if sync_lumas[0] >= 64.0 or sync_lumas[1] <= 192.0:
        return {
            "marker_pass": False,
            "decoded_frame_id": None,
            "marker_sync_luma": [round(value, 2) for value in sync_lumas],
            "marker_luma": [round(value, 2) for value in cell_lumas[MARKER_SYNC_CELLS:]],
            "marker_bits": "",
            "marker_error": "sync_failed",
        }

    decoded = 0
    bit_chars: list[str] = []
    data_lumas = cell_lumas[MARKER_SYNC_CELLS:]
    for bit_index, luma_value in enumerate(data_lumas):
        bit = 1 if luma_value >= MARKER_THRESHOLD else 0
        if bit:
            decoded |= 1 << bit_index
        bit_chars.append(str(bit))

    return {
        "marker_pass": True,
        "decoded_frame_id": decoded,
        "marker_sync_luma": [round(value, 2) for value in sync_lumas],
        "marker_luma": [round(value, 2) for value in data_lumas],
        "marker_bits": "".join(bit_chars),
        "marker_error": "",
    }


def classify_image(path: Path, threshold: float) -> dict[str, Any]:
    frame = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if frame is None or not frame.size:
        return {
            "color": "decode-failed",
            "pass": False,
            "marker_pass": False,
            "decoded_frame_id": None,
            "marker_sync_luma": [],
            "marker_luma": [],
            "marker_bits": "",
            "marker_error": "decode_failed",
            "rgb_mean": [0.0, 0.0, 0.0],
            "distance": 999999.0,
            "mean_luma": 0.0,
        }
    rgb_frame = frame[:, :, ::-1]
    rgb_mean = rgb_frame.mean(axis=(0, 1))
    best_name = ""
    best_distance = 999999.0
    for name, rgb in PALETTE:
        distance = float(np.linalg.norm(rgb_mean.astype(np.float32) - np.array(rgb, dtype=np.float32)))
        if distance < best_distance:
            best_name = name
            best_distance = distance
    return {
        "color": best_name,
        "pass": best_distance <= threshold,
        "rgb_mean": [round(float(value), 2) for value in rgb_mean],
        "distance": round(best_distance, 2),
        "mean_luma": mean_luma(rgb_mean),
        **decode_frame_marker(rgb_frame),
    }


def relative_image_path(trace_path: Path, image_path: Path) -> str:
    try:
        return image_path.resolve().relative_to(trace_path.parent.resolve()).as_posix()
    except ValueError:
        return image_path.resolve().as_posix()


def build_trace(args: argparse.Namespace) -> int:
    sender_json = Path(args.sender_json)
    mjpeg_report = Path(args.mjpeg_report)
    out_dir = Path(args.out_dir)
    trace_path = Path(args.trace_json) if args.trace_json else out_dir / "trace.json"
    classification_path = out_dir / "mjpeg-classification.json"
    out_dir.mkdir(parents=True, exist_ok=True)

    sender = read_json(sender_json)
    report = read_json(mjpeg_report)
    sent_source = sender.get("sent", [])
    sent = [
        {
            "frame_id": int(item["frame_id"]),
            "sent_ms": float(item["sent_ms"]) + args.sent_time_offset_ms,
            "content_id": str(item["content_id"]),
            "color": str(item["color"]),
        }
        for item in sent_source
    ]

    classified: list[dict[str, Any]] = []
    for item in report.get("saved", []):
        image_path = Path(str(item["file"]))
        if not image_path.is_absolute():
            cwd_relative = image_path.resolve()
            report_relative = (mjpeg_report.parent / image_path).resolve()
            image_path = cwd_relative if cwd_relative.exists() else report_relative
        info = classify_image(image_path, args.color_distance_threshold)
        classified.append(
            {
                "index": int(item["index"]),
                "file": str(image_path),
                "sha256": str(item["sha256"]),
                "bytes": int(item["bytes"]),
                "captured_ms_raw": float(item.get("captured_ms", item["index"] * (1000.0 / args.capture_fps))),
                **info,
            }
        )

    sent_by_id = {int(item["frame_id"]): item for item in sent}
    used_sent_ids: set[int] = set()
    raw_matches: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for capture in classified:
        decoded_frame_id = capture.get("decoded_frame_id")
        if not capture["pass"] or not capture["marker_pass"] or not isinstance(decoded_frame_id, int):
            continue
        sent_item = sent_by_id.get(decoded_frame_id)
        if sent_item is None or decoded_frame_id in used_sent_ids:
            continue
        raw_latency = float(capture["captured_ms_raw"]) - float(sent_item["sent_ms"])
        if raw_latency < args.min_raw_latency_ms or raw_latency > args.max_raw_latency_ms:
            continue
        used_sent_ids.add(decoded_frame_id)
        raw_matches.append((sent_item, capture))

    if raw_matches:
        raw_latencies = [
            float(capture["captured_ms_raw"]) - float(sent_item["sent_ms"])
            for sent_item, capture in raw_matches
        ]
        capture_clock_offset_ms = min(raw_latencies) - args.aligned_min_latency_ms
    else:
        capture_clock_offset_ms = 0.0

    captured: list[dict[str, Any]] = []
    for capture_index, (sent_item, capture) in enumerate(raw_matches):
        image_path = Path(str(capture["file"]))
        captured_ms = round(float(capture["captured_ms_raw"]) - capture_clock_offset_ms, 3)
        captured.append(
            {
                "capture_index": capture_index,
                "captured_ms": captured_ms,
                "decoded_frame_id": int(capture["decoded_frame_id"]),
                "content_id": content_id_for_capture(
                    int(capture["decoded_frame_id"]),
                    str(capture["color"]),
                    str(sent_item["content_id"]),
                ),
                "mean_luma": float(capture["mean_luma"]),
                "image_path": relative_image_path(trace_path, image_path),
                "image_sha256": sha256_file(image_path),
                "decoded_color": str(capture["color"]),
                "color_distance": float(capture["distance"]),
                "marker_bits": str(capture["marker_bits"]),
            }
        )

    trace = {
        "schema": SCHEMA,
        "trace_kind": "hardware-mjpeg-image-evidence",
        "requirements": {
            "min_match_rate": 0.95,
            "max_drop_rate": 0.05,
            "max_latency_ms": float(args.max_latency_ms),
            "max_order_violations": 0,
            "max_content_mismatches": 0,
            "max_black_frames": 0,
            "min_luma": 8.0,
            "require_image_paths": True,
        },
        "alignment": {
            "method": "image-decoded frame marker matched by frame_id; minimum raw latency aligned to non-negative latency",
            "aligned_min_latency_ms": args.aligned_min_latency_ms,
            "capture_clock_offset_ms": round(capture_clock_offset_ms, 3),
            "marker": {
                "bits": MARKER_BITS,
                "sync_cells": MARKER_SYNC_CELLS,
                "x": MARKER_X,
                "y": MARKER_Y,
                "cell": MARKER_CELL,
                "inner": MARKER_INNER,
                "threshold": MARKER_THRESHOLD,
            },
        },
        "sent": [
            {
                "frame_id": item["frame_id"],
                "sent_ms": round(float(item["sent_ms"]), 3),
                "content_id": item["content_id"],
            }
            for item in sent
        ],
        "captured": captured,
    }
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    trace_path.write_text(json.dumps(trace, indent=2), encoding="utf-8")

    unique_colors = sorted({str(item["color"]) for item in classified if item["pass"]})
    raw_latencies = [
        float(capture["captured_ms_raw"]) - float(sent_item["sent_ms"])
        for sent_item, capture in raw_matches
    ]
    summary = {
        "status": "pass" if len(captured) >= int(args.min_matched_frames) and len(unique_colors) >= int(args.min_colors) else "fail",
        "sender_json": str(sender_json),
        "mjpeg_report": str(mjpeg_report),
        "trace": str(trace_path),
        "mjpeg_saved_frames": len(classified),
        "mjpeg_unique_hashes": int(report.get("unique_hashes", len({item["sha256"] for item in classified}))),
        "mjpeg_unique_colors": len(unique_colors),
        "unique_colors": unique_colors,
        "matched_frames": len(captured),
        "decoded_marker_frames": len(
            [
                item
                for item in classified
                if item.get("marker_pass") and isinstance(item.get("decoded_frame_id"), int)
            ]
        ),
        "matched_frame_ids": [int(capture["decoded_frame_id"]) for _, capture in raw_matches],
        "capture_clock_offset_ms": round(capture_clock_offset_ms, 3),
        "sent_time_offset_ms": round(args.sent_time_offset_ms, 3),
        "raw_latency_min_ms": round(min(raw_latencies), 3) if raw_latencies else None,
        "raw_latency_max_ms": round(max(raw_latencies), 3) if raw_latencies else None,
        "palette": [{"name": name, "rgb": list(rgb)} for name, rgb in PALETTE],
    }
    classification_path.write_text(json.dumps({"summary": summary, "classified": classified}, indent=2), encoding="utf-8")

    marker_bits = (
        f"mjpeg_saved_frames={summary['mjpeg_saved_frames']} "
        f"mjpeg_unique_hashes={summary['mjpeg_unique_hashes']} "
        f"mjpeg_unique_colors={summary['mjpeg_unique_colors']} "
        f"matched_frames={summary['matched_frames']} trace={trace_path}"
    )
    if summary["status"] == "pass":
        print(f"UNIFIED_TRACE_FROM_MJPEG_OK {marker_bits}")
        return 0
    print(f"UNIFIED_TRACE_FROM_MJPEG_FAIL {marker_bits}")
    print(json.dumps(summary, indent=2))
    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sender-json", required=True)
    parser.add_argument("--mjpeg-report", required=True)
    parser.add_argument("--out-dir", default="build/unified-15fps-image-evidence-pass-through/trace")
    parser.add_argument("--trace-json", default="")
    parser.add_argument("--capture-fps", type=float, default=15.0)
    parser.add_argument("--color-distance-threshold", type=float, default=90.0)
    parser.add_argument("--min-colors", type=int, default=8)
    parser.add_argument("--min-matched-frames", type=int, default=29)
    parser.add_argument("--max-latency-ms", type=float, default=250.0)
    parser.add_argument("--min-raw-latency-ms", type=float, default=0.0)
    parser.add_argument("--max-raw-latency-ms", type=float, default=5000.0)
    parser.add_argument("--aligned-min-latency-ms", type=float, default=0.0)
    parser.add_argument("--sent-time-offset-ms", type=float, default=0.0)
    return parser


def main() -> int:
    return build_trace(build_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
