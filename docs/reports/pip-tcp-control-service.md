# PIP TCP Control Service Report

Date: 2026-07-04

Result: PASSED

## Objective

Replace the slow per-button UART shell control path for PL PIP presets with a
low-latency board-side TCP control service, while keeping UART as a fallback.

Success means:

- A board Linux daemon stays resident and maps the PL PIP AXI-Lite register
  block once through `/dev/mem`.
- Dashboard PIP preset buttons prefer TCP commands over UART.
- Each dashboard PIP action reports transport, end-to-end control latency, and
  PL register readback.
- A probe script can quantify the baseline without relying on visual timing.

## Implemented Route

```text
dashboard PIP button
-> POSIX TCP socket to 192.168.1.10:5012
-> /tmp/pip_effect_server resident on Zynq Linux
-> mmap(/dev/mem) once
-> PL PIP AXI-Lite registers at 0x43c00000
-> register readback returned to dashboard
```

UART remains available as a fallback path if the TCP daemon is unreachable.

## Changed Scope

- Added `pip_effect_server`, a small POSIX TCP daemon for `status`, `ping`, and
  `preset <name>` commands.
- Updated the Linux tool build to produce and hash `pip_effect_server`.
- Updated dashboard PIP preset handling to prefer TCP control and fall back to
  the previous UART `/tmp/pip_effect_ctl` path.
- Added dashboard state/action fields for PIP control transport, total control
  latency, and parsed PIP register status.
- Added `tools/probe_pip_control_latency.py` to exercise dashboard PIP actions
  and summarize latency.

## Verification

PC self-tests:

```text
python -m py_compile tools\dashboard\pc_dashboard.py tools\probe_pip_control_latency.py
PIP_CONTROL_LATENCY_PROBE_SELF_TEST_OK
DASHBOARD_SCAFFOLD_SELF_TEST_OK
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
DASHBOARD_MINIMAL_UI_SELF_TEST_OK
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
DASHBOARD_GSTREAMER_CONTROL_SELF_TEST_OK
DASHBOARD_CHINESE_UI_SELF_TEST_OK
```

Linux tool build:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
VIDEO_CONTROL_TEST_OK
VIDEO_EFFECT_TEST_OK
VDMA_MM2S_CONFIG_BUILD_OK
PIP_EFFECT_CTL_BUILD_OK
PIP_EFFECT_SERVER_BUILD_OK
```

Board deployment and daemon start:

```text
sha256sum /tmp/pip_effect_server
24ed7b0b90bc741aa910f940d547e12c858d695a8dcd8bc37fc390ffd6741e15
PIP_CONTROL_SERVER_READY host=0.0.0.0 port=5012 base=0x43c00000
ps: /tmp/pip_effect_server --port 5012
```

Direct PC-to-board TCP control:

```text
CMD status
PIP_EFFECT_STATUS tag=tcp-status ... enable=1 ... x=16 y=16 ... latency_us=48

CMD preset top-left
PIP_EFFECT_CONFIGURED base=0x43c00000 control=0x00000007 x=16 y=16
PIP_EFFECT_STATUS tag=tcp-after-config ... enable=1 ... x=16 y=16 ...
PIP_CONTROL_OK command=preset preset=top-left latency_us=54

CMD preset bottom-right
PIP_EFFECT_CONFIGURED base=0x43c00000 control=0x00000007 x=560 y=420
PIP_EFFECT_STATUS tag=tcp-after-config ... enable=1 ... x=560 y=420 ...
PIP_CONTROL_OK command=preset preset=bottom-right latency_us=41
```

Dashboard API probe:

```text
PIP_CONTROL_LATENCY_SUMMARY result=pass samples=7 ok_samples=7 transports=tcp
min_ms=1.499 p50_ms=2.184 p95_ms=21.647 max_ms=24.1
```

All seven dashboard PIP actions returned `transport=tcp` with register
readback:

```text
pip-top-left:     enable=1 x=16  y=16  scale=4 effect=0
pip-bottom-right: enable=1 x=560 y=420 scale=4 effect=0
pip-large:        enable=1 x=360 y=260 scale=2 effect=0
pip-small:        enable=1 x=560 y=420 scale=4 effect=0
pip-invert:       enable=1 x=560 y=420 scale=4 effect=1
pip-grayscale:    enable=1 x=560 y=420 scale=4 effect=2
pip-bypass:       enable=0 x=560 y=420 scale=4 effect=0
```

## Evidence

- `build/pip-tcp-control-service/linux-tools/pip_effect_server`
- `build/pip-tcp-control-service/uart_deploy_start_pip_server.log`
- `build/pip-tcp-control-service/dashboard-probe/pip-control-latency-report.json`
- `build/pip-tcp-control-service/dashboard.out.log`
- `build/pip-tcp-control-service/dashboard.err.log`
- `build/pip-tcp-control-service/dashboard.pid`
- `build/pip-tcp-control-service/http.out.log`
- `build/pip-tcp-control-service/http.err.log`

## Board Action

- Deployed `/tmp/pip_effect_server` over Ethernet using a temporary PC HTTP
  server and board `wget`.
- Started `/tmp/pip_effect_server --port 5012` from the UART shell.
- Did not replace `BOOT.BIN`, `image.ub`, rootfs, QSPI, NAND, eMMC, or board
  flash.
- Did not rebuild or reprogram FPGA logic.

## Rollback

- Stop the daemon with `killall pip_effect_server`.
- Start dashboard without a reachable TCP daemon and keep the default UART
  fallback enabled, or pass `--pip-control-no-fallback` for strict failure.
- Previous controlled-PIP route remains documented in
  `docs/reports/pl-controlled-pip-effect-pipeline.md`.

## Residual Risks

- The daemon still uses userspace `/dev/mem`, not a kernel driver.
- The TCP protocol is intentionally minimal line-based text. It is suitable for
  trusted lab LAN use, not an authenticated network service.
- The daemon is not yet integrated into board boot or system init; it was
  started manually from UART for this cycle.
- This cycle improves PIP control latency only. It does not change or revalidate
  the 5fps RTP/JPEG video transport quality.
