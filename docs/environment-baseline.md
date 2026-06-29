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

Last confirmed: 2026-06-29
Confirmed by: probe-environment.ps1, probe-hardware.ps1, and PnP/NetAdapter
inspection on 2026-06-29, recorded in `build/reports/environment.json` and
`build/reports/hardware.yml`. UART COM identity cross-checked against PnP
device IDs (CH340 VID_1A86 = board UART; FTDI VID_0403 = JTAG adapter serial
channel, not board UART).

| Fact | Value | Notes |
| --- | --- | --- |
| Host OS | Windows | local machine |
| Vivado | 2018.3, invoked via WSL batch | default root `E:\Xilinx\Vivado\2018.3` |
| SDK / XSCT | 2018.3 | default root `E:\Xilinx\SDK\2018.3` |
| PetaLinux | 2018.3 installed in WSL | `/opt/petalinux-v2018.3`; source `settings.sh` as Linux user `petalinux` from a clean environment |
| PetaLinux WSL compatibility | Ubuntu 22.04 with compatibility fixes | `python` compatibility package maps to Python 2.7.18, `/bin/sh -> bash`, `en_US.UTF-8` generated, `i386` architecture enabled |
| Required tools present | `bin\vivado.bat`, `bin\hw_server.bat`, `bin\xsct.bat` | checked by probe-environment.ps1 |
| JTAG adapter | HelloFpga JTAG-JT2 26SA093A | FTDI VID `0403` PID `6011` |
| Target device | `xc7z020clg484-1` | confirmed by JTAG |
| Board | HelloFPGA Smart ZYNQ SL | |
| Active board profile | `boards/hellofpga-smart-zynq-sl-7020.tcl` | git-tracked |
| JTAG adapter serial channel | COM13 | FTDI VID `0403` PID `6011` 26SA093D; this is the JTAG adapter's own serial port, not the board UART. COM number is USB-port-dependent |
| UART | COM16 @ 115200 8N1 | USB-SERIAL CH340 VID `1A86` PID `7523`; this is the board's USB-UART. COM number is USB-port-dependent; re-identify if replugged |
| HDMI capture | DirectShow device index 1 | re-identify if capture adapter replugged |
| Ethernet | direct link, PC `192.168.1.2/24` on "以太网 2" (Realtek 1Gbps) | link up at 1000/Full confirmed 2026-06-29 |
| Board IP (baremetal) | `192.168.1.10`, MAC `00:0A:35:00:01:02` | baremetal lwIP default |
| Board IP (Linux) | `192.168.1.10/24` set manually via UART, MAC `00:0A:35:00:1E:53` | Linux image uses DHCP by default; no DHCP server on direct link, so static IP must be set after boot. MAC differs from baremetal — clear PC ARP when switching images |

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
