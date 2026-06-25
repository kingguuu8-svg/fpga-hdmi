---
name: zynq7020-hardware
description: Detect, program, and verify the connected XC7Z020 development board for this repository. Use when selecting an XSCT or openFPGALoader JTAG backend, scanning the FT4232 chain, downloading a Vivado bitstream to SRAM, validating device identity, or diagnosing cable and driver failures.
---

# Zynq-7020 Hardware

Prefer `scripts/program-xsct.ps1` when Xilinx `hw_server` exposes the Zynq
target. Use `scripts/program-openfpgaloader.ps1` for a generic FT4232H adapter
whose JTAG interface is bound to WinUSB.

Before programming:

1. Run the environment and hardware probes.
2. Verify the bitstream was built for the exact connected XC7Z020 part.
3. Program SRAM only for the MVP. Do not write QSPI, NAND, eMMC, or SD media.
4. Record the backend, bitstream hash, and command result under
   `build/reports/`.

Never rewrite the FTDI EEPROM as part of the normal pipeline. Driver changes
must target only interface A (`MI_00`) and leave UART interfaces unchanged.

Read `references/jtag-backends.md` when changing drivers or backends.

