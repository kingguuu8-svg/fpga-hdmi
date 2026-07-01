# PC Dashboard

The dashboard is a PC-side web console for the Zynq video pipeline.

MVP panels:

```text
Input To FPGA:
  exact deterministic generated PC frame used by the UDP sender
  no camera/webcam input
  custom file input deferred after MVP

FPGA Output:
  latest HDMI capture snapshot or placeholder
  output verification only, not an input source or continuous video widget

Function Control Panel:
  start/stop controls a dashboard-owned demo sender subprocess
  start-stream schedules one HDMI capture attempt asynchronously
  capture-output schedules a manual HDMI snapshot refresh
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
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-truthful-loop-validation -CaptureDevice 1 -CaptureFrames 90 -CaptureSaveSamples 6 -Frames 12 -Fps 2 -InterPacketUs 200
```

This deploys the receiver to `/tmp`, starts the dashboard, triggers
`start-stream`, requires non-black HDMI capture, and requires saved HDMI
samples to contain dynamic output changes.

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
  live local sender subprocess control

capture-output:
  asynchronous HDMI snapshot capture through tools/capture_hdmi.py

pause-receiver / resume-receiver / receiver-status:
  UART command helper, requiring --uart-port and a ready board receiver FIFO

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
