#!/usr/bin/env python3
"""Generate a deterministic 1280x720 baseline JPEG sequence for display tests."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np


def make_frame(width: int, height: int, frame_id: int) -> np.ndarray:
    phase_x = (frame_id * 7) % 128
    phase_y = (frame_id * 5) % 96
    x = np.arange(width, dtype=np.int32)[None, :]
    y = np.arange(height, dtype=np.int32)[:, None]
    frame = np.full((height, width, 3), 35, dtype=np.uint8)

    # Left region: x-only variation. A row-wise phase jump exposes a frame
    # boundary introduced while the display scans out the buffer.
    vertical = np.where((((x + phase_x) // 64) & 1) != 0, 210, 35).astype(np.uint8)
    frame[:, : int(width * 0.625), :] = np.repeat(vertical[:, :, None], 3, axis=2)[:, : int(width * 0.625), :]

    # Upper-right region: y-only variation. A column-wise phase jump exposes
    # the complementary vertical seam that a vertical-stripe-only source misses.
    horizontal = np.where((((y + phase_y) // 48) & 1) != 0, 210, 35).astype(np.uint8)
    right = frame[:, int(width * 0.625) :, :]
    right[: int(height * 0.667), :, :] = np.repeat(horizontal[:, :, None], 3, axis=2)[:, : right.shape[1], :][: int(height * 0.667), :, :]

    # Keep a stable boundary between the two diagnostic regions.
    boundary_x = int(width * 0.625)
    cv2.line(frame, (boundary_x, 0), (boundary_x, int(height * 0.667)), (245, 245, 245), 2)
    return frame


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", default="build/rtp-jpeg-tearing-sequence")
    parser.add_argument("--frames", type=int, default=120)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--quality", type=int, default=95)
    args = parser.parse_args()

    if args.frames <= 0 or args.width != 1280 or args.height != 720:
        raise SystemExit("this test sequence is fixed at 1280x720 and needs a positive frame count")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for frame_id in range(args.frames):
        frame = make_frame(args.width, args.height, frame_id)
        ok, encoded = cv2.imencode(
            ".jpg",
            frame,
            [int(cv2.IMWRITE_JPEG_QUALITY), args.quality],
        )
        if not ok:
            raise RuntimeError(f"JPEG encode failed for frame {frame_id}")
        path = out_dir / f"frame-{frame_id:04d}.jpg"
        payload = encoded.tobytes()
        path.write_bytes(payload)
        entries.append(
            {
                "frame_id": frame_id,
                "file": path.name,
                "bytes": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
                "phase": (frame_id * 5) % 32,
            }
        )

    report = {
        "schema": "rtp-jpeg-tearing-sequence-v1",
        "width": args.width,
        "height": args.height,
        "fps": 30,
        "quality": args.quality,
        "source_vertical_stripe_width": 64,
        "source_horizontal_stripe_width": 48,
        "expected_output_period_x": 128,
        "expected_output_period_y": 96,
        "frames": entries,
    }
    report_path = out_dir / "sequence.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(
        "RTP_JPEG_TEARING_SEQUENCE_OK "
        f"frames={len(entries)} size={args.width}x{args.height} "
        f"report={report_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
