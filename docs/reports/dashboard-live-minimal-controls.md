# Dashboard Live Minimal Controls

Date: 2026-07-01

## Objective

Make the PC dashboard functional and visually minimal.

## Changed Scope

- Reworked `tools/dashboard/pc_dashboard.py` into a plain functional web view:
  no decorative background, no gradient buttons, no shadows, no card styling.
- Changed the default dashboard action mode from dry-run to live.
- Made `start-stream` launch the real `tools/send_demo_video_udp.py` process.
- Made `stop-stream` terminate the dashboard-owned sender process.
- Added sender parameters to the dashboard CLI:
  `--sender-width`, `--sender-height`, `--sender-payload`,
  `--sender-inter-packet-us`.
- Added UART/FIFO binding through the existing `tools/uart_run_commands.ps1`
  helper when `--uart-port` is configured.
- Added `--uart-disabled` for explicit no-UART operation.
- Extended `tools/send_demo_video_udp.py` so `--frames 0` means continuous send
  until stopped.

## Functional Boundaries

```text
Start stream:
  Starts a dashboard-owned Python sender subprocess.

Stop stream:
  Terminates that dashboard-owned subprocess. On Windows, the terminated
  continuous sender reports exit_code=1; this is expected for a forced stop.

Pause/resume/status:
  Sends shell commands through the configured UART port to the existing board
  receiver FIFO path. These actions require the board to be at a shell prompt
  and the receiver to have created /tmp/video_ctl.

Effect none/invert:
  Updates dashboard-selected effect semantics. Runtime effect switching is not
  claimed; current receiver effects are launch-time arguments.
```

## Verification

Ran:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-live-minimal-controls"
```

Result:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK out=build\dashboard-live-minimal-controls
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK out=build\dashboard-live-minimal-controls actions=4
DASHBOARD_MINIMAL_UI_SELF_TEST_OK out=build\dashboard-live-minimal-controls
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK out=build\dashboard-live-minimal-controls actions=4
```

Also ran:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\fixed-demo-video-sender"
rtk powershell.exe -NoProfile -Command "python -m py_compile .\tools\dashboard\pc_dashboard.py .\tools\send_demo_video_udp.py .\tools\dashboard\demo_source.py"
```

Results:

```text
DEMO_VIDEO_SENDER_SELF_TEST_OK out=build\fixed-demo-video-sender packets=30
```

The dashboard self-test verified:

- HTML loads and contains the three required panels
- HTML contains no `gradient` or `box-shadow`
- `start-stream` launches a real sender subprocess
- localhost receives a real `ZVID` UDP packet from that subprocess
- `stop-stream` terminates the dashboard-owned sender
- `pause-receiver` returns `UART_NOT_CONFIGURED` when no UART port is provided
- `effect-invert` updates dashboard state
- camera input remains disabled
- custom-file input remains disabled

Raw evidence:

```text
build/dashboard-live-minimal-controls/action-results.json
build/dashboard-live-minimal-controls/final-state.json
build/dashboard-live-minimal-controls/sender.out.log
build/dashboard-live-minimal-controls/index.html
```

## Board Action

None in the automated gate. UART live binding was implemented but not exercised
against the connected board in this cycle.

## Result

PASSED. The dashboard is now a minimal functional control panel. The stream
buttons control a real local sender process; UART receiver controls are wired to
the existing UART helper and fail explicitly when UART is not configured.

## Residual Risks

- The dashboard does not deploy or start the board receiver process.
- UART/FIFO buttons require the board shell and `/tmp/video_ctl` to already be
  available.
- Runtime effect switching is still not implemented in the receiver.
