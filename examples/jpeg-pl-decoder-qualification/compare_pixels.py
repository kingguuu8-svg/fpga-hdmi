#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path


def fnv1a32(data):
    value = 0x811C9DC5
    for byte in data:
        value ^= byte
        value = (value * 0x01000193) & 0xFFFFFFFF
    return value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("rtl_output", type=Path)
    parser.add_argument("reference_rgb", type=Path)
    parser.add_argument("out_json", type=Path)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--min-psnr-db", type=float, default=35.0)
    parser.add_argument("--expected-fnv", type=lambda value: int(value, 0))
    parser.add_argument("--raw-rgb", action="store_true")
    args = parser.parse_args()

    expected_pixels = args.width * args.height
    if args.raw_rgb:
        rtl = args.rtl_output.read_bytes()
    else:
        rtl = []
        for line in args.rtl_output.read_text(encoding="ascii").splitlines():
            token = line.strip()
            if token and not token.startswith("//"):
                value = int(token, 16)
                rtl.extend(
                    ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
                )
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
    rtl_fnv = fnv1a32(rtl)
    fnv_match = args.expected_fnv is None or rtl_fnv == args.expected_fnv
    result = {
        "width": args.width,
        "height": args.height,
        "pixels": expected_pixels,
        "mean_absolute_error": sum(abs_errors) / expected_bytes,
        "max_absolute_error": max(abs_errors),
        "mse": mse,
        "psnr_db": psnr,
        "minimum_psnr_db": args.min_psnr_db,
        "rtl_fnv1a32": f"0x{rtl_fnv:08x}",
        "expected_fnv1a32": (
            None if args.expected_fnv is None else f"0x{args.expected_fnv:08x}"
        ),
        "fnv_match": fnv_match,
        "result": "pass" if psnr >= args.min_psnr_db and fnv_match else "fail",
    }
    args.out_json.write_text(json.dumps(result, indent=2) + "\n", encoding="ascii")
    if result["result"] != "pass":
        raise SystemExit(
            "JPEG_PL_RTL_COMPARE_FAILED "
            f"psnr_db={psnr:.3f} min={args.min_psnr_db:.3f} "
            f"rtl_fnv=0x{rtl_fnv:08x} "
            f"expected_fnv={result['expected_fnv1a32']}"
        )
    print(
        "JPEG_PL_RTL_COMPARE_OK "
        f"pixels={expected_pixels} psnr_db={psnr:.3f} "
        f"mae={result['mean_absolute_error']:.3f} "
        f"max_error={result['max_absolute_error']} "
        f"rtl_fnv={result['rtl_fnv1a32']}"
    )


if __name__ == "__main__":
    main()
