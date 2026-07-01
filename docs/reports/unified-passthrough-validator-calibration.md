# Unified Pass-Through Validator Calibration

Date: 2026-07-01

## Objective

Introduce one reusable pass-through validator that checks temporal frame
correspondence instead of visual plausibility. This cycle creates and
calibrates the validator only; it does not claim hardware pass-through.

## Frozen Pass Gate

```text
pass_condition: known_good_pass == 1 and known_bad_black_fail == 1 and
  known_bad_wrong_order_fail == 1 and known_bad_missing_frame_fail == 1 and
  known_bad_wrong_content_fail == 1 and known_bad_latency_fail == 1.
validator: python .\tools\validate_passthrough_trace.py --calibration --out-dir build\unified-passthrough-validator-calibration
```

## Changed Scope

- Added `tools/validate_passthrough_trace.py`.
- Added `docs/protocols/unified-passthrough-trace.md`.
- Registered the trace schema in `AGENTS.md`.
- Updated README, roadmap, current-cycle, cycle-log, and the pipeline skill.

## Validator Semantics

The validator consumes a decoded trace:

```text
sent frame_id/content_id/sent_ms
captured decoded_frame_id/content_id/captured_ms/mean_luma
optional image_path/image_sha256 evidence
```

It checks:

```text
match_rate >= min_match_rate
drop_rate <= max_drop_rate
latency <= max_latency_ms
frame order is monotonic
captured content_id matches sent content_id
black/no-frame captures do not count as valid frames
image fixtures exist and match sha256 when required
```

This deliberately replaces ad-hoc luma, unique-hash, and color-set validators.

## Verification

Compile check:

```text
rtk powershell.exe -NoProfile -Command "python -m py_compile tools\validate_passthrough_trace.py"
```

Result: passed.

Calibration command:

```text
rtk powershell.exe -NoProfile -Command "python .\tools\validate_passthrough_trace.py --calibration --out-dir build\unified-passthrough-validator-calibration"
```

Marker:

```text
UNIFIED_PASSTHROUGH_VALIDATOR_CALIBRATION_OK known_bad_black_fail=1 known_bad_latency_fail=1 known_bad_missing_frame_fail=1 known_bad_wrong_content_fail=1 known_bad_wrong_order_fail=1 known_good_pass=1 report=build\unified-passthrough-validator-calibration\calibration-summary.json
```

Measured pass-condition values:

```text
known_good_pass=1
known_bad_black_fail=1
known_bad_wrong_order_fail=1
known_bad_missing_frame_fail=1
known_bad_wrong_content_fail=1
known_bad_latency_fail=1
```

Calibration cases:

| Case | Expected | Actual | Required failure |
| --- | --- | --- | --- |
| `known_good` | pass | pass | none |
| `known_bad_black` | fail | fail | `black_frame` |
| `known_bad_wrong_order` | fail | fail | `frame_order_violation` |
| `known_bad_missing_frame` | fail | fail | `match_rate_below_min` |
| `known_bad_wrong_content` | fail | fail | `content_mismatch` |
| `known_bad_latency` | fail | fail | `latency_above_max` |

Important metrics from the calibration summary:

```text
known_good: matched=30/30, match_rate=1.0, drop_rate=0.0, max_latency_ms=120.0
known_bad_black: black_frames=30, match_rate=0.0, drop_rate=1.0
known_bad_wrong_order: order_violations=1
known_bad_missing_frame: matched=27/30, match_rate=0.9, drop_rate=0.1
known_bad_wrong_content: content_mismatches=1
known_bad_latency: latency_violations=30, max_latency_ms=420.0
```

## Board Action

None. This is a PC-side validator/calibration cycle only.

No Vivado build, PetaLinux build, JTAG programming, TF-card write, UART action,
Ethernet transmission, HDMI capture, or board flash write was performed.

## Evidence

- `tools/validate_passthrough_trace.py`
- `docs/protocols/unified-passthrough-trace.md`
- `build/unified-passthrough-validator-calibration/calibration-summary.json`
- `build/unified-passthrough-validator-calibration/cases/*/trace.json`
- `build/unified-passthrough-validator-calibration/cases/*/result.json`
- `build/unified-passthrough-validator-calibration/cases/*/images/*.ppm`

## Result

PASSED.

```text
pass_condition=(known_good_pass == 1 and known_bad_black_fail == 1 and known_bad_wrong_order_fail == 1 and known_bad_missing_frame_fail == 1 and known_bad_wrong_content_fail == 1 and known_bad_latency_fail == 1)
measured=(known_good_pass=1, known_bad_black_fail=1, known_bad_wrong_order_fail=1, known_bad_missing_frame_fail=1, known_bad_wrong_content_fail=1, known_bad_latency_fail=1)
```

## Residual Risks

- The validator assumes a future hardware runner can decode `frame_id` and
  `content_id` from captured HDMI frames and align capture timestamps with
  sender timestamps.
- The calibration fixtures are synthetic; they prove validator behavior, not
  hardware throughput or HDMI capture quality.
- The next hardware cycle must use this already-committed validator as its
  frozen pass gate and report frame_id correspondence, latency, and sustained
  drop rate at the selected FPS.
