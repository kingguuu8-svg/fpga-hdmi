# PC Dashboard

The dashboard is a PC-side web console for the Zynq video pipeline.

MVP panels:

```text
Input To FPGA:
  deterministic generated PC preview
  no camera/webcam input
  custom file input deferred after MVP

FPGA Output:
  latest HDMI capture image slot or placeholder
  output verification only, not an input source

Function Control Panel:
  visual control skeleton
  fixed demo-video sender is available as a standalone CLI
  dry-run action API covers sender start/stop, UART/FIFO pause/resume/status,
  and effect selection semantics
```

Run the scaffold self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\visual-dashboard-scaffold"
```

Run the control-integration self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-control-integration"
```

Run the fixed demo-video sender self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\fixed-demo-video-sender"
```

Run the local dashboard:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765"
```

The dashboard action API is currently dry-run:

```text
GET  /api/actions
POST /api/action {"action":"start-stream"}
POST /api/action {"action":"stop-stream"}
POST /api/action {"action":"pause-receiver"}
POST /api/action {"action":"resume-receiver"}
POST /api/action {"action":"receiver-status"}
POST /api/action {"action":"effect-none"}
POST /api/action {"action":"effect-invert"}
```
