# Visual Dashboard Scaffold

Date: 2026-07-01
Cycle ID: visual-dashboard-scaffold

## Objective

Add the first PC-side visual dashboard scaffold with input preview, FPGA output
preview, and a control/log panel skeleton.

## Scope

- Added `tools/dashboard/pc_dashboard.py`, a local Python stdlib web dashboard.
- Added `tools/dashboard/README.md`.
- Implemented three MVP panels:
  - Input To FPGA
  - FPGA Output
  - Function Control Panel
- Input preview is deterministic PC-generated SVG content.
- Custom input files are explicitly deferred after MVP.
- Camera/webcam input is disabled and not used as a project input source.
- FPGA output preview is a latest-HDMI-capture image slot or a placeholder.
- Control buttons are visual placeholders only in this cycle.

## Verification

Command:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\visual-dashboard-scaffold"
```

Result:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK out=build\visual-dashboard-scaffold
```

The self-test started a local server and fetched:

```text
/
/api/state
/api/input-preview.svg?frame=7
/api/output-preview
```

Assertions covered:

```text
HTML contains input, output, and control panel regions.
State JSON reports camera_enabled=false.
State JSON reports custom_file_enabled=false.
State logs include "camera/webcam input: disabled".
Input SVG contains GENERATED INPUT.
Output endpoint returns the FPGA output placeholder.
```

Raw evidence:

```text
build/visual-dashboard-scaffold/index.html
build/visual-dashboard-scaffold/state.json
build/visual-dashboard-scaffold/input-preview.svg
build/visual-dashboard-scaffold/output-placeholder.svg
```

## Result

Status: PASSED.

The PC dashboard scaffold is available and self-tested. It provides the visual
layout needed for the next cycles without using a camera/webcam input source
and without implementing custom file input in the MVP.

## Residual Risks

- The scaffold does not yet send UDP video.
- The scaffold does not yet issue UART commands.
- The FPGA output panel only displays a configured capture file or placeholder;
  live refresh is a later integration detail.
