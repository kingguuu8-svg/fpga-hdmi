# Dashboard Control Integration

Date: 2026-07-01

## Objective

Wire the PC visual dashboard to actionable stream/control commands while keeping
the verification path deterministic and PC-side.

## Changed Scope

- Extended `tools/dashboard/pc_dashboard.py` with:
  - `/api/actions` action catalog
  - `/api/action` POST endpoint
  - dashboard button handlers
  - dry-run action runner
  - control state for stream, receiver pause state, selected effect, and logs
- Kept the input source policy unchanged:
  - no camera/webcam input
  - no user-selectable custom-file input
- Kept live board transports out of this cycle. The action surface records
  command semantics that can later bind to real sender subprocess and UART/FIFO
  operations.

## Action Semantics

The dry-run action catalog is aligned to the routes already proven in earlier
cycles:

```text
start-stream     -> python tools/send_demo_video_udp.py 192.168.1.10 --port 5005 --frames 5 --fps 1
stop-stream      -> stop dashboard-owned demo sender process
pause-receiver   -> FIFO/UART command: pause
resume-receiver  -> FIFO/UART command: resume
receiver-status  -> FIFO/UART command: status
effect-none      -> receiver launch argument: --effect none
effect-invert    -> receiver launch argument: --effect invert
```

`effect-*` is intentionally recorded as receiver launch semantics, not claimed
as a proven runtime effect switch.

## Verification

Ran:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-control-integration"
```

Result:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK out=build\dashboard-control-integration
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK out=build\dashboard-control-integration actions=6
```

The self-test verified:

- dashboard HTML loads
- input preview panel exists
- FPGA output preview panel exists
- function-control panel exists
- control buttons expose `data-action` hooks
- `/api/actions` returns the expected action catalog
- `/api/action` accepts six dry-run actions
- action logs record sender, FIFO/UART, and effect semantics
- final stream state is stopped
- final receiver pause state is false
- final selected effect is invert
- camera input remains disabled
- custom-file input remains disabled

Raw evidence:

```text
build/dashboard-control-integration/actions.json
build/dashboard-control-integration/action-results.json
build/dashboard-control-integration/final-state.json
build/dashboard-control-integration/index.html
```

## Board Action

None. This is a PC-side dashboard action-surface integration gate.

## Result

PASSED. The dashboard now has a tested visual control surface and HTTP API for
the MVP actions, without requiring a live board during the UI verification
cycle.

## Residual Risks

- Actions are dry-run only; no sender subprocess is started by the dashboard
  yet.
- UART/FIFO commands are represented as semantics, not transmitted from the
  dashboard yet.
- Runtime effect switching is not proven; current effect semantics map to
  receiver launch options.
