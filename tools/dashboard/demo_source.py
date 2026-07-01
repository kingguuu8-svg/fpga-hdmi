"""Deterministic non-camera demo video source."""

from __future__ import annotations

import hashlib


def make_demo_frame(width: int, height: int, frame_id: int) -> bytes:
    """Return one RGB888 frame for the fixed built-in dashboard demo."""
    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")

    data = bytearray(width * height * 3)
    pip_w = max(32, width // 5)
    pip_h = max(24, height // 5)
    travel_x = max(1, width - pip_w - 1)
    travel_y = max(1, height - pip_h - 1)
    pip_x = (frame_id * 11) % travel_x
    pip_y = (frame_id * 7) % travel_y

    for y in range(height):
        for x in range(width):
            r = (x * 255) // max(1, width - 1)
            g = (y * 255) // max(1, height - 1)
            b = ((frame_id * 13) + x // 3 + y // 2) & 0xFF

            in_pip = pip_x <= x < pip_x + pip_w and pip_y <= y < pip_y + pip_h
            if in_pip:
                local_x = x - pip_x
                local_y = y - pip_y
                border = local_x < 4 or local_y < 4 or local_x >= pip_w - 4 or local_y >= pip_h - 4
                if border:
                    r, g, b = 255, 242, 180
                else:
                    checker = ((local_x // 12) ^ (local_y // 12) ^ frame_id) & 1
                    r, g, b = (230, 72, 46) if checker else (25, 120, 210)

            idx = (y * width + x) * 3
            data[idx] = r
            data[idx + 1] = g
            data[idx + 2] = b

    return bytes(data)


def frame_sha256(frame: bytes) -> str:
    return hashlib.sha256(frame).hexdigest()
