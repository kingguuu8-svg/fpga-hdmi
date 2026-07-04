#!/usr/bin/env python3
"""Probe dashboard-to-PL PIP control latency through the active dashboard API."""

from __future__ import annotations

import argparse
import json
import statistics
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_ACTIONS = [
    "pip-top-left",
    "pip-bottom-right",
    "pip-large",
    "pip-small",
    "pip-invert",
    "pip-grayscale",
    "pip-bypass",
]


def post_action(base_url: str, action: str, timeout_s: float) -> dict[str, Any]:
    payload = json.dumps({"action": action}).encode("utf-8")
    req = urllib.request.Request(
        base_url.rstrip("/") + "/api/action",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as response:
            body = response.read()
            status = response.status
    except urllib.error.HTTPError as exc:
        body = exc.read()
        status = exc.code
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    data = json.loads(body.decode("utf-8"))
    data["http_status"] = status
    data["probe_elapsed_ms"] = round(elapsed_ms, 3)
    return data


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return values[0]
    ordered = sorted(values)
    rank = (len(ordered) - 1) * pct
    low = int(rank)
    high = min(low + 1, len(ordered) - 1)
    weight = rank - low
    return ordered[low] * (1.0 - weight) + ordered[high] * weight


def summarize(samples: list[dict[str, Any]]) -> dict[str, Any]:
    latencies = [
        float(sample["pip_control_latency_ms"])
        for sample in samples
        if sample.get("ok") and sample.get("pip_control_latency_ms") is not None
    ]
    transports = sorted({str(sample.get("pip_control_transport")) for sample in samples if sample.get("pip_control_transport")})
    return {
        "samples": len(samples),
        "ok_samples": sum(1 for sample in samples if sample.get("ok")),
        "transports": transports,
        "min_ms": round(min(latencies), 3) if latencies else None,
        "p50_ms": round(statistics.median(latencies), 3) if latencies else None,
        "p95_ms": round(percentile(latencies, 0.95), 3) if latencies else None,
        "max_ms": round(max(latencies), 3) if latencies else None,
    }


def run_self_test() -> int:
    samples = [
        {"ok": True, "pip_control_latency_ms": 1.0, "pip_control_transport": "tcp"},
        {"ok": True, "pip_control_latency_ms": 3.0, "pip_control_transport": "tcp"},
        {"ok": False, "pip_control_latency_ms": None, "pip_control_transport": "tcp-failed"},
    ]
    summary = summarize(samples)
    assert summary["samples"] == 3
    assert summary["ok_samples"] == 2
    assert summary["transports"] == ["tcp", "tcp-failed"]
    assert summary["min_ms"] == 1.0
    assert summary["p50_ms"] == 2.0
    assert summary["max_ms"] == 3.0
    print("PIP_CONTROL_LATENCY_PROBE_SELF_TEST_OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8765")
    parser.add_argument("--actions", default=",".join(DEFAULT_ACTIONS))
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--timeout-s", type=float, default=6.0)
    parser.add_argument("--out-dir", default="build/pip-control-latency-probe")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    actions = [item.strip() for item in args.actions.split(",") if item.strip()]
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    samples: list[dict[str, Any]] = []

    for _ in range(args.repeat):
        for action in actions:
            result = post_action(args.url, action, args.timeout_s)
            sample = {
                "action": action,
                "ok": bool(result.get("ok")),
                "http_status": result.get("http_status"),
                "probe_elapsed_ms": result.get("probe_elapsed_ms"),
                "pip_control_transport": result.get("pip_control_transport"),
                "pip_control_latency_ms": result.get("pip_control_latency_ms"),
                "pip_register_status": result.get("pip_register_status"),
                "error": result.get("error"),
                "detail": result.get("detail"),
            }
            samples.append(sample)
            status = sample.get("pip_register_status") or {}
            print(
                "PIP_CONTROL_LATENCY_SAMPLE "
                f"action={action} ok={int(sample['ok'])} "
                f"transport={sample.get('pip_control_transport')} "
                f"latency_ms={sample.get('pip_control_latency_ms')} "
                f"probe_elapsed_ms={sample.get('probe_elapsed_ms')} "
                f"enable={status.get('enable')} x={status.get('x')} y={status.get('y')} "
                f"scale={status.get('scale')} effect={status.get('effect')}"
            )

    summary = summarize(samples)
    report = {"url": args.url, "actions": actions, "repeat": args.repeat, "summary": summary, "samples": samples}
    report_path = out_dir / "pip-control-latency-report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    failed = [sample for sample in samples if not sample.get("ok")]
    result = "fail" if failed else "pass"
    print(
        "PIP_CONTROL_LATENCY_SUMMARY "
        f"result={result} samples={summary['samples']} ok_samples={summary['ok_samples']} "
        f"transports={','.join(summary['transports'])} "
        f"min_ms={summary['min_ms']} p50_ms={summary['p50_ms']} "
        f"p95_ms={summary['p95_ms']} max_ms={summary['max_ms']} "
        f"report={report_path}"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
