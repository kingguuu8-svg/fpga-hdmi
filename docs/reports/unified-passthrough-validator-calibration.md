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

## Third-party review

Reviewer: independent audit in a separate session (2026-07-01). This section is
non-blocking: it does not reopen the cycle or gate the next one. Its purpose is
to leave a durable record of what was independently checked alongside the
cycle's own PASSED claim.

Verdict: the cycle's PASSED holds up. The six calibration booleans were
reproduced independently and every metric in the report's calibration table was
confirmed against a fresh `calibration-summary.json`.

Independent checks performed:

- Re-ran `python .\tools\validate_passthrough_trace.py --calibration` into a
  clean out-dir. Marker reproduced:
  `UNIFIED_PASSTHROUGH_VALIDATOR_CALIBRATION_OK` with all six booleans = 1.
  Metrics matched the report verbatim (known_good 30/30 match_rate=1.0;
  known_bad_missing 27/30=0.9; known_bad_black 30 black frames;
  known_bad_wrong_order 1 order violation; known_bad_latency 30 latency
  violations, max 420 ms).
- Probed the validator with hand-crafted, non-script-generated traces to test
  whether it overfits its own fixture generator:
  - A 5-frame good trace with a low-luma edge frame (mean_luma 9.5) -> PASS.
  - A trace with an unmatched capture (decoded_frame_id=99) plus a black frame
    -> FAIL, correctly emitting `unmatched_capture`, `black_frame`,
    `match_rate_below_min`, and `drop_rate_above_max`.
  - A "cheating runner" trace that copies `content_id`/`frame_id` from the sent
    side into captured without decoding -> PASS (see residual concern 2).
  - A 20-sent / 19-matched trace at exactly the 95% boundary -> FAIL on
    `drop_rate_above_max` only (see residual concern 1).
- Audited governance-rule form: `pass_condition` and `validator` are present
  and precise; Rule 2's introduce-and-calibrate exception is satisfied
  (1 known-good + 5 known-bad, results recorded, no hardware PASSED claimed on
  the new validator this cycle); `docs/cycle-log.md` `Result:` carries both
  `pass_condition=` and `measured=`.
- Audited fact consistency: thresholds live only in
  `docs/protocols/unified-passthrough-trace.md` and the script; README and
  roadmap reference by path without restating values; the protocol is
  registered in `AGENTS.md`.
- Confirmed original cycle build artifacts exist locally with timestamps
  predating the commit, so the cycle was run, not merely asserted.

Residual concerns not covered by the cycle's own closure criteria:

1. `match_rate` and `drop_rate` disagree at the 95% boundary due to floating
   point. `drop_rate` is computed as `1.0 - match_rate`
   (`tools/validate_passthrough_trace.py:179`), so at 19/20 matched:
   `match_rate=0.95` passes `< min` but `drop_rate=0.050000000000000044` fails
   `> max`, contradicting the inclusive `drop_rate <= max_drop_rate` semantics
   in `docs/protocols/unified-passthrough-trace.md:71`. This is conservative
   (boundary judged FAIL, not PASS) so it cannot produce a false PASSED, but the
   decisive [0.95, 1.0) region is never exercised by the calibration cases,
   which sit at 1.0 and 0.9. Suggested fix: compute `drop_rate` from integer
   counts `(sent - matched) / sent` and add a 95%-boundary calibration case.

2. The validator consumes a runner-decoded trace; `decoded_frame_id`,
   `content_id`, and `captured_ms` are all supplied by the runner. A trace that
   copies the sent side's metadata into captured without any real HDMI decode
   passes validation. The only independent corroboration path
   (`require_image_paths=True` plus `image_sha256`) is disabled by default
   (`DEFAULT_REQUIREMENTS.require_image_paths=False`, protocol marks
   `image_path` optional). This is the same self-judging pattern the governance
   rules were written to remove, displaced from the validator onto the runner.
   Before the next hardware cycle relies on this validator as its frozen pass
   gate, it should mandate `require_image_paths=True` with committed captured
   images, or add an offline re-decode of `decoded_frame_id` from the captured
   images and compare it against the runner's reported value.

3. The cycle was opened and closed in a single commit (`5e8e21b`); no separate
   commit ever recorded an Active Cycle state in `docs/current-cycle.md`, so
   Rule 1's "frozen at the moment the cycle becomes active" leaves no auditable
   trace. Low risk here because the pass_condition is structural (six booleans
   fixed by the script), but for a future cycle with a tunable threshold this
   pattern would let the bar be set after the result is known. Suggested
   process fix: commit the Active Cycle state before running verification.

4. In `validate_trace`, an unmatched high `decoded_frame_id` updates
   `previous_frame_id` before the unmatched check continues
   (`tools/validate_passthrough_trace.py:133-141`), so a later legitimate lower
   frame_id can register a spurious `frame_order_violation`. Rare in practice;
   suggest moving the unmatched check ahead of the order check.

None of the above reopens this cycle or blocks the next one. Concerns 1 and 4
are validator defects suited to a narrow fix cycle; concern 2 is a usage rule
for the next hardware cycle; concern 3 is a process note.

Follow-up: concerns 1 and 4 are addressed by
`docs/reports/unified-validator-boundary-order-fix.md`. Concern 2 remains a
mandatory evidence requirement for the next hardware cycle, and concern 3
remains a process risk to avoid in future cycle openings.
