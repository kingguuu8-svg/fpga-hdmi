# GStreamer RTP Kmssink Route Gate

Date: 2026-07-02

Result: FAILED before verification.

## Objective

Open a route gate for replacing the project-specific network-video receiver and
display scheduling with the mature Linux path:

```text
PC GStreamer RTP raw-video UDP -> board GStreamer rtpjitterbuffer
-> rtpvrawdepay -> videoconvert -> kmssink -> /dev/dri/card0 -> HDMI
```

## Review Finding

The independent audit appended to
`docs/reports/eth-ps-pl-hdmi-pass-through.md` found that the frozen
`pass_condition` was directionally correct but under-specified. It kept
`tearing_frames == 0`, but removed the exact smoothness ruler that previously
failed:

```text
frame_duration_stddev_ms <= 4.0
```

It also removed frame-drop accountability and frame-id correspondence. This
would allow a run to pass with visible frequency instability or large frame
loss, which is the failure mode the governance rules were written to prevent.

## Verification

No verification was run after this cycle opened. The cycle is closed because
the frozen pass gate was invalid for the stated objective, not because the
GStreamer route was tested.

## Board Action

None. No UART command, Ethernet test, HDMI capture, Vivado build, PetaLinux
build, TF-card write, JTAG programming, or board flash write was performed.

## Result

pass_condition=(pc_gst_launch_present == 1 and board_gst_launch_present == 1
and board_required_gst_elements_present == 5 and
board_required_gst_elements_missing == 0 and board_sink == kmssink and
board_display_device == /dev/dri/card0 and transport == rtp-raw-udp and
self_written_udp_receiver_used == 0 and fbdev_live_write_used == 0 and
pc_sender_frames >= 120 and hdmi_captured_frames >= 120 and
captured_motion_frames >= 120 and tearing_frames == 0 and
validator_status == pass).

measured=(not_run; audit_status=fail;
missing_required_gate_fields=frame_duration_stddev_ms<=4.0,drop_rate<=0.05_or_sent_equals_received,frame_id_correspondence).

The result is FAILED because the pass condition removed required rulers before
verification. Per Rule 1, the frozen bar must not be edited in place; the next
cycle must reopen with corrected thresholds before any verification runs.

## Evidence

- `docs/reports/eth-ps-pl-hdmi-pass-through.md`
- commit `3ecad49` (`docs: audit gstreamer route-gate pass_condition for removed rulers`)

## Residual Risks

- The GStreamer path has not been tested yet.
- The current board image may still lack GStreamer or required plugins; that
  must be measured in the corrected route-gate cycle.
