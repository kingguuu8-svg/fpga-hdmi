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
- Correction (2026-07-01 audit): an earlier version of this report said the
  active-cycle state "was opened before implementation." Git history shows no
  separate open commit — the cycle opened and closed in `e21482c` with no prior
  `## Active Cycle` block committed. The claim was inaccurate. The
  `verification-standard-governance-fix` cycle added a Rule 1 open-commit
  sub-rule so future cycles with a tunable `pass_condition` must commit the
  Active Cycle block before verification runs; this cycle is historical and
  keeps its single-commit form under that rule's forward-only clause.

## Third-party review

Reviewer: independent audit in a separate session (2026-07-01). This section is
non-blocking: it does not reopen the cycle or gate the next one.

Verdict: the cycle's PASSED holds up. Both code fixes were confirmed against
the committed source, and both the calibration and the boundary-order
regression were reproduced independently into clean output directories.

Independent checks performed:

- Re-ran `python .\tools\validate_passthrough_trace.py --calibration` into
  `build/review-evidence/calibration-rerun`. Marker reproduced:
  `UNIFIED_PASSTHROUGH_VALIDATOR_CALIBRATION_OK` with all six booleans = 1.
  The pre-fix calibration still passes after the fix, confirming no regression
  in the existing known-good/known-bad behavior.
- Re-ran `python .\tools\validate_passthrough_trace.py --boundary-order-regression`
  into `build/review-evidence/boundary-order-rerun`. Marker reproduced
  verbatim:
  `UNIFIED_VALIDATOR_BOUNDARY_ORDER_FIX_OK calibration_status=pass
  boundary_19_of_20_status=pass boundary_19_of_20_drop_rate=0.05
  unmatched_high_then_lower_status=fail
  unmatched_high_then_lower_has_unmatched_capture=1
  unmatched_high_then_lower_has_frame_order_violation=0
  wrong_order_status=fail wrong_order_has_frame_order_violation=1`.
  Every measured value matches the report's frozen pass_condition.
- Confirmed the two source fixes against `git show e21482c -- tools/validate_passthrough_trace.py`:
  `drop_rate` now computes `(sent_count - matched_count) / sent_count` from
  integers (was `1.0 - match_rate`), eliminating the floating-point boundary
  contradiction; and the order check moved after the unmatched-capture and
  duplicate checks, so an unmatched high `decoded_frame_id` no longer mutates
  `previous_frame_id`.
- Confirmed the `boundary_19_of_20` case sits at exactly 19/20 matched with
  `drop_rate=0.05` and no failures — the decisive [0.95, 1.0) boundary region
  flagged by the calibration review (concern 1) is now exercised and passes.

Residual concerns not covered by the cycle's own closure criteria:

1. Rule 2 gray area: this cycle modified the validator and added the
   `--boundary-order-regression` mode, then used that new mode as its pass
   gate. The validator script itself predates the cycle (committed in
   `5e8e21b`), satisfying the letter of Rule 2, but the specific pass-condition
   assertions are newly written. This is acceptable because the defects were
   raised by an external review (not invented to fit a result) and the
   pass_condition demands that known-bad cases FAIL (`wrong_order_status==fail`),
   so the cheating direction opposes the bar. Still, the regression cases and
   their "expected" columns are author-defined; independence is weaker than the
   calibration cycle's external review.
2. Single-commit process: the cycle opened and closed in `e21482c` with no
   prior Active Cycle commit (the report's former "opened before
   implementation" claim was inaccurate and has been corrected above). The
   `verification-standard-governance-fix` cycle added a Rule 1 open-commit
   sub-rule making this non-conformant for future cycles with a tunable
   threshold; this cycle is historical under the forward-only clause.

None of the above reopens this cycle or blocks the next one.
