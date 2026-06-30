# Sustained Low-FPS Stream

Date: 2026-06-30
Cycle ID: sustained-low-fps-stream

## Objective

Prove the Linux UDP receiver can handle a sustained low-FPS multi-frame stream,
not just a single frame, while continuing to update HDMI through `/dev/fb0`.

## Scope

- Reused the existing UDP RGB888 protocol and Linux receiver.
- Added elapsed-time markers to the receiver's per-frame logs.
- Added `tools/run_sustained_stream_probe.ps1` as a reproducible host/board run
  helper.
- Sent five deterministic 800x600 RGB888 frames from the PC at low FPS.
- Did not add UART control or visual effects in this cycle.

## Implementation Notes

The first attempt exposed a reproducibility bug in the host helper, not in the
board path:

```text
Python http.server started from PowerShell remained alive but did not listen.
The board wget failed, and the first helper version still proceeded to send
UDP and capture HDMI.
```

That attempt was rejected as evidence. The helper was fixed to:

```text
1. Serve fb_video_udp_receiver through a one-shot PowerShell/.NET TcpListener.
2. Require /tmp/fb_video_udp_receiver SHA-256 verification on the board.
3. Require VIDEO_UDP_LINUX_RECEIVER_READY before sending UDP.
4. Require the exact frame-write and receiver-done markers after the stream.
```

## Verification

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_sustained_stream_probe.ps1 -Frames 5 -Fps 1 -InterPacketUs 200
```

Host build and tests:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
LINUX_RECEIVER_BUILD_OK
```

Board binary:

```text
ELF 32-bit LSB executable, ARM, EABI5, dynamically linked
SHA-256 b9a675bf12af95df866076083d6e547ce53bda9f1b9d3b834d30fbc3b7ab1b67
```

One-shot deployment:

```text
ONE_SHOT_HTTP_SERVED bytes=14232
/tmp/fb_video_udp_receiver: OK
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=5 timeout_sec=90
```

PC sender:

```text
frame=0 bytes=1440000 packets=1200 elapsed_s=0.893
frame=1 bytes=1440000 packets=1200 elapsed_s=0.877
frame=2 bytes=1440000 packets=1200 elapsed_s=0.864
frame=3 bytes=1440000 packets=1200 elapsed_s=0.860
frame=4 bytes=1440000 packets=1200 elapsed_s=0.860
SEND_OK frames=5 packets=6000 target=192.168.1.10:5005
```

Board receiver:

```text
FB_INFO path=/dev/fb0 xres=800 yres=600 xres_virtual=800 yres_virtual=1200
  bpp=24 line_length=2400 smem_len=2880000
  red_offset=16 green_offset=8 blue_offset=0
FB_CHANNEL_BYTES red=2 green=1 blue=0
VIDEO_UDP_FRAME_WRITTEN frame_id=0 frames=1 packets=1200 dropped=0 elapsed_ms=7941
VIDEO_UDP_FRAME_WRITTEN frame_id=1 frames=2 packets=2400 dropped=0 elapsed_ms=8924
VIDEO_UDP_FRAME_WRITTEN frame_id=2 frames=3 packets=3600 dropped=0 elapsed_ms=9912
VIDEO_UDP_FRAME_WRITTEN frame_id=3 frames=4 packets=4800 dropped=0 elapsed_ms=10909
VIDEO_UDP_FRAME_WRITTEN frame_id=4 frames=5 packets=6000 dropped=0 elapsed_ms=11909
VIDEO_UDP_RECEIVER_DONE frames=5 packets=6000 dropped=0 elapsed_ms=11909
```

Ethernet counters after the stream:

```text
RX packets:15466 errors:0 dropped:0 overruns:0 frame:0
TX packets:1039 errors:0 dropped:0 overruns:0 carrier:0
```

HDMI capture:

```text
HDMI_CAPTURE_OK device_index=1 backend=dshow
top_blue:     [0.05, 0.05, 254.61]
middle_green: [0.0, 255.0, 0.0]
bottom_red:  [255.0, 0.0, 0.0]
```

Raw evidence:

```text
build/sustained-low-fps-stream/test_video_udp_receiver.log
build/sustained-low-fps-stream/test_linux_framebuffer_writer.log
build/sustained-low-fps-stream/fb_video_udp_receiver.sha256.txt
build/sustained-low-fps-stream/one-shot-http-server.log
build/sustained-low-fps-stream/send_video_udp.log
build/sustained-low-fps-stream/uart_deploy_start_receiver.log
build/sustained-low-fps-stream/uart_after_stream.log
build/sustained-low-fps-stream/hdmi-after-stream/latest-validation.json
build/sustained-low-fps-stream/hdmi-after-stream/latest.png
```

## Result

Status: PASSED.

The board received and displayed a five-frame low-FPS stream with all 6000 UDP
chunks accounted for and no receiver drops. HDMI validation after the stream
passed.

## Residual Risks

- This is still a paced low-FPS proof, not a high-throughput realtime target.
- The displayed pattern was deterministic and static across frames; this cycle
  proves repeated transport/display updates, not visual motion.
- The receiver is still manually deployed to `/tmp`; it is not yet integrated
  into the root filesystem or init system.
