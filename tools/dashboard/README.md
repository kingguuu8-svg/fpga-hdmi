# PC Dashboard

The dashboard is a PC-side web console for the Zynq video pipeline.

MVP panels:

```text
Input To FPGA:
  exact deterministic generated PC frame used by the UDP sender
  no camera/webcam input
  custom file input deferred after MVP

FPGA Output:
  live HDMI return MJPEG stream from the capture adapter
  output verification only, not an input source

Function Control Panel:
  start/stop controls a dashboard-owned demo sender subprocess
  start-stream starts the sender and exposes the live HDMI return endpoint
  capture-output is only a manual HDMI snapshot fallback
  UART/FIFO pause/resume/status uses the existing UART helper when configured
  effect selection records receiver launch semantics
```

Run the scaffold self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\visual-dashboard-scaffold"
```

Run the minimal live-control self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-live-minimal-controls"
```

Run the HDMI-capture binding self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-hdmi-capture-binding"
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

Run the local dashboard:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765"
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
start-stream / stop-stream:
  live local color-block sender subprocess control

right panel:
  live HDMI return through /api/output-stream.mjpeg

capture-output:
  manual HDMI snapshot capture through tools/capture_hdmi.py; not the primary
  right-panel video path

pause-receiver / resume-receiver / receiver-status:
  UART command helper, requiring --uart-port and a ready board receiver FIFO;
  live mode returns tailed receiver CONTROL_/VIDEO_UDP_ markers

effect-none / effect-invert:
  dashboard state only; applies to later receiver launch flow
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
