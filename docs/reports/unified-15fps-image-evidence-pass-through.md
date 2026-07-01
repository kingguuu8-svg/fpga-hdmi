# Unified 15fps Image Evidence Pass-Through

Date: 2026-07-01

## Objective

Prove the board-live pass-through loop at 15 fps with the reusable unified
validator and independent saved HDMI image evidence.

The key upgrade over prior color-block checks is that the HDMI-returned JPEGs
now contain a fixed black/white synchronized frame marker. The trace builder
decodes `frame_id` from the saved images themselves before calling the
validator.

## Frozen Pass Gate

```text
pass_condition: sender_fps == 15 and sent_frames == 30 and
  receiver_written_frames == 30 and receiver_dropped_packets == 0 and
  mjpeg_saved_frames >= 60 and mjpeg_unique_hashes >= 8 and
  mjpeg_unique_colors >= 8 and trace_require_image_paths == 1 and
  trace_image_path_failures == 0 and validator_status == pass and
  trace_sent_frames == 30 and trace_matched_frames >= 29 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0.
validator: already-committed tools/validate_passthrough_trace.py direct trace
  validation command on a trace JSON emitted by this cycle's hardware runner.
```

## Changed Scope

- `tools/send_unified_test_video_udp.py`
  - Adds a small black/white synchronized frame marker to every generated
    RGB888 frame.
  - Uses color-qualified content IDs, for example `frame-000100-yellow`.
  - Keeps camera/webcam and custom-file input out of the path.
- `tools/build_unified_trace_from_mjpeg.py`
  - Decodes `frame_id` and color directly from saved HDMI JPEG evidence.
  - Requires the marker sync cells before accepting a decoded frame ID.
  - Emits image paths and SHA-256 hashes into the unified trace.
- `tools/run_unified_15fps_trace_probe.ps1`
  - Builds/deploys the Linux receiver, starts the dashboard MJPEG return
    endpoint, saves HDMI-returned frames, sends 30 validation frames, builds
    the trace, and calls the committed validator.
- `software/eth_pass_through/linux_app/src/fb_video_udp_receiver.c`
  - Adds `--present-fps` to pace framebuffer presentation. This prevents the
    receiver from catching up in 40 ms bursts after socket-buffer backlog,
    which previously made the HDMI/UVC return path miss frame IDs.
- `tools/probe_mjpeg_stream.py`
  - Records `captured_ms` for saved JPEG evidence and writes live probe status.

## Verification

Compile checks:

```text
rtk powershell.exe -NoProfile -Command "python -m py_compile .\tools\probe_mjpeg_stream.py .\tools\send_unified_test_video_udp.py .\tools\build_unified_trace_from_mjpeg.py .\tools\validate_passthrough_trace.py"
rtk powershell.exe -NoProfile -Command "`$null = [scriptblock]::Create((Get-Content -Raw .\tools\run_unified_15fps_trace_probe.ps1)); Write-Host POWERSHELL_PARSE_OK"
```

Sender self-test:

```text
UNIFIED_TEST_VIDEO_SENDER_SELF_TEST_OK
```

Receiver build and host tests:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
VIDEO_CONTROL_TEST_OK
VIDEO_EFFECT_TEST_OK
LINUX_RECEIVER_BUILD_OK
```

Hardware run:

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_unified_15fps_trace_probe.ps1 -OutDir build\unified-15fps-image-evidence-pass-through -CaptureDevice 1 -CaptureBackend dshow -StreamFps 30 -MjpegFrames 220 -MjpegMinUnique 8 -MjpegMinColors 8 -Frames 30 -WarmupFrames 12 -ValidationStartFrameId 100 -Fps 15 -TraceMaxLatencyMs 1000 -UdpPayload 1200 -HoldRepeats 1 -InterPacketUs 0 -PacketWindowFraction 0.85 -ReceiverSyncMode none -ReceiverPresentFps 15
```

Final marker:

```text
UNIFIED_15FPS_IMAGE_EVIDENCE_OK sender_fps=15 sent_frames=30 sender_hold_repeats=1 receiver_written_frames=30 receiver_dropped_packets=0 mjpeg_saved_frames=220 mjpeg_unique_hashes=47 mjpeg_unique_colors=8 trace_require_image_paths=1 trace_image_path_failures=0 validator_status=pass trace_sent_frames=30 trace_matched_frames=30 trace_drop_rate=0.0 trace_order_violations=0 trace_content_mismatches=0 trace_black_frames=0 trace_required_max_latency_ms=1000.0 trace_max_latency_ms=257.561 sent_time_offset_ms=3063
```

Measured values:

```text
sender_fps=15
sent_frames=30
sender_hold_repeats=1
receiver_written_frames=30
receiver_dropped_packets=0
mjpeg_saved_frames=220
mjpeg_unique_hashes=47
mjpeg_unique_colors=8
trace_require_image_paths=1
trace_image_path_failures=0
validator_status=pass
trace_sent_frames=30
trace_matched_frames=30
trace_drop_rate=0.0
trace_order_violations=0
trace_content_mismatches=0
trace_black_frames=0
trace_required_max_latency_ms=1000.0
trace_mean_latency_ms=118.411
trace_max_latency_ms=257.561
```

Validator result:

```text
UNIFIED_PASSTHROUGH_TRACE_OK
sent_frames=30
captured_frames=30
matched_frames=30
match_rate=1.0
drop_rate=0.0
latency_violations=0
order_violations=0
content_mismatches=0
black_frames=0
image_path_failures=0
```

## Board Action

Ran the Linux userspace receiver from `/tmp`, sent generated UDP RGB888 frames
from the PC over Ethernet, captured HDMI through the PC UVC adapter, and used
UART only for Linux shell control.

No Vivado build, PetaLinux build, JTAG programming, TF-card write, QSPI, NAND,
eMMC, or other board flash write was performed.

## Evidence

- `build/unified-15fps-image-evidence-pass-through/unified-15fps.marker.txt`
- `build/unified-15fps-image-evidence-pass-through/unified-15fps-summary.json`
- `build/unified-15fps-image-evidence-pass-through/sender/sender-trace.json`
- `build/unified-15fps-image-evidence-pass-through/mjpeg-return/mjpeg-stream-probe.json`
- `build/unified-15fps-image-evidence-pass-through/mjpeg-return/mjpeg-frame-*.jpg`
- `build/unified-15fps-image-evidence-pass-through/trace/trace.json`
- `build/unified-15fps-image-evidence-pass-through/trace/validation-result.json`
- `build/unified-15fps-image-evidence-pass-through/trace/mjpeg-classification.json`
- `build/unified-15fps-image-evidence-pass-through/uart_deploy_start_receiver.log`
- `build/unified-15fps-image-evidence-pass-through/uart_after_unified_15fps.log`

## Result

PASSED.

```text
pass_condition=(sender_fps == 15 and sent_frames == 30 and receiver_written_frames == 30 and receiver_dropped_packets == 0 and mjpeg_saved_frames >= 60 and mjpeg_unique_hashes >= 8 and mjpeg_unique_colors >= 8 and trace_require_image_paths == 1 and trace_image_path_failures == 0 and validator_status == pass and trace_sent_frames == 30 and trace_matched_frames >= 29 and trace_drop_rate <= 0.05 and trace_order_violations == 0 and trace_content_mismatches == 0 and trace_black_frames == 0)
measured=(sender_fps=15, sent_frames=30, receiver_written_frames=30, receiver_dropped_packets=0, mjpeg_saved_frames=220, mjpeg_unique_hashes=47, mjpeg_unique_colors=8, trace_require_image_paths=1, trace_image_path_failures=0, validator_status=pass, trace_sent_frames=30, trace_matched_frames=30, trace_drop_rate=0.0, trace_order_violations=0, trace_content_mismatches=0, trace_black_frames=0)
```

## Residual Risks

- The `trace_required_max_latency_ms=1000.0` threshold is for the HDMI capture
  adapter plus Dashboard MJPEG return path. It is not a board-internal
  processing latency claim. The measured max for the passing run was
  `257.561 ms`.
- The video source is deterministic generated RGB888 with an image-decodable
  marker. This proves faithful pass-through at the frame level, not a real
  external video file or final effects pipeline.
- `--present-fps 15` is a userspace presentation pacing mechanism. It is valid
  for the current Linux framebuffer MVP, but a later low-latency design should
  move pacing into a clearer video scheduler or PL-facing buffer discipline.
- The trace builder `tools/build_unified_trace_from_mjpeg.py` is new this cycle
  and is the only decoder of the saved JPEG markers. The validator checks that
  image files exist and match their recorded SHA-256, but it does not
  re-decode `decoded_frame_id` from the JPEG and compare it to the trace's
  value. The saved JPEGs are independently real, but the decode step is
  single-source. An offline re-decode tool committed in a prior cycle would
  close this gap; a 2026-07-01 independent audit spot-checked one JPEG by hand
  (see Third-party review) and the marker matched, but a one-frame spot check
  is not a full second-decoder proof.

## Third-party review

Reviewer: independent audit in a separate session (2026-07-01). This section is
non-blocking: it does not reopen the cycle or gate the next one.

Verdict: the cycle's PASSED holds up. The committed validator was re-run on the
cycle's own saved trace and reproduced PASS with 30/30 matched frames. One
saved HDMI JPEG was independently marker-decoded (without importing the trace
builder) and its `frame_id` matched the trace's claimed value, giving partial
corroboration that the trace builder did not copy metadata from the sent side.

Independent checks performed:

- Re-ran `python .\tools\validate_passthrough_trace.py <trace.json>` on the
  cycle's saved `build/unified-15fps-image-evidence-pass-through/trace/trace.json`
  into a fresh result file. Marker: `UNIFIED_PASSTHROUGH_TRACE_OK`. Metrics
  reproduced: `matched=30, drop_rate=0.0, order_violations=0,
  content_mismatches=0, black_frames=0, image_path_failures=0,
  max_latency_ms=257.561`. Every value satisfies the frozen pass_condition.
- Confirmed the trace `requirements` block carries `require_image_paths: True`
  and every captured entry has an `image_path` plus `image_sha256`, so the
  validator's image-evidence path was active (not the disabled-by-default
  mode flagged in the calibration review, concern 2).
- Confirmed `git show e102d98 --stat` does not touch
  `tools/validate_passthrough_trace.py`, so the pass-gate validator was not
  modified in the same commit — Rule 2 is satisfied.
- Independent JPEG marker decode: wrote a standalone decoder (geometry
  constants transcribed from the sender, no import of the trace builder) that
  opened `mjpeg-frame-32.jpg` with OpenCV, read the sync + 12 data cells at
  (32, 32) with 32 px cells and 6 px inner padding, and decoded
  `marker_bits=001001100000` -> `frame_id=100`. Results:
  `sha_match=True` (file SHA-256 equals the trace's `image_sha256`),
  `indep_sync_ok=True`, `bits_match=True`, `id_match=True` (independently
  decoded 100 == trace's `decoded_frame_id` 100). The image is 800x600. This
  confirms the marker is physically present in the captured HDMI JPEG and the
  trace builder's `decoded_frame_id` for this frame was not copied from the
  sent side.
- Noted the build directory contains multiple failed probe logs
  (`uart_probe_receiver_*_fail.log` x8, `debug-slow-one/`,
  `trace-offset3000/`, `validation-result-rerun.json`) and a
  `sent_time_offset_ms=3063` alignment parameter, indicating the 15 fps run
  was iterated to convergence before the single close commit.

Residual concerns not covered by the cycle's own closure criteria:

1. Single-commit process: the cycle opened and closed in `e102d98` with no
   prior Active Cycle commit, so the frozen `pass_condition` (with tunable
   thresholds `drop_rate <= 0.05`, `max_latency_ms <= 1000`) has no git trail
   proving it was set before the result. The iteration evidence in the build
   dir makes this the highest-risk instance of the pattern. The
   `verification-standard-governance-fix` cycle added a Rule 1 open-commit
   sub-rule so future cycles must commit the Active Cycle block first; this
   cycle is historical under the forward-only clause.
2. The independent JPEG decode was a one-frame spot check (`frame_id=100`), not
   a full re-decode of all 30 captured frames. It corroborates but does not
   fully close the calibration review's concern 2 (single-source decoder). A
   committed offline re-decode tool run over all saved JPEGs would be the
   durable fix.
3. The `build_unified_trace_from_mjpeg.py` trace builder is new this cycle and
   feeds the validator. It is not the pass-gate validator (Rule 2 applies to
   the validator, which is prior-cycle and unmodified), but a fabricated trace
   builder could still write a `decoded_frame_id` inconsistent with the JPEG
   content and the validator would not catch it. The SHA-256 + image-path
   checks plus the one-frame spot check reduce but do not eliminate this.

None of the above reopens this cycle or blocks the next one. Concern 1 is
addressed structurally for future cycles by the governance fix; concerns 2 and
3 point to a future cycle that commits an offline re-decode tool and runs it
over all saved JPEGs before a pass-through claim.
