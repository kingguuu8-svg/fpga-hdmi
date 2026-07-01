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
  visual control skeleton first
  sender and UART actions are wired in later cycles
```

Run the scaffold self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\visual-dashboard-scaffold"
```

Run the local dashboard:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765"
```
