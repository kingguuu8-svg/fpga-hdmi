"""Deterministic non-camera demo video source."""

from __future__ import annotations

import hashlib


COLOR_BLOCKS: tuple[tuple[str, tuple[int, int, int]], ...] = (
    ("red", (255, 0, 0)),
    ("green", (0, 255, 0)),
    ("blue", (0, 0, 255)),
    ("white", (255, 255, 255)),
    ("black", (0, 0, 0)),
    ("yellow", (255, 255, 0)),
    ("cyan", (0, 255, 255)),
    ("magenta", (255, 0, 255)),
)


def color_block_for_frame(frame_id: int) -> tuple[str, tuple[int, int, int]]:
    return COLOR_BLOCKS[frame_id % len(COLOR_BLOCKS)]


def make_demo_frame(width: int, height: int, frame_id: int) -> bytes:
    """Return one full-screen RGB888 color block for the fixed demo."""
    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")

    _, rgb = color_block_for_frame(frame_id)
    return bytes(rgb) * (width * height)


def frame_sha256(frame: bytes) -> str:
    return hashlib.sha256(frame).hexdigest()
