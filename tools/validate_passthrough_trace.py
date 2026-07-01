#!/usr/bin/env python3
"""Validate temporal pass-through correspondence from a decoded HDMI trace.

The validator intentionally consumes a decoded trace instead of opening HDMI
capture devices directly. A hardware runner should extract frame_id/content_id
from captured frames, then pass the resulting JSON here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCHEMA = "unified-passthrough-trace-v1"
DEFAULT_REQUIREMENTS = {
    "min_match_rate": 0.95,
    "max_drop_rate": 0.05,
    "max_latency_ms": 250.0,
    "max_order_violations": 0,
    "max_content_mismatches": 0,
    "max_black_frames": 0,
    "min_luma": 8.0,
    "require_image_paths": False,
}


@dataclass(frozen=True)
class Failure:
    code: str
    detail: str

    def to_json(self) -> dict[str, str]:
        return {"code": self.code, "detail": self.detail}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def content_id_for_frame(frame_id: int) -> str:
    return f"frame-{frame_id:06d}"


def frame_rgb(frame_id: int) -> tuple[int, int, int]:
    # Deterministic non-black palette for calibration fixtures.
    return (
        (37 * frame_id + 71) % 256,
        (83 * frame_id + 113) % 256,
        (149 * frame_id + 191) % 256,
    )


def mean_luma(rgb: tuple[int, int, int]) -> float:
    red, green, blue = rgb
    return round((0.2126 * red) + (0.7152 * green) + (0.0722 * blue), 3)


def write_ppm(path: Path, rgb: tuple[int, int, int], width: int = 32, height: int = 18) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    header = f"P6\n{width} {height}\n255\n".encode("ascii")
    path.write_bytes(header + bytes(rgb) * (width * height))
    return sha256_file(path)


def merged_requirements(trace: dict[str, Any]) -> dict[str, Any]:
    merged = dict(DEFAULT_REQUIREMENTS)
    merged.update(trace.get("requirements", {}))
    return merged


def validate_trace(trace_path: Path) -> dict[str, Any]:
    trace = read_json(trace_path)
    failures: list[Failure] = []
    if trace.get("schema") != SCHEMA:
        failures.append(Failure("schema_mismatch", f"schema={trace.get('schema')!r} expected={SCHEMA!r}"))

    req = merged_requirements(trace)
    sent = trace.get("sent", [])
    captured = trace.get("captured", [])
    if not isinstance(sent, list) or not isinstance(captured, list):
        failures.append(Failure("trace_shape", "sent and captured must both be lists"))
        sent = []
        captured = []

    sent_by_id: dict[int, dict[str, Any]] = {}
    for item in sent:
        frame_id = item.get("frame_id")
        if not isinstance(frame_id, int):
            failures.append(Failure("bad_sent_frame_id", f"sent frame_id={frame_id!r} is not an int"))
            continue
        if frame_id in sent_by_id:
            failures.append(Failure("duplicate_sent_frame", f"frame_id={frame_id}"))
        sent_by_id[frame_id] = item

    seen_capture_ids: set[int] = set()
    matched_ids: set[int] = set()
    latencies: list[float] = []
    black_frames = 0
    content_mismatches = 0
    latency_violations = 0
    order_violations = 0
    duplicate_captures = 0
    unmatched_captures = 0
    image_path_failures = 0
    previous_frame_id: int | None = None

    for index, item in enumerate(captured):
        frame_id = item.get("decoded_frame_id")
        capture_label = f"capture_index={item.get('capture_index', index)}"
        luma_value = item.get("mean_luma")
        if frame_id is None or (isinstance(luma_value, (int, float)) and float(luma_value) < float(req["min_luma"])):
            black_frames += 1
            continue
        if not isinstance(frame_id, int):
            unmatched_captures += 1
            failures.append(Failure("bad_captured_frame_id", f"{capture_label} decoded_frame_id={frame_id!r}"))
            continue

        sent_item = sent_by_id.get(frame_id)
        if sent_item is None:
            unmatched_captures += 1
            failures.append(Failure("unmatched_capture", f"{capture_label} decoded_frame_id={frame_id}"))
            continue
        if frame_id in seen_capture_ids:
            duplicate_captures += 1
            continue
        seen_capture_ids.add(frame_id)
        matched_ids.add(frame_id)

        if previous_frame_id is not None and frame_id < previous_frame_id:
            order_violations += 1
        previous_frame_id = frame_id

        if item.get("content_id") != sent_item.get("content_id"):
            content_mismatches += 1

        sent_ms = sent_item.get("sent_ms")
        captured_ms = item.get("captured_ms")
        if isinstance(sent_ms, (int, float)) and isinstance(captured_ms, (int, float)):
            latency = float(captured_ms) - float(sent_ms)
            latencies.append(latency)
            if latency < 0:
                failures.append(Failure("negative_latency", f"{capture_label} frame_id={frame_id} latency_ms={latency:.3f}"))
            if latency > float(req["max_latency_ms"]):
                latency_violations += 1
        else:
            failures.append(Failure("missing_timestamp", f"{capture_label} frame_id={frame_id}"))

        if req.get("require_image_paths"):
            image_path = item.get("image_path")
            if not isinstance(image_path, str) or not image_path:
                image_path_failures += 1
                continue
            resolved = (trace_path.parent / image_path).resolve()
            if not resolved.exists():
                image_path_failures += 1
                continue
            expected_hash = item.get("image_sha256")
            if expected_hash and sha256_file(resolved) != expected_hash:
                image_path_failures += 1

    sent_count = len(sent_by_id)
    matched_count = len(matched_ids)
    match_rate = (matched_count / sent_count) if sent_count else 0.0
    drop_rate = ((sent_count - matched_count) / sent_count) if sent_count else 1.0
    max_latency = max(latencies) if latencies else math.inf
    mean_latency = (sum(latencies) / len(latencies)) if latencies else math.inf

    if sent_count == 0:
        failures.append(Failure("no_sent_frames", "trace has no sent frames"))
    if match_rate < float(req["min_match_rate"]):
        failures.append(Failure("match_rate_below_min", f"match_rate={match_rate:.6f} min={float(req['min_match_rate']):.6f}"))
    if drop_rate > float(req["max_drop_rate"]):
        failures.append(Failure("drop_rate_above_max", f"drop_rate={drop_rate:.6f} max={float(req['max_drop_rate']):.6f}"))
    if black_frames > int(req["max_black_frames"]):
        failures.append(Failure("black_frame", f"black_frames={black_frames} max={int(req['max_black_frames'])}"))
    if order_violations > int(req["max_order_violations"]):
        failures.append(Failure("frame_order_violation", f"order_violations={order_violations} max={int(req['max_order_violations'])}"))
    if content_mismatches > int(req["max_content_mismatches"]):
        failures.append(Failure("content_mismatch", f"content_mismatches={content_mismatches} max={int(req['max_content_mismatches'])}"))
    if latency_violations:
        failures.append(Failure("latency_above_max", f"latency_violations={latency_violations} max_latency_ms={max_latency:.3f}"))
    if duplicate_captures:
        failures.append(Failure("duplicate_capture", f"duplicate_captures={duplicate_captures}"))
    if image_path_failures:
        failures.append(Failure("image_fixture_failure", f"image_path_failures={image_path_failures}"))

    result = {
        "trace": str(trace_path),
        "schema": trace.get("schema"),
        "requirements": req,
        "metrics": {
            "sent_frames": sent_count,
            "captured_frames": len(captured),
            "matched_frames": matched_count,
            "match_rate": round(match_rate, 6),
            "drop_rate": round(drop_rate, 6),
            "mean_latency_ms": None if math.isinf(mean_latency) else round(mean_latency, 3),
            "max_latency_ms": None if math.isinf(max_latency) else round(max_latency, 3),
            "latency_violations": latency_violations,
            "order_violations": order_violations,
            "content_mismatches": content_mismatches,
            "black_frames": black_frames,
            "duplicate_captures": duplicate_captures,
            "unmatched_captures": unmatched_captures,
            "image_path_failures": image_path_failures,
        },
        "failures": [failure.to_json() for failure in failures],
        "status": "pass" if not failures else "fail",
    }
    return result


def write_trace(case_dir: Path, captured_mutator: Any | None = None, frame_count: int = 30) -> Path:
    images_dir = case_dir / "images"
    sent: list[dict[str, Any]] = []
    captured: list[dict[str, Any]] = []
    frame_period_ms = 1000.0 / 15.0
    for frame_id in range(frame_count):
        content_id = content_id_for_frame(frame_id)
        sent.append(
            {
                "frame_id": frame_id,
                "sent_ms": round(frame_id * frame_period_ms, 3),
                "content_id": content_id,
            }
        )
        rgb = frame_rgb(frame_id)
        image_rel = Path("images") / f"capture-{frame_id:06d}.ppm"
        image_hash = write_ppm(case_dir / image_rel, rgb)
        captured.append(
            {
                "capture_index": frame_id,
                "captured_ms": round((frame_id * frame_period_ms) + 120.0, 3),
                "decoded_frame_id": frame_id,
                "content_id": content_id,
                "mean_luma": mean_luma(rgb),
                "image_path": str(image_rel).replace("\\", "/"),
                "image_sha256": image_hash,
            }
        )

    if captured_mutator is not None:
        captured = captured_mutator(case_dir, images_dir, captured)

    trace = {
        "schema": SCHEMA,
        "trace_kind": "synthetic-calibration",
        "requirements": {
            **DEFAULT_REQUIREMENTS,
            "require_image_paths": True,
        },
        "sent": sent,
        "captured": captured,
    }
    case_dir.mkdir(parents=True, exist_ok=True)
    trace_path = case_dir / "trace.json"
    trace_path.write_text(json.dumps(trace, indent=2), encoding="utf-8")
    return trace_path


def mutate_black(case_dir: Path, images_dir: Path, captured: list[dict[str, Any]]) -> list[dict[str, Any]]:
    black_hash = write_ppm(images_dir / "black.ppm", (0, 0, 0))
    for item in captured:
        item["decoded_frame_id"] = None
        item["content_id"] = "black"
        item["mean_luma"] = 0.0
        item["image_path"] = "images/black.ppm"
        item["image_sha256"] = black_hash
    return captured


def mutate_wrong_order(case_dir: Path, images_dir: Path, captured: list[dict[str, Any]]) -> list[dict[str, Any]]:
    captured[5], captured[6] = captured[6], captured[5]
    for index, item in enumerate(captured):
        item["capture_index"] = index
    return captured


def mutate_missing_frame(case_dir: Path, images_dir: Path, captured: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [item for item in captured if item["decoded_frame_id"] not in {5, 15, 25}]


def mutate_boundary_missing_one(case_dir: Path, images_dir: Path, captured: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [item for item in captured if item["decoded_frame_id"] != 19]


def mutate_unmatched_high_then_lower(case_dir: Path, images_dir: Path, captured: list[dict[str, Any]]) -> list[dict[str, Any]]:
    unmatched = dict(captured[0])
    unmatched["capture_index"] = 4
    unmatched["captured_ms"] = round(float(captured[3]["captured_ms"]) + 1.0, 3)
    unmatched["decoded_frame_id"] = 99
    unmatched["content_id"] = content_id_for_frame(99)
    mutated = captured[:4] + [unmatched] + captured[4:]
    for index, item in enumerate(mutated):
        item["capture_index"] = index
    return mutated


def mutate_wrong_content(case_dir: Path, images_dir: Path, captured: list[dict[str, Any]]) -> list[dict[str, Any]]:
    item = captured[7]
    wrong_rgb = frame_rgb(99)
    wrong_rel = Path("images") / "wrong-content-000007.ppm"
    item["content_id"] = "wrong-content"
    item["mean_luma"] = mean_luma(wrong_rgb)
    item["image_path"] = str(wrong_rel).replace("\\", "/")
    item["image_sha256"] = write_ppm(case_dir / wrong_rel, wrong_rgb)
    return captured


def mutate_latency(case_dir: Path, images_dir: Path, captured: list[dict[str, Any]]) -> list[dict[str, Any]]:
    for item in captured:
        item["captured_ms"] = round(float(item["captured_ms"]) + 300.0, 3)
    return captured


CALIBRATION_CASES = {
    "known_good": (None, True, None),
    "known_bad_black": (mutate_black, False, "black_frame"),
    "known_bad_wrong_order": (mutate_wrong_order, False, "frame_order_violation"),
    "known_bad_missing_frame": (mutate_missing_frame, False, "match_rate_below_min"),
    "known_bad_wrong_content": (mutate_wrong_content, False, "content_mismatch"),
    "known_bad_latency": (mutate_latency, False, "latency_above_max"),
}


def failure_codes(result: dict[str, Any]) -> set[str]:
    return {str(item["code"]) for item in result.get("failures", [])}


def run_calibration(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    cases_dir = out_dir / "cases"
    results: dict[str, dict[str, Any]] = {}
    booleans: dict[str, int] = {}
    for name, (mutator, should_pass, required_failure) in CALIBRATION_CASES.items():
        trace_path = write_trace(cases_dir / name, captured_mutator=mutator)
        result = validate_trace(trace_path)
        result_path = cases_dir / name / "result.json"
        result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        failures = {item["code"] for item in result["failures"]}
        if should_pass:
            ok = result["status"] == "pass"
            bool_name = "known_good_pass"
        else:
            ok = result["status"] == "fail" and required_failure in failures
            bool_name = f"{name}_fail"
        booleans[bool_name] = 1 if ok else 0
        results[name] = {
            "trace": str(trace_path),
            "result": str(result_path),
            "status": result["status"],
            "required_failure": required_failure,
            "failure_codes": sorted(failures),
            "metrics": result["metrics"],
            "calibration_ok": ok,
        }

    summary_status = "pass" if all(value == 1 for value in booleans.values()) else "fail"
    summary = {
        "status": summary_status,
        "pass_condition": booleans,
        "cases": results,
    }
    summary_path = out_dir / "calibration-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    marker_bits = " ".join(f"{name}={value}" for name, value in sorted(booleans.items()))
    if summary_status == "pass":
        print(f"UNIFIED_PASSTHROUGH_VALIDATOR_CALIBRATION_OK {marker_bits} report={summary_path}")
        return 0
    print(f"UNIFIED_PASSTHROUGH_VALIDATOR_CALIBRATION_FAIL {marker_bits} report={summary_path}")
    return 1


def run_boundary_order_regression(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    cases_dir = out_dir / "cases"

    calibration_dir = out_dir / "calibration"
    run_calibration(calibration_dir)
    calibration_summary = read_json(calibration_dir / "calibration-summary.json")

    boundary_trace = write_trace(
        cases_dir / "boundary_19_of_20",
        captured_mutator=mutate_boundary_missing_one,
        frame_count=20,
    )
    boundary_result = validate_trace(boundary_trace)
    boundary_result_path = boundary_trace.with_name("result.json")
    boundary_result_path.write_text(json.dumps(boundary_result, indent=2), encoding="utf-8")

    unmatched_trace = write_trace(
        cases_dir / "unmatched_high_then_lower",
        captured_mutator=mutate_unmatched_high_then_lower,
        frame_count=6,
    )
    unmatched_result = validate_trace(unmatched_trace)
    unmatched_result_path = unmatched_trace.with_name("result.json")
    unmatched_result_path.write_text(json.dumps(unmatched_result, indent=2), encoding="utf-8")
    unmatched_codes = failure_codes(unmatched_result)

    wrong_order_trace = write_trace(
        cases_dir / "wrong_order",
        captured_mutator=mutate_wrong_order,
        frame_count=8,
    )
    wrong_order_result = validate_trace(wrong_order_trace)
    wrong_order_result_path = wrong_order_trace.with_name("result.json")
    wrong_order_result_path.write_text(json.dumps(wrong_order_result, indent=2), encoding="utf-8")
    wrong_order_codes = failure_codes(wrong_order_result)

    measured = {
        "calibration_status": calibration_summary["status"],
        "boundary_19_of_20_status": boundary_result["status"],
        "boundary_19_of_20_drop_rate": boundary_result["metrics"]["drop_rate"],
        "unmatched_high_then_lower_status": unmatched_result["status"],
        "unmatched_high_then_lower_has_unmatched_capture": 1 if "unmatched_capture" in unmatched_codes else 0,
        "unmatched_high_then_lower_has_frame_order_violation": 1 if "frame_order_violation" in unmatched_codes else 0,
        "wrong_order_status": wrong_order_result["status"],
        "wrong_order_has_frame_order_violation": 1 if "frame_order_violation" in wrong_order_codes else 0,
    }
    pass_condition = (
        measured["calibration_status"] == "pass"
        and measured["boundary_19_of_20_status"] == "pass"
        and measured["boundary_19_of_20_drop_rate"] == 0.05
        and measured["unmatched_high_then_lower_status"] == "fail"
        and measured["unmatched_high_then_lower_has_unmatched_capture"] == 1
        and measured["unmatched_high_then_lower_has_frame_order_violation"] == 0
        and measured["wrong_order_status"] == "fail"
        and measured["wrong_order_has_frame_order_violation"] == 1
    )
    summary = {
        "status": "pass" if pass_condition else "fail",
        "measured": measured,
        "cases": {
            "boundary_19_of_20": {
                "trace": str(boundary_trace),
                "result": str(boundary_result_path),
                "metrics": boundary_result["metrics"],
                "failure_codes": sorted(failure_codes(boundary_result)),
            },
            "unmatched_high_then_lower": {
                "trace": str(unmatched_trace),
                "result": str(unmatched_result_path),
                "metrics": unmatched_result["metrics"],
                "failure_codes": sorted(unmatched_codes),
            },
            "wrong_order": {
                "trace": str(wrong_order_trace),
                "result": str(wrong_order_result_path),
                "metrics": wrong_order_result["metrics"],
                "failure_codes": sorted(wrong_order_codes),
            },
        },
    }
    summary_path = out_dir / "boundary-order-regression-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    marker_bits = " ".join(f"{name}={value}" for name, value in measured.items())
    if summary["status"] == "pass":
        print(f"UNIFIED_VALIDATOR_BOUNDARY_ORDER_FIX_OK {marker_bits} report={summary_path}")
        return 0
    print(f"UNIFIED_VALIDATOR_BOUNDARY_ORDER_FIX_FAIL {marker_bits} report={summary_path}")
    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", nargs="?", help="decoded pass-through trace JSON")
    parser.add_argument("--result-json", help="write validation result JSON")
    parser.add_argument("--calibration", action="store_true", help="generate and run synthetic calibration cases")
    parser.add_argument("--boundary-order-regression", action="store_true", help="run boundary and order defect regressions")
    parser.add_argument("--out-dir", default="build/unified-passthrough-validator-calibration")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.calibration:
        return run_calibration(Path(args.out_dir))
    if args.boundary_order_regression:
        return run_boundary_order_regression(Path(args.out_dir))
    if not args.trace:
        parser.error("trace is required unless --calibration or --boundary-order-regression is used")
    trace_path = Path(args.trace)
    result = validate_trace(trace_path)
    result_json = Path(args.result_json) if args.result_json else trace_path.with_name("validation-result.json")
    result_json.parent.mkdir(parents=True, exist_ok=True)
    result_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
    if result["status"] == "pass":
        print(f"UNIFIED_PASSTHROUGH_TRACE_OK trace={trace_path} result={result_json}")
        return 0
    print(f"UNIFIED_PASSTHROUGH_TRACE_FAIL trace={trace_path} result={result_json}")
    print(json.dumps(result, indent=2))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
