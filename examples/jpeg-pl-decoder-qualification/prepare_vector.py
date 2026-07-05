#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def jpeg_words(data: bytes):
    words = []
    for offset in range(0, len(data), 4):
        chunk = data[offset : offset + 4]
        value = sum(byte << (8 * index) for index, byte in enumerate(chunk))
        words.append((value, (1 << len(chunk)) - 1, offset + 4 >= len(data)))
    return words


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("jpeg", type=Path)
    parser.add_argument("out_dir", type=Path)
    args = parser.parse_args()

    data = args.jpeg.read_bytes()
    image = Image.open(args.jpeg).convert("RGB")
    width, height = image.size
    if (width, height) != (1280, 720):
        raise SystemExit(f"expected 1280x720 JPEG, got {width}x{height}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    words = jpeg_words(data)
    with (args.out_dir / "jpeg_words.mem").open("w", encoding="ascii") as handle:
        for value, strobe, last in words:
            handle.write(f"{last:x}{strobe:x}{value:08x}\n")

    (args.out_dir / "software-reference.rgb").write_bytes(image.tobytes())
    metadata = {
        "jpeg": str(args.jpeg.resolve()),
        "sha256": hashlib.sha256(data).hexdigest(),
        "jpeg_bytes": len(data),
        "word_count": len(words),
        "width": width,
        "height": height,
        "pixel_count": width * height,
        "software_reference": "Pillow RGB decode",
    }
    (args.out_dir / "vector.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="ascii"
    )
    print(
        "JPEG_720P_VECTOR_OK "
        f"bytes={len(data)} words={len(words)} pixels={width * height}"
    )


if __name__ == "__main__":
    main()
