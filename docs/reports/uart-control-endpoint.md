# UART Control Endpoint

Date: 2026-06-30
Cycle ID: uart-control-endpoint

## Objective

Add a UART-driven control path to the Linux receiver process and prove that a
UART command changes receiver behavior while UDP video input and HDMI output
remain working.

## Scope

- Added a minimal command parser with host tests.
- Added `--control-fifo` to the Linux receiver.
- Used UART shell commands to write `pause`, `resume`, and `status` into the
  FIFO.
- Proved that a complete UDP frame is skipped while paused, then a later frame
  is written after resume.
- Did not add visual effects in this cycle.

## Control Interface

The current UART fallback control path is:

```text
UART shell
-> echo <command> > /tmp/video_ctl
-> receiver --control-fifo /tmp/video_ctl
-> receiver state change
```

Supported commands in this cycle:

```text
pause
resume
status
quit
```

This is intentionally a minimal fallback endpoint. The same command semantics
can later be moved to TCP/UDP without changing the receiver state model.

## Verification

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_uart_control_probe.ps1
```

Host build and tests:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
VIDEO_CONTROL_TEST_OK
LINUX_RECEIVER_BUILD_OK
```

Board binary:

```text
ELF 32-bit LSB executable, ARM, EABI5, dynamically linked
SHA-256 41a7509a7e744054066e6f583f419e2d33193657e0735bd7db75d2d96469a575
```

Deployment:

```text
ONE_SHOT_HTTP_SERVED bytes=18816
/tmp/fb_video_udp_receiver: OK
CONTROL_FIFO_READY path=/tmp/video_ctl
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=1 timeout_sec=120 control=/tmp/video_ctl
```

UART control and UDP evidence:

```text
CONTROL_PAUSED commands=1
frame=100 bytes=1440000 packets=1200 elapsed_s=0.921
VIDEO_UDP_FRAME_SKIPPED_PAUSED frame_id=100 skipped=1 packets=1200 dropped=0

CONTROL_RESUMED commands=2
CONTROL_STATUS paused=0 quit=0 commands=3 unknown=0
frame=101 bytes=1440000 packets=1200 elapsed_s=0.887
VIDEO_UDP_FRAME_WRITTEN frame_id=101 frames=1 packets=2400 dropped=0 skipped=1
VIDEO_UDP_RECEIVER_DONE frames=1 skipped=1 packets=2400 dropped=0
```

Ethernet counters after the probe:

```text
RX packets:17885 errors:0 dropped:0 overruns:0 frame:0
TX packets:1127 errors:0 dropped:0 overruns:0 carrier:0
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
build/uart-control-endpoint/test_video_control.log
build/uart-control-endpoint/one-shot-http-server.log
build/uart-control-endpoint/uart_pause.log
build/uart-control-endpoint/uart_after_paused_frame.log
build/uart-control-endpoint/uart_resume_status.log
build/uart-control-endpoint/uart_final.log
build/uart-control-endpoint/hdmi-after-uart-control/latest-validation.json
```

## Result

Status: PASSED.

UART shell commands now control the running Linux receiver. The test proves that
`pause` changes behavior by suppressing a complete frame write, and `resume`
restores the proven UDP-to-HDMI path.

## Residual Risks

- The FIFO endpoint is a minimal Linux userspace fallback, not a polished daemon
  protocol.
- Control persistence, authentication, command acknowledgements to a PC-side UI,
  and TCP/UDP command transport are not implemented yet.
- The visual output is still pass-through; the next cycle should add the first
  board-side visual effect.
