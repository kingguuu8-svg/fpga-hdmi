# Dashboard HDMI Capture Timeout Fix

Date: 2026-07-01

## Objective

Fix the real `start-stream` path timing out while calling HDMI capture from the
dashboard.

## Problem

After `dashboard-hdmi-capture-binding` was committed, a live dashboard API test
showed:

```text
capture warning: HDMI_CAPTURE_TIMEOUT report=build\dashboard-live\hdmi-capture\latest-validation.json
```

Root cause: dashboard allowed only about 12 seconds for capture, while the
DirectShow HDMI capture path can take around 30 seconds on this machine.

## Changed Scope

- Increased dashboard HDMI capture subprocess timeout to at least 90 seconds.
- Reduced default dashboard preview capture frames from 20 to 8.

## Verification

Ran:

```powershell
rtk powershell.exe -NoProfile -Command "python -m py_compile .\tools\dashboard\pc_dashboard.py"
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-hdmi-capture-timeout-fix"
```

Results:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK out=build\dashboard-hdmi-capture-timeout-fix
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK out=build\dashboard-hdmi-capture-timeout-fix actions=5
DASHBOARD_MINIMAL_UI_SELF_TEST_OK out=build\dashboard-hdmi-capture-timeout-fix
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK out=build\dashboard-hdmi-capture-timeout-fix actions=5
```

Restarted the dashboard and tested the actual user path:

```text
POST /api/action {"action":"start-stream"}
POST /api/action {"action":"stop-stream"}
```

Result:

```text
start_ok=true
start_detail=sender started ... HDMI_CAPTURE_OK image=build\dashboard-live\hdmi-capture\latest.png
stop_ok=true
capture_status=ok
image_exists=true
```

The capture report recorded `mean_luma=0.14`, so the dashboard now captures an
image, but the image content is still near black. That remaining issue is board
receiver/output readiness, not dashboard capture invocation.

## Board Action

PC-side dashboard process and HDMI capture only. No Vivado, PetaLinux, JTAG, or
board flash action.

## Result

PASSED. Clicking `start-stream` now triggers HDMI capture successfully in the
dashboard process.

## Residual Risks

- HDMI preview content is near black until the board receiver/display path is
  active.
- Capture is still action-triggered, not continuous realtime preview.
