# Environment Baseline

This file records the one-time-confirmed environment facts for this machine
and connected board. It is git-tracked. The project skills read it to decide
whether to re-probe the environment or skip probing and trust the baseline.

## How to use this file

- The environment skills may skip probing when this file exists and none of the
  invalidation conditions below are met.
- When any invalidation condition is met, re-run
  `skills/zynq7020-environment/scripts/probe-environment.ps1` and
  `probe-hardware.ps1`, confirm the results match this file (or update this
  file to match), and only then trust the baseline again.
- This file is a fact owner for "current environment facts" in the sense of the
  AGENTS.md fact-consistency rule. Other documents and skills reference it
  rather than restating these values.

## Confirmed facts

Last confirmed: 2026-06-26
Confirmed by: prior probe runs recorded in `build/reports/environment.json`,
`build/reports/hardware.yml`, and `docs/boards/hellofpga-smart-zynq-sl.md`.

| Fact | Value | Notes |
| --- | --- | --- |
| Host OS | Windows | local machine |
| Vivado | 2018.3, invoked via WSL batch | default root `E:\Xilinx\Vivado\2018.3` |
| SDK / XSCT | 2018.3 | default root `E:\Xilinx\SDK\2018.3` |
| Required tools present | `bin\vivado.bat`, `bin\hw_server.bat`, `bin\xsct.bat` | checked by probe-environment.ps1 |
| JTAG adapter | HelloFpga JTAG-JT2 26SA093A | FTDI VID `0403` PID `6011` |
| Target device | `xc7z020clg484-1` | confirmed by JTAG |
| Board | HelloFPGA Smart ZYNQ SL | |
| Active board profile | `boards/hellofpga-smart-zynq-sl-7020.tcl` | git-tracked |
| UART | COM16 and COM27 @ 115200 8N1 | COM numbers are USB-port-dependent; re-identify if replugged |
| HDMI capture | DirectShow device index 1 | re-identify if capture adapter replugged |
| Ethernet | direct link, PC `192.168.1.2/24`, board `192.168.1.10` | board IP is the baremetal default; Linux image IP must be re-read from boot logs |

## Invalidation conditions

Re-probe and re-confirm this baseline when any of the following is true:

- The machine, board, or Vivado/SDK installation is changed or reinstalled.
- A Vivado version other than 2018.3 is selected.
- A Windows update is followed by JTAG or UART failure.
- The JTAG adapter, USB port, or capture adapter is physically changed or replugged and the enumerated COM/index no longer matches the table above.
- A probe run produces a result that contradicts any fact in the table above.
- This file's "Last confirmed" date is older than the most recent hardware operation recorded in `docs/cycle-log.md` AND a probe has not been run since.

The baseline is intentionally event-triggered, not time-triggered. Silent
environment drift that does not affect an active JTAG/UART/Ethernet operation
does not by itself require a re-probe; the drift will surface as a probe
contradiction the next time the affected interface is actually used.
