# Dashboard Unified 15 fps Paired Preview

Date: 2026-07-02

## Objective

Replace the Dashboard legacy sender with the unified sender and pair the left
preview to the frame ID decoded from the HDMI return.

## Result

FAILED.

The transport portion eventually passed, but the preview semantic was wrong.
The left panel followed the HDMI-decoded frame ID, which made the panels appear
matched by construction and hid the natural end-to-end delay. The user rejected
that behavior before cycle close. The correct model is two truthful timelines:
left is the latest frame actually sent; right is the actual HDMI-returned frame.

The run also exposed that `sender_fps=15` was only a configured value. The final
sender trace measured 12.011 fps because sending 1200 Python UDP datagrams for
one 800x600 RGB888 frame took about 83 ms.

## Frozen Gate And Measured Values

```text
pass_condition: dashboard_sender_kind == unified and sender_fps == 15 and
  receiver_present_fps == 15 and hdmi_sample_fps == 15 and
  content_dwell_seconds == 5 and paired_preview_samples >= 20 and
  paired_preview_id_mismatches == 0 and sent_frames == 90 and
  receiver_written_frames == 90 and receiver_dropped_packets == 0 and
  validator_status == pass and trace_matched_frames >= 86 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0 and
  trace_image_path_failures == 0 and trace_max_latency_ms <= 1000.

measured: dashboard_sender_kind=unified, configured_sender_fps=15,
  sender_measured_fps=12.011, receiver_present_fps=15, hdmi_sample_fps=15,
  content_dwell_seconds=5, paired_preview_samples=20,
  paired_preview_id_mismatches=0, sent_frames=90,
  receiver_written_frames=90, receiver_dropped_packets=0,
  validator_status=pass, trace_matched_frames=90, trace_drop_rate=0.0,
  trace_order_violations=0, trace_content_mismatches=0,
  trace_black_frames=0, trace_image_path_failures=0,
  trace_max_latency_ms=141.088, user_acceptance=failed.
```

Although the frozen numeric checks were reached, cycle closure is FAILED because
the objective's preview behavior was explicitly rejected and the configured FPS
was not the measured FPS.

## Iteration Evidence

- Initial same-thread capture: 79/90 matched. `cap.read`, JPEG, HTTP, and preview
  work shared one loop.
- Deadline scheduling without double sleep: 78/90 matched.
- Faster BMP generation: 85/90 matched.
- Twelve warmup frames: 83/90 matched.
- Dedicated continuous UVC producer plus 15 fps output queue: 90/90 matched,
  dropped=0, but retained the rejected paired-preview semantic.

## Useful Findings

- Dashboard now starts the unified sender rather than the legacy demo sender.
- Sender live state is written only after a frame has actually been sent.
- A dedicated UVC producer prevents JPEG/HTTP work from dropping unique HDMI
  frame IDs.
- The next cycle must not use the returned frame ID to choose the left image.
- The next cycle must report measured FPS, not only configured FPS.

## Board Action

The Linux receiver ran from `/tmp`; PC sent UDP RGB888; HDMI was captured through
the UVC adapter; UART controlled the Linux shell. No Vivado, PetaLinux, JTAG,
TF-card, or flash write occurred.

## Evidence

- `build/dashboard-unified-15fps-paired-preview/sender/sender-trace.json`
- `build/dashboard-unified-15fps-paired-preview/paired-preview-evidence.json`
- `build/dashboard-unified-15fps-paired-preview/mjpeg-return/`
- `build/dashboard-unified-15fps-paired-preview/trace/validation-result.json`
- `build/dashboard-unified-15fps-paired-preview/uart_after_unified_15fps.log`
