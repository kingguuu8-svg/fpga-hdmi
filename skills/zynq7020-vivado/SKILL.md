---
name: zynq7020-vivado
description: Generate and build deterministic Vivado 2018.3 hardware for an XC7Z020 board in this repository. Use when creating RTL examples, applying verified board profiles and XDC constraints, running synthesis and implementation, checking DRC and timing, or producing a bitstream and reports.
---

# Zynq-7020 Vivado

Use `scripts/sim-wsl.ps1 -Example video-pip` before building the video pipeline
MVP. Then use `scripts/build-wsl.ps1 -BoardProfile <path> -Example video-pip`
to produce the downloadable HDMI/PIP bitstream.

Use `scripts/build-wsl.ps1 -BoardProfile <path>` for the clocked LED chaser MVP
on this machine. Use `-Example led-static` only when the board profile has no
verified PL clock yet.
It invokes the WSL-installed Vivado 2018.3 in batch mode and keeps generated
state under `build/`. Use `scripts/build.ps1` only to diagnose the Windows
Vivado installation.

Before building:

1. Verify the exact FPGA part, package, speed grade, LED pins, I/O voltage, and
   active polarity against the carrier schematic or a trusted board reference.
   Also verify oscillator frequency/pin before any clocked example.
2. Create one board profile under `boards/`; do not modify the generic RTL for
   board differences.
3. Reject empty pins, non-XC7Z020 parts, and unsupported profile fields.

The build must stop on synthesis, implementation, DRC, unconstrained I/O, or
timing failure. Do not downgrade critical DRC checks to warnings.

For `video-pip`, treat the xsim markers as gates:

```text
STAGE1_TIMING_AND_PATTERN_OK
STAGE2_PIP_OK
STAGE3_EFFECT_PIPE_OK
STAGE4_BUTTON_CONTROL_OK
SIM_OK
```

Read `references/board-profile.md` when adding a board.
