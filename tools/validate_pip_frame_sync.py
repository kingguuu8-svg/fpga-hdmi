#!/usr/bin/env python3
"""Validate that the PL main and PIP frame counters advance in lockstep."""

from __future__ import annotations

import argparse
import json
import re
import socket
import time
from pathlib import Path


STATUS_PATTERN = re.compile(
    r"PIP_EFFECT_STATUS .*main_frames=(?P<main>\d+) "
    r"pip_frames=(?P<pip>\d+)"
)
COUNTER_MASK = 0xFFFFFFFF


def read_status(host: str, port: int, timeout: float) -> dict[str, object]:
    started = time.perf_counter()
    with socket.create_connection((host, port), timeout=timeout) as connection:
        connection.settimeout(timeout)
        connection.sendall(b"status\n")
        chunks = []
        while True:
            chunk = connection.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if b"PIP_CONTROL_OK" in chunk:
                break
    response = b"".join(chunks).decode("ascii", errors="replace")
    match = STATUS_PATTERN.search(response)
    if match is None:
        raise RuntimeError(f"PIP status counters missing: {response!r}")
    return {
        "captured_ms": round(started * 1000.0, 3),
        "round_trip_ms": round((time.perf_counter() - started) * 1000.0, 3),
        "main_frames": int(match.group("main")),
        "pip_frames": int(match.group("pip")),
        "response": response.strip(),
    }


def counter_delta(new: int, old: int) -> int:
    return (new - old) & COUNTER_MASK


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host")
    parser.add_argument("--port", type=int, default=5012)
    parser.add_argument("--samples", type=int, default=6)
    parser.add_argument("--interval-sec", type=float, default=1.0)
    parser.add_argument("--timeout-sec", type=float, default=2.0)
    parser.add_argument("--result-json", default="")
    args = parser.parse_args()
    if args.samples < 2 or args.interval_sec <= 0 or args.timeout_sec <= 0:
        raise SystemExit("samples must be >= 2 and time values must be positive")

    samples = []
    for index in range(args.samples):
        samples.append(read_status(args.host, args.port, args.timeout_sec))
        if index + 1 < args.samples:
            time.sleep(args.interval_sec)

    intervals = []
    for previous, current in zip(samples, samples[1:]):
        main_delta = counter_delta(
            int(current["main_frames"]), int(previous["main_frames"])
        )
        pip_delta = counter_delta(
            int(current["pip_frames"]), int(previous["pip_frames"])
        )
        intervals.append(
            {
                "main_delta": main_delta,
                "pip_delta": pip_delta,
                "delta_difference": abs(main_delta - pip_delta),
            }
        )

    offsets = [
        counter_delta(int(sample["main_frames"]), int(sample["pip_frames"]))
        for sample in samples
    ]
    offset_span = max(offsets) - min(offsets)
    passed = (
        all(item["main_delta"] > 0 and item["pip_delta"] > 0 for item in intervals)
        and all(item["delta_difference"] <= 1 for item in intervals)
        and offset_span <= 1
    )
    report = {
        "schema": "pip-frame-counter-sync-v1",
        "status": "pass" if passed else "fail",
        "host": args.host,
        "port": args.port,
        "samples": samples,
        "intervals": intervals,
        "counter_offsets": offsets,
        "offset_span": offset_span,
    }
    result_path = Path(args.result_json) if args.result_json else None
    if result_path is not None:
        result_path.parent.mkdir(parents=True, exist_ok=True)
        result_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    marker = "PIP_FRAME_SYNC_OK" if passed else "PIP_FRAME_SYNC_FAIL"
    print(
        f"{marker} samples={len(samples)} offset_span={offset_span} "
        f"max_delta_difference={max(item['delta_difference'] for item in intervals)} "
        f"report={result_path or 'none'}"
    )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
