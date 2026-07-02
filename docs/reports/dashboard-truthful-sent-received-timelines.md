# Dashboard Truthful Sent/Received Timelines

Date: 2026-07-02

Result: FAILED, frozen at user request.

## Objective

Show two truthful independent dashboard timelines:

- Left panel: latest frame actually completed by the PC sender.
- Right panel: actual HDMI-returned frame captured through the UVC adapter.
- Natural delay is allowed and exposed; the left frame must not be selected
  from the HDMI-decoded frame ID.

## Frozen Gate

The cycle-open commit preregistered this pass condition:

```text
preview_source == latest-actual-sent-frame and configured_sender_fps == 10
and 9.5 <= sender_measured_fps <= 10.5 and receiver_present_fps == 10
and hdmi_delivery_fps == 10 and content_dwell_seconds == 5
and timeline_samples >= 20 and negative_lag_samples == 0
and positive_lag_samples >= 1 and distinct_sent_ids >= 3
and distinct_hdmi_ids >= 3 and max_lag_frames <= 30
and sent_frames == 90 and receiver_written_frames == 90
and receiver_dropped_packets == 0 and validator_status == pass
and trace_matched_frames >= 86 and trace_drop_rate <= 0.05
and trace_order_violations == 0 and trace_content_mismatches == 0
and trace_black_frames == 0 and trace_image_path_failures == 0
and trace_max_latency_ms <= 1000.
```

Validator:

```text
already-committed tools/validate_passthrough_trace.py on the decoded
Dashboard-started hardware trace, plus direct PowerShell checks against
/api/input-preview.bmp headers.
```

## Verification Run

Command:

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_unified_15fps_trace_probe.ps1
```

Output directory:

```text
build/dashboard-truthful-sent-received-timelines/
```

Final marker:

```text
DASHBOARD_TRUTHFUL_SENT_RECEIVED_TIMELINES_FAIL dashboard_sender_kind=unified preview_source=latest-actual-sent-frame configured_sender_fps=10 sender_measured_fps=8.047 receiver_present_fps=10 hdmi_delivery_fps=10 content_dwell_seconds=5 timeline_samples=20 negative_lag_samples=0 positive_lag_samples=3 distinct_sent_ids=4 distinct_hdmi_ids=4 max_lag_frames=2 sent_frames=90 receiver_written_frames=90 receiver_dropped_packets=0 mjpeg_saved_frames=150 mjpeg_unique_hashes=102 mjpeg_unique_colors=2 trace_require_image_paths=1 trace_image_path_failures=0 validator_status=pass trace_sent_frames=90 trace_matched_frames=90 trace_drop_rate=0.0 trace_order_violations=0 trace_content_mismatches=0 trace_black_frames=0 trace_required_max_latency_ms=1000.0 trace_max_latency_ms=135.028 sent_time_offset_ms=4250 out=E:\main\fpga-hdml\build\dashboard-truthful-sent-received-timelines
```

## Measured Values

```text
preview_source=latest-actual-sent-frame
configured_sender_fps=10
sender_measured_fps=8.047
receiver_present_fps=10
hdmi_delivery_fps=10
content_dwell_seconds=5
timeline_samples=20
negative_lag_samples=0
positive_lag_samples=3
distinct_sent_ids=4
distinct_hdmi_ids=4
max_lag_frames=2
sent_frames=90
receiver_written_frames=90
receiver_dropped_packets=0
validator_status=pass
trace_matched_frames=90
trace_drop_rate=0.0
trace_order_violations=0
trace_content_mismatches=0
trace_black_frames=0
trace_image_path_failures=0
trace_max_latency_ms=135.028
```

## Interpretation

This run proved an important subchain but did not pass the cycle:

- The Dashboard left preview source was truthful: `latest-actual-sent-frame`.
- The HDMI-return trace matched 90/90 frames with drop rate 0.0.
- The board receiver wrote 90/90 frames with packet drops 0.
- The sampled timeline exposed natural lag: three positive-lag samples,
  zero negative-lag samples, max lag two frames.
- The preregistered sender-rate gate failed: measured sender FPS was 8.047,
  below the frozen lower bound 9.5.

Because the pass condition was frozen before verification, this cycle cannot
be rescued by lowering the FPS threshold or redefining the measured rate. It is
closed as FAILED and frozen at the user's stop-work request.

## Board Action

Ran the Linux receiver from `/tmp`, sent PC UDP RGB888 frames over Ethernet,
captured HDMI through the PC UVC adapter, and used UART shell control. No
Vivado build, PetaLinux build, JTAG programming, TF-card write, QSPI, NAND,
eMMC, or other persistent board write was performed.

## Source Snapshot

The frozen working snapshot changes:

- Dashboard default sender/stream FPS from 15 to 10.
- Dashboard input preview semantics from paired HDMI ID to latest actual sent
  frame.
- Runner timeline checks from paired-equality checks to non-negative lag
  checks.

This failed path is not promoted into `skills/zynq7020-pipeline/SKILL.md`
because project rules only allow verified feasible paths to become workflow
entry points.

## Residual Risks

- The immediate bottleneck is PC sender pacing, not board packet loss: the
  sender sent all frames and the board wrote all frames, but the measured send
  cadence was too slow for the frozen 10 fps gate.
- The timeline sample set collapsed to repeated frame 189 after the finite
  sender finished, so later dashboard presentation should keep the stream live
  or sample within the active send window if the goal is a human-facing live
  display.
- The current dashboard still needs a user-visible presentation pass; this
  cycle only freezes the engineering evidence and failed code snapshot.
