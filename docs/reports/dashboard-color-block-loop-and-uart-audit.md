# Dashboard Color Block Loop And UART Audit

Date: 2026-07-01

## Objective

Replace the visually ambiguous generated demo with full-screen sequential color
blocks, then verify the complete loop with machine-readable evidence:

```text
PC generated color block -> UDP sender -> board Linux receiver -> /dev/fb0
-> VDMA/HDMI -> PC HDMI capture adapter -> Dashboard live MJPEG right panel
```

Also verify that the Dashboard UART controls can drive the running receiver
through `/tmp/video_ctl` and report real receiver responses.

## Changed Scope

- Replaced the demo generator with full-screen RGB888 color blocks:
  red, green, blue, white, black, yellow, cyan, and magenta.
- Added sender log output for the color name of every transmitted frame.
- Added MJPEG return-stream color classification to
  `tools/probe_mjpeg_stream.py`.
- Added finite validation and keep-running demo modes to
  `tools/run_dashboard_board_live_loop.ps1`.
- Disabled the Linux framebuffer console cursor before starting the receiver.
  This removes the small black blinking overlay that was visible on HDMI.
- Changed Dashboard UART actions to pass commands through a command file and
  include tailed receiver markers in the action response.

## Verification

### Local checks

```text
rtk powershell.exe -NoProfile -Command "python -m py_compile tools\dashboard\demo_source.py tools\send_demo_video_udp.py tools\dashboard\pc_dashboard.py tools\probe_mjpeg_stream.py tools\capture_hdmi.py"
```

Result: passed.

```text
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\dashboard-color-block-loop-and-uart-audit\sender-selftest"
```

Result:

```text
DEMO_VIDEO_SENDER_SELF_TEST_OK ... packets=30
```

The self-test report records:

```text
pattern=full-screen-sequential-color-blocks
palette=red,green,blue,white,black,yellow,cyan,magenta
camera_input=false
custom_file_input=false
received_packets=30
```

```text
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-color-block-loop-and-uart-audit\dashboard-selftest-after-uart-fix"
```

Result:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
DASHBOARD_MINIMAL_UI_SELF_TEST_OK
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
```

```text
rtk powershell.exe -NoProfile -Command "$text=Get-Content -Raw tools\run_dashboard_board_live_loop.ps1; [void][scriptblock]::Create($text); Write-Host 'PS_PARSE_OK'"
```

Result: `PS_PARSE_OK`.

### Finite board loop

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\finite-loop -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200
```

Marker:

```text
DASHBOARD_BOARD_LIVE_LOOP_OK mode=finite receiver_frames=12 sender_frames=12 written=12 mjpeg_frames=80 mjpeg_unique=8 mjpeg_colors=8 color_names=black,blue,cyan,green,magenta,red,white,yellow
```

Sender evidence:

```text
demo_frame=0 color=red bytes=1440000 packets=1200
demo_frame=1 color=green bytes=1440000 packets=1200
demo_frame=2 color=blue bytes=1440000 packets=1200
demo_frame=3 color=white bytes=1440000 packets=1200
demo_frame=4 color=black bytes=1440000 packets=1200
demo_frame=5 color=yellow bytes=1440000 packets=1200
demo_frame=6 color=cyan bytes=1440000 packets=1200
demo_frame=7 color=magenta bytes=1440000 packets=1200
DEMO_VIDEO_SEND_OK frames=12 packets=14400 target=192.168.1.10:5005
```

Receiver evidence:

```text
CONTROL_FIFO_READY path=/tmp/video_ctl
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=12 timeout_sec=180 control=/tmp/video_ctl effect=none
VIDEO_UDP_FRAME_WRITTEN frame_id=0 frames=1 packets=1200 dropped=0 skipped=0 effect=none
...
VIDEO_UDP_FRAME_WRITTEN frame_id=11 frames=12 packets=14400 dropped=0 skipped=0 effect=none
VIDEO_UDP_RECEIVER_DONE frames=12 skipped=0 packets=14400 dropped=0
```

HDMI return evidence:

```text
MJPEG_STREAM_PROBE_OK frames=80 unique=8 colors=black,blue,cyan,green,magenta,red,white,yellow
```

This proves the Dashboard right panel is consuming a live HDMI return stream
whose frames classify as the PC source color blocks. It is not a stale static
image and not the previous decorative PIP/checker demo.

### Keep-running demo loop

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\live-demo -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 40 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200 -KeepRunning
```

Marker:

```text
DASHBOARD_BOARD_LIVE_LOOP_OK mode=keep-running receiver_frames=1000000 sender_frames=0 written=19 mjpeg_frames=40 mjpeg_unique=7 mjpeg_colors=7 color_names=black,cyan,green,magenta,red,white,yellow
```

The Dashboard was left running at `http://127.0.0.1:8765` for live inspection.

### UART control

Bottom-layer UART/FIFO probe:

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_uart_control_probe.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\uart-control-probe -CaptureDevice 1
```

Observed receiver markers:

```text
CONTROL_PAUSED commands=1
VIDEO_UDP_FRAME_SKIPPED_PAUSED frame_id=100 skipped=1 packets=1200 dropped=0
CONTROL_RESUMED commands=2
CONTROL_STATUS paused=0 quit=0 commands=3 unknown=0
VIDEO_UDP_FRAME_WRITTEN frame_id=101 frames=1 packets=2400 dropped=0 skipped=1 effect=none
VIDEO_UDP_RECEIVER_DONE frames=1 skipped=1 packets=2400 dropped=0
HDMI_CAPTURE_OK
UART_CONTROL_PROBE_OK
```

Dashboard action API probe against the live demo:

```text
pause-receiver: http_status=200, response contains CONTROL_PAUSED and VIDEO_UDP_FRAME_SKIPPED_PAUSED
receiver-status while paused: http_status=200, response contains CONTROL_STATUS paused=1
resume-receiver: http_status=200, response contains CONTROL_RESUMED and VIDEO_UDP_FRAME_WRITTEN
receiver-status after resume: http_status=200, response contains CONTROL_STATUS paused=0
```

The previous Dashboard UART failure was caused by passing multi-word UART shell
commands through the PowerShell `-Command` array path. `sleep 1` was bound as a
file path in the helper. The Dashboard now writes a command file and calls
`uart_run_commands.ps1 -CommandFile ...`, which avoids that parameter-binding
failure.

## Result

PASSED.

The current demo source is a simple full-screen color-block video. The PC sender
logs the exact source color sequence, the board receiver writes those frames
with `effect=none` and `dropped=0`, the Dashboard right panel sees a live HDMI
MJPEG stream classified as the same source color set, and UART pause/resume/
status controls produce real receiver responses.

## Residual Risks

- HDMI/UVC capture and MJPEG encoding prevent pixel-perfect equality checks.
  The current proof is semantic color classification plus receiver packet/write
  markers.
- The input preview and HDMI return preview are not frame-locked.
- `-KeepRunning` uses a large finite receiver frame count and a 3600 second
  receiver timeout; it is a demo mode, not a persistent system service.
- `effect-none` and `effect-invert` Dashboard buttons still describe receiver
  launch selection. Runtime effect switching is not claimed by this cycle.
