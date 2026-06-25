---
name: zynq7020-environment
description: Detect and validate the Windows-hosted AMD/Xilinx toolchain and connected Zynq-7000 hardware for this repository. Use when locating Vivado 2018.3, SDK/XSCT, hw_server, USB/JTAG adapters, XC7Z020 devices, or diagnosing environment and cable failures before a build or programming operation.
---

# Zynq-7020 Environment

Run `scripts/probe-environment.ps1` before building or programming.

Run `scripts/probe-hardware.ps1` when a board is connected. It starts a private
`hw_server`, queries the JTAG chain through Vivado, writes a machine-readable
report, and stops only the server process it created.

Run `scripts/probe-uart.ps1` to sample boot output from the detected FTDI UART
channels when USB descriptors do not identify the carrier board.

Require all of the following before continuing:

- Vivado version is 2018.3.
- `vivado.bat`, `hw_server.bat`, and `xsct.bat` exist.
- The JTAG chain contains an XC7Z020 device.
- The selected project part exactly matches the detected device.

Do not infer the carrier board or LED pin from the FPGA device name. If the
carrier cannot be identified from USB descriptors or repository configuration,
request the board model or schematic before creating XDC constraints.

Read `references/environment.md` only when changing tool locations or debugging
driver discovery.
