#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("rtl_hex", type=Path)
    parser.add_argument("reference_rgb", type=Path)
    parser.add_argument("out_json", type=Path)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--min-psnr-db", type=float, default=35.0)
    args = parser.parse_args()

    expected_pixels = args.width * args.height
    rtl = []
    for line in args.rtl_hex.read_text(encoding="ascii").splitlines():
        token = line.strip()
        if token and not token.startswith("//"):
            value = int(token, 16)
            rtl.extend(((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF))
    reference = args.reference_rgb.read_bytes()
    expected_bytes = expected_pixels * 3
    if len(rtl) != expected_bytes or len(reference) != expected_bytes:
        raise SystemExit(
            f"size mismatch rtl={len(rtl)} reference={len(reference)} expected={expected_bytes}"
        )

    abs_errors = [abs(a - b) for a, b in zip(rtl, reference)]
    squared_error = sum((a - b) ** 2 for a, b in zip(rtl, reference))
    mse = squared_error / expected_bytes
    psnr = float("inf") if mse == 0 else 10.0 * math.log10((255.0 * 255.0) / mse)
    result = {
        "width": args.width,
        "height": args.height,
        "pixels": expected_pixels,
        "mean_absolute_error": sum(abs_errors) / expected_bytes,
        "max_absolute_error": max(abs_errors),
        "mse": mse,
        "psnr_db": psnr,
        "minimum_psnr_db": args.min_psnr_db,
        "result": "pass" if psnr >= args.min_psnr_db else "fail",
    }
    args.out_json.write_text(json.dumps(result, indent=2) + "\n", encoding="ascii")
    if result["result"] != "pass":
        raise SystemExit(
            f"JPEG_PL_RTL_COMPARE_FAILED psnr_db={psnr:.3f} min={args.min_psnr_db:.3f}"
        )
    print(
        "JPEG_PL_RTL_COMPARE_OK "
        f"pixels={expected_pixels} psnr_db={psnr:.3f} "
        f"mae={result['mean_absolute_error']:.3f} max_error={result['max_absolute_error']}"
    )


if __name__ == "__main__":
    main()
