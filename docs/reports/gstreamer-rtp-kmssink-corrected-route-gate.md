# GStreamer RTP Kmssink Corrected Route Gate

Date: 2026-07-02

Result: FAILED.

## Objective

Verify the shortest mature Linux route for smooth network-driven video without
using the project-specific UDP receiver/display scheduler:

```text
PC GStreamer RTP raw-video UDP -> board GStreamer rtpjitterbuffer
-> rtpvrawdepay -> videoconvert -> kmssink -> /dev/dri/card0 -> HDMI
```

This cycle corrected the prior flawed pass gate by restoring smoothness,
drop-rate, and frame-id correspondence requirements before any verification
ran.

## Frozen Gate

```text
pc_gst_launch_present == 1 and board_gst_launch_present == 1
and pc_required_gst_elements_missing == 0 and
board_required_gst_elements_missing == 0 and board_sink == kmssink and
board_display_device == /dev/dri/card0 and transport == rtp-raw-udp and
jitter_buffer == rtpjitterbuffer and self_written_udp_receiver_used == 0
and fbdev_live_write_used == 0 and trace_sent_frames >= 120 and
trace_captured_frames >= 114 and trace_matched_frames >= 114 and
trace_drop_rate <= 0.05 and trace_order_violations == 0 and
trace_content_mismatches == 0 and trace_black_frames == 0 and
trace_image_path_failures == 0 and hdmi_captured_frames >= 120 and
frame_duration_stddev_ms <= 4.0 and tearing_frames == 0 and
unified_validator_status == pass and tearing_validator_status == pass.
```

## Verification

PC GStreamer probe:

```text
PC_CMD_MISSING gst-launch-1.0
PC_CMD_MISSING gst-inspect-1.0
```

Board GStreamer probe:

```text
BOARD_CMD_MISSING gst-launch-1.0
BOARD_CMD_MISSING gst-inspect-1.0
/dev/dri/card0 exists
BOARD_GST_ELEMENT_MISSING udpsrc
BOARD_GST_ELEMENT_MISSING rtpjitterbuffer
BOARD_GST_ELEMENT_MISSING rtpvrawdepay
BOARD_GST_ELEMENT_MISSING videoconvert
BOARD_GST_ELEMENT_MISSING kmssink
```

The cycle failed at the cheapest route gate. No RTP sender, board receive
pipeline, HDMI motion capture, trace validation, or tearing validation was run.

## Measured

```text
pc_gst_launch_present=0
board_gst_launch_present=0
pc_required_gst_elements_missing=5
board_required_gst_elements_missing=5
board_sink=missing
board_display_device=/dev/dri/card0
transport=not-run
jitter_buffer=missing
self_written_udp_receiver_used=0
fbdev_live_write_used=0
trace_sent_frames=0
trace_captured_frames=0
trace_matched_frames=0
trace_drop_rate=1.0
trace_order_violations=not-run
trace_content_mismatches=not-run
trace_black_frames=not-run
trace_image_path_failures=not-run
hdmi_captured_frames=0
frame_duration_stddev_ms=not-run
tearing_frames=not-run
unified_validator_status=not-run
tearing_validator_status=not-run
```

## Board Action

Runtime-only UART shell inspection was performed. No Ethernet video send, HDMI
capture, Vivado build, PetaLinux build, TF-card write, JTAG programming, or
board flash write was performed.

## Evidence

- `build/gstreamer-rtp-kmssink-corrected-route-gate/pc-gstreamer-probe.log`
- `build/gstreamer-rtp-kmssink-corrected-route-gate/board-gstreamer-probe-exact.log`

## Interpretation

The GStreamer route is still the right shortest Linux-ecosystem direction, but
the current PC environment and current board image cannot run it. The next
cycle must install or provide GStreamer on the PC and add GStreamer packages
to the PetaLinux/rootfs image before re-running the same route gate.

## Residual Risks

- Required GStreamer package names for PetaLinux 2018.3 still need to be
  mapped to the available Yocto recipes.
- After GStreamer is available, the RTP/raw caps and `kmssink` properties may
  still require tuning.
