# Linux Net To HDMI Direct Copy

Date: 2026-07-02

Result: PASSED.

## Objective

Complete the Linux-side network-to-HDMI transfer path by removing the long
per-pixel framebuffer byte-reorder window identified in the third-party review.
The PC now sends framebuffer-native 24bpp payload bytes, and the Linux receiver
writes each complete UDP frame to `/dev/fb0` using direct row memcpy before the
VDMA HDMI path scans it out.

This cycle is pure userspace:

- No Vivado build.
- No PetaLinux build.
- No device-tree change.
- No bitstream change.
- No TF-card or persistent board write.

## Review Input

The reviewed concern in `docs/reports/eth-ps-pl-hdmi-pass-through.md` was
concrete: the receiver wrote the live framebuffer in place with a per-pixel
RGB-to-framebuffer reorder loop, while the HDMI VDMA continuously scanned the
same memory. The recommended Tier 1 fix was to move byte-order conversion to
the PC side and make the board-side copy a direct memcpy.

## Changes

- `tools/send_unified_test_video_udp.py`
  - Added `--wire-format fb24-native`.
  - Keeps the existing `rgb888` default for compatibility.
  - Records `wire_format` in `sender-trace.json`.

- `software/eth_pass_through/linux_app/src/fb_video_udp_receiver.c`
  - Added `--fb-copy-mode rgb888-reorder|direct-memcpy`.
  - Keeps the existing `rgb888-reorder` default.
  - Direct mode requires the verified board framebuffer layout:
    red byte 2, green byte 1, blue byte 0.
  - Emits `FB_COPY_MODE mode=direct-memcpy` for board-log evidence.

- `tools/run_linux_net_to_hdmi_direct_copy_probe.ps1`
  - Builds and deploys the receiver to `/tmp`.
  - Starts the receiver with `--fb-copy-mode direct-memcpy`.
  - Sends marker-backed `fb24-native` UDP frames.
  - Captures HDMI through the existing UVC/MJPEG path.
  - Builds a saved-image trace and runs the committed unified validator.

## Frozen Gate

```text
receiver_fb_copy_mode == direct-memcpy and
sender_wire_format == fb24-native and sender_fps == 15 and sent_frames == 30
and receiver_written_frames == 30 and receiver_dropped_packets == 0 and
receiver_effect == none and trace_require_image_paths == 1 and
trace_image_path_failures == 0 and validator_status == pass and
trace_sent_frames == 30 and trace_matched_frames >= 29 and
trace_drop_rate <= 0.05 and trace_order_violations == 0 and
trace_content_mismatches == 0 and trace_black_frames == 0 and
trace_max_latency_ms <= 1000.
```

Validator:

```text
already-committed tools/validate_passthrough_trace.py on saved HDMI
image-backed trace, plus existing receiver build/host tests and direct log
checks for FB_COPY_MODE, receiver writes, dropped=0, and sender wire_format.
```

## Verification

Static and host checks:

```text
python -m py_compile tools/send_unified_test_video_udp.py
python -m py_compile tools/build_unified_trace_from_mjpeg.py
python -m py_compile tools/validate_passthrough_trace.py
UNIFIED_TEST_VIDEO_SENDER_SELF_TEST_OK
POWERSHELL_PARSE_OK for tools/run_linux_net_to_hdmi_direct_copy_probe.ps1
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
VIDEO_CONTROL_TEST_OK
VIDEO_EFFECT_TEST_OK
LINUX_RECEIVER_BUILD_OK
```

Connected-board command:

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_linux_net_to_hdmi_direct_copy_probe.ps1
```

Final marker:

```text
LINUX_NET_TO_HDMI_DIRECT_COPY_OK receiver_fb_copy_mode=direct-memcpy sender_wire_format=fb24-native sender_fps=15 sent_frames=30 receiver_written_frames=30 receiver_dropped_packets=0 receiver_effect=none mjpeg_saved_frames=520 mjpeg_unique_hashes=42 mjpeg_unique_colors=8 trace_require_image_paths=1 trace_image_path_failures=0 validator_status=pass trace_sent_frames=30 trace_matched_frames=30 trace_drop_rate=0.0 trace_order_violations=0 trace_content_mismatches=0 trace_black_frames=0 trace_required_max_latency_ms=1000.0 trace_max_latency_ms=62.382 sent_time_offset_ms=3078 out=E:\main\fpga-hdml\build\linux-net-to-hdmi-direct-copy
```

Measured:

```text
receiver_fb_copy_mode=direct-memcpy
sender_wire_format=fb24-native
sender_fps=15
sent_frames=30
receiver_written_frames=30
receiver_dropped_packets=0
receiver_effect=none
mjpeg_saved_frames=520
mjpeg_unique_hashes=42
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
trace_mean_latency_ms=27.038
trace_max_latency_ms=62.382
```

## Board Evidence

Receiver startup:

```text
FB_INFO path=/dev/fb0 xres=800 yres=600 xres_virtual=800 yres_virtual=1200 bpp=24 line_length=2400 smem_len=2880000 red_offset=16 green_offset=8 blue_offset=0
FB_CHANNEL_BYTES red=2 green=1 blue=0
FB_COPY_MODE mode=direct-memcpy red_byte=2 green_byte=1 blue_byte=0
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=42 timeout_sec=180 control=/tmp/video_ctl effect=none sync_mode=none fb_copy_mode=direct-memcpy present_interval_ms=67
```

Receiver completion:

```text
VIDEO_UDP_FRAME_WRITTEN frame_id=100 ... dropped=0 ... effect=none
...
VIDEO_UDP_FRAME_WRITTEN frame_id=129 ... dropped=0 ... effect=none
VIDEO_UDP_RECEIVER_DONE frames=42 skipped=0 packets=50400 dropped=0
```

The receiver target count was 42 because the run used 12 warmup frames plus 30
validation frames. The pass condition counts only validation frame IDs 100-129.

## Interpretation

The Linux-side network-to-HDMI transfer path is now closed for marker-backed
generated video frames:

```text
PC fb24-native UDP payload -> Linux UDP socket -> complete-frame buffer
-> direct row memcpy into /dev/fb0 -> VDMA HDMI scanout -> HDMI/UVC capture
-> saved-image unified trace validator
```

This directly addresses the review's Tier 1 recommendation. It does not yet
replace fbdev with DRM/KMS page-flip or GStreamer; those remain the mature
next-step display pipeline if the goal becomes smoother human-facing video
rather than a verified engineering transfer chain.

## Residual Risks

- The sender still reports configured `sender_fps=15`; the measured host send
  cadence is not used as this cycle's pass gate. The evidence proves ordered
  network-to-HDMI frame transfer, not a 15 fps wall-clock playback guarantee.
- The HDMI evidence path uses marker-backed generated frames, not a real video
  file or compressed stream.
- Direct memcpy is verified for the current framebuffer byte layout only. If a
  future image changes `/dev/fb0` channel offsets, the receiver intentionally
  rejects direct mode instead of silently showing wrong colors.
- fbdev direct writes are still not vsync-locked. The next mature display
  step is DRM/KMS double buffering or a GStreamer `kmssink` path.
