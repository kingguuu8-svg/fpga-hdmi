# PC Dashboard

The dashboard is a PC-side web console for the Zynq video pipeline.
The preferred mode is now the GStreamer route, not the legacy custom UDP/fbdev
route.

MVP panels:

```text
Input To FPGA:
  local preview of the PC GStreamer videotestsrc ball source
  no camera/webcam input
  custom file input deferred after MVP

FPGA Output:
  live HDMI return MJPEG stream from the capture adapter
  output verification only, not an input source

Function Control Panel:
  start-stream starts the board GStreamer receiver over UART and the PC
  GStreamer RTP/raw sender
  stop-stream stops the PC sender and attempts to stop the board receiver
  capture-output is only a manual HDMI snapshot fallback
  receiver-status tails the board GStreamer receiver log over UART
  pause/resume/effect controls are legacy UDP/fbdev controls and are explicit
  not-implemented in GStreamer mode
```

Run the GStreamer/Chinese UI self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-gstreamer-chinese-control"
```

Expected markers include:

```text
DASHBOARD_GSTREAMER_CONTROL_SELF_TEST_OK
DASHBOARD_CHINESE_UI_SELF_TEST_OK
```

Run the displayable board-live loop:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\finite-loop -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200
```

This deploys the receiver to `/tmp`, starts the dashboard, triggers
`start-stream`, reads `/api/output-stream.mjpeg`, and requires the returned
MJPEG stream to classify as the generated full-screen color-block source.

Run the board-live loop and leave the dashboard/sender running:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\live-demo -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 40 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200 -KeepRunning
```

Run the fixed demo-video sender self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\fixed-demo-video-sender"
```

Run the local GStreamer dashboard:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765 --pipeline gstreamer --uart-port COM16 --uart-login-root --uart-password root"
```

Dashboard action API:

```text
GET  /api/actions
POST /api/action {"action":"start-stream"}
POST /api/action {"action":"stop-stream"}
POST /api/action {"action":"capture-output"}
POST /api/action {"action":"pause-receiver"}
POST /api/action {"action":"resume-receiver"}
POST /api/action {"action":"receiver-status"}
POST /api/action {"action":"effect-none"}
POST /api/action {"action":"effect-invert"}
```

Current behavior:

```text
start-stream:
  board: kill stale gst-launch processes, hide the active framebuffer console
    cursor, then run udpsrc port=5011 ! rtpjitterbuffer ! rtpjpegdepay !
    jpegdec ! videoconvert ! videoscale ! fbdevsink device=/dev/fb0
  PC: conda GStreamer videotestsrc ball ! tee; one branch records the actual
    RGB source preview, the other uses I420 ! jpegenc ! rtpjpegpay ! udpsink

right panel:
  live HDMI return through /api/output-stream.mjpeg

capture-output:
  manual HDMI snapshot capture through tools/capture_hdmi.py; not the primary
  right-panel video path

pause-receiver / resume-receiver / receiver-status:
  receiver-status tails the board GStreamer receiver log in GStreamer mode;
  pause/resume are not implemented for the gst-launch route

effect-none / effect-invert:
  not implemented for the gst-launch route; retained only for legacy UDP mode
```

Disable UART explicitly if the serial port should not be touched:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --uart-disabled"
```

Use dry-run mode only when testing command semantics without launching the
sender process:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --action-mode dry-run"
```

Use legacy UDP/fbdev mode only for recovery comparison with older dashboard
cycles:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --pipeline legacy-udp"
```
