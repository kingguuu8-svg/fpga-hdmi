# Unified Validator Boundary Order Fix

Date: 2026-07-01

## Objective

Fix the two validator defects identified by the third-party review of
`unified-passthrough-validator-calibration`:

- Exact 95% boundary handling: 19/20 matched frames must pass with
  `drop_rate=0.05`.
- Unmatched captures must not create spurious `frame_order_violation` failures
  for later legitimate frames.

This is a PC-side validator defect-fix cycle. It does not claim hardware
pass-through.

## Frozen Pass Gate

```text
pass_condition: calibration_status == pass and boundary_19_of_20_status ==
  pass and boundary_19_of_20_drop_rate == 0.05 and
  unmatched_high_then_lower_status == fail and
  unmatched_high_then_lower_has_unmatched_capture == 1 and
  unmatched_high_then_lower_has_frame_order_violation == 0 and
  wrong_order_status == fail and wrong_order_has_frame_order_violation == 1.
validator: already-committed tools/validate_passthrough_trace.py direct trace
  validation commands; no new primary validator script may be introduced in
  this cycle.
```

## Changed Scope

- `tools/validate_passthrough_trace.py`
  - Computes `drop_rate` directly from integer counts:
    `(sent_count - matched_count) / sent_count`.
  - Performs order checks only after a captured frame is matched and not a
    duplicate, so unmatched captures do not mutate the order baseline.
  - Adds regression trace generation and summary reporting through
    `--boundary-order-regression`.
- `docs/protocols/unified-passthrough-trace.md`
  - Clarifies exact drop-rate and order-check semantics.
- `docs/current-cycle.md`
  - Closes the cycle, records the measured pass condition, and points the next
    cycle back to the 15 fps hardware run.
- `docs/cycle-log.md`
  - Records this completed cycle with the frozen pass condition and measured
    values.
- `docs/project-roadmap.md`, `README.md`, and
  `skills/zynq7020-pipeline/SKILL.md`
  - Register the verified boundary/order regression before the next hardware
    pass-through claim.

## Verification

Compile check:

```text
rtk powershell.exe -NoProfile -Command "python -m py_compile tools\validate_passthrough_trace.py"
```

Result: passed.

Existing calibration still passes:

```text
rtk powershell.exe -NoProfile -Command "python .\tools\validate_passthrough_trace.py --calibration --out-dir build\unified-validator-boundary-order-fix\calibration-only"
```

Marker:

```text
UNIFIED_PASSTHROUGH_VALIDATOR_CALIBRATION_OK known_bad_black_fail=1 known_bad_latency_fail=1 known_bad_missing_frame_fail=1 known_bad_wrong_content_fail=1 known_bad_wrong_order_fail=1 known_good_pass=1
```

Boundary/order regression:

```text
rtk powershell.exe -NoProfile -Command "python .\tools\validate_passthrough_trace.py --boundary-order-regression --out-dir build\unified-validator-boundary-order-fix"
```

Marker:

```text
UNIFIED_VALIDATOR_BOUNDARY_ORDER_FIX_OK calibration_status=pass boundary_19_of_20_status=pass boundary_19_of_20_drop_rate=0.05 unmatched_high_then_lower_status=fail unmatched_high_then_lower_has_unmatched_capture=1 unmatched_high_then_lower_has_frame_order_violation=0 wrong_order_status=fail wrong_order_has_frame_order_violation=1
```

Measured values:

```text
calibration_status=pass
boundary_19_of_20_status=pass
boundary_19_of_20_drop_rate=0.05
unmatched_high_then_lower_status=fail
unmatched_high_then_lower_has_unmatched_capture=1
unmatched_high_then_lower_has_frame_order_violation=0
wrong_order_status=fail
wrong_order_has_frame_order_violation=1
```

Regression case details:

| Case | Expected | Measured |
| --- | --- | --- |
| `boundary_19_of_20` | PASS at exact boundary | `sent=20`, `matched=19`, `match_rate=0.95`, `drop_rate=0.05`, no failures |
| `unmatched_high_then_lower` | FAIL only for unmatched capture | `unmatched_captures=1`, failure codes: `unmatched_capture`, `order_violations=0` |
| `wrong_order` | FAIL for real order violation | `order_violations=1`, failure codes: `frame_order_violation` |

## Board Action

None. This is a PC-side validator defect-fix cycle only.

No Vivado build, PetaLinux build, JTAG programming, TF-card write, UART action,
Ethernet transmission, HDMI capture, or board flash write was performed.

## Evidence

- `tools/validate_passthrough_trace.py`
- `docs/protocols/unified-passthrough-trace.md`
- `docs/current-cycle.md`
- `docs/cycle-log.md`
- `docs/project-roadmap.md`
- `README.md`
- `skills/zynq7020-pipeline/SKILL.md`
- `build/unified-validator-boundary-order-fix/boundary-order-regression-summary.json`
- `build/unified-validator-boundary-order-fix/calibration-only/calibration-summary.json`
- `build/unified-validator-boundary-order-fix/cases/boundary_19_of_20/result.json`
- `build/unified-validator-boundary-order-fix/cases/unmatched_high_then_lower/result.json`
- `build/unified-validator-boundary-order-fix/cases/wrong_order/result.json`

## Result

PASSED.

```text
pass_condition=(calibration_status == pass and boundary_19_of_20_status == pass and boundary_19_of_20_drop_rate == 0.05 and unmatched_high_then_lower_status == fail and unmatched_high_then_lower_has_unmatched_capture == 1 and unmatched_high_then_lower_has_frame_order_violation == 0 and wrong_order_status == fail and wrong_order_has_frame_order_violation == 1)
measured=(calibration_status=pass, boundary_19_of_20_status=pass, boundary_19_of_20_drop_rate=0.05, unmatched_high_then_lower_status=fail, unmatched_high_then_lower_has_unmatched_capture=1, unmatched_high_then_lower_has_frame_order_violation=0, wrong_order_status=fail, wrong_order_has_frame_order_violation=1)
```

## Residual Risks

- This cycle fixes validator edge defects only. It does not solve the larger
  review concern that the future hardware runner must independently decode or
  corroborate captured image evidence instead of self-reporting metadata.
- The next hardware cycle should mandate `require_image_paths=true` or an
  equivalent offline re-decode path from captured HDMI images.
- The active-cycle state for this fix was opened before implementation, but it
  is closed in the same commit as the fix, matching current project practice.
