# Dashboard HDMI Capture Binding

Date: 2026-07-01

## Objective

Make the dashboard output panel capture HDMI after `start-stream`, instead of
only displaying a placeholder or a pre-existing image.

## Changed Scope

- Added `none` validation profile to `tools/capture_hdmi.py` for preview
  captures where the expected visual pattern is not fixed.
- Added dashboard HDMI capture configuration:
  - `--capture-device`
  - `--capture-backend`
  - `--capture-width`
  - `--capture-height`
  - `--capture-frames`
  - `--capture-profile`
  - `--capture-disabled`
- Added `capture-output` dashboard action.
- Changed `start-stream` so it starts the real sender process and then runs one
  HDMI capture attempt.
- Changed the output preview image to refresh every poll.

## Verification

Ran:

```powershell
rtk powershell.exe -NoProfile -Command "python -m py_compile .\tools\dashboard\pc_dashboard.py .\tools\capture_hdmi.py .\tools\send_demo_video_udp.py"
```

Ran deterministic dashboard self-test with HDMI capture disabled:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-hdmi-capture-binding"
```

Results:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK out=build\dashboard-hdmi-capture-binding
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK out=build\dashboard-hdmi-capture-binding actions=5
DASHBOARD_MINIMAL_UI_SELF_TEST_OK out=build\dashboard-hdmi-capture-binding
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK out=build\dashboard-hdmi-capture-binding actions=5
```

Ran live HDMI preview capture:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\capture_hdmi.py --device auto --backend dshow --width 800 --height 600 --frames 20 --validation-profile none --out-dir build\dashboard-hdmi-capture-binding\hdmi-capture"
```

Result:

```text
HDMI_CAPTURE_IMAGE build\dashboard-hdmi-capture-binding\hdmi-capture\latest.png
HDMI_CAPTURE_REPORT build\dashboard-hdmi-capture-binding\hdmi-capture\latest-validation.json
HDMI_CAPTURE_OK device_index=0 backend=dshow image=build\dashboard-hdmi-capture-binding\hdmi-capture\latest.png
```

The capture report shows the DirectShow adapter opened and wrote a frame.
The captured frame was near black (`mean_luma=0.05`). That proves the PC HDMI
capture path is callable, but it does not prove the board receiver is currently
displaying a meaningful stream.

## Board Action

PC-side HDMI capture only. No Vivado rebuild, PetaLinux rebuild, JTAG
programming, or board flash write.

## Result

PASSED for dashboard/capture binding. `start-stream` is now wired to launch the
sender and attempt HDMI capture, and `capture-output` can be used to refresh the
output panel manually.

## Residual Risks

- The capture image during this cycle was near black. The next live-board issue
  is likely receiver/display readiness, not dashboard capture wiring.
- `start-stream` sends UDP frames; it does not deploy or start
  `/tmp/fb_video_udp_receiver` on the board.
- The output panel is capture-on-action/poll-refresh, not continuous video
  preview yet.
