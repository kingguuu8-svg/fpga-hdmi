---
name: zynq7020-vivado
description: Generate and build deterministic Vivado 2018.3 hardware for an XC7Z020 board in this repository. Use when creating RTL examples, applying verified board profiles and XDC constraints, running synthesis and implementation, checking DRC and timing, or producing a bitstream and reports.
---

# Zynq-7020 Vivado

## Environment

Vivado 2018.3 is invoked via WSL batch on this machine. The confirmed install
paths and tool presence are recorded in `docs/environment-baseline.md`; trust
that baseline unless an invalidation condition is met (then re-probe via the
environment skill). Do not restate those paths here.

## Simulation and build entry points

The canonical list of workflow entry points and which example to build is owned
by `skills/zynq7020-pipeline/SKILL.md` per the AGENTS.md fact-consistency rule.
The commands below are the concrete invocations for each example; if the
pipeline skill names a different preferred example, follow the pipeline skill.

Run xsim before building any video-path example:

- PL-only side demo:
  `scripts/sim-wsl.ps1 -Example video-pip`
- Network-video pass-through:
  `scripts/sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through`

Then build the bitstream:

- PL-only side demo:
  `scripts/build-wsl.ps1 -BoardProfile <path> -Example video-pip`
- Network-video pass-through VDMA board:
  `examples/eth-ps-pl-hdmi-pass-through/tcl/build-stage1-vdma-board-wsl.ps1`
  (this example has its own board-specific build script; do not use the
  retired `build-stage1-board-wsl.ps1` custom-reader entry point)
- Clocked LED chaser MVP:
  `scripts/build-wsl.ps1 -BoardProfile <path>` (defaults to led-chaser)
- No verified PL clock yet:
  `scripts/build-wsl.ps1 -BoardProfile <path> -Example led-static`

The WSL build scripts invoke Vivado 2018.3 in batch mode and keep generated
state under `build/`. Use `scripts/build.ps1` only to diagnose the Windows-side
Vivado installation.

## Before building

Board hard facts (FPGA part, package, speed grade, LED pins, I/O voltage,
active polarity, oscillator frequency/pin) are owned by
`docs/boards/hellofpga-smart-zynq-sl.md` per the fact-consistency rule. Do not
re-derive them here. Before building:

1. Confirm the board reference has not changed since the last successful build
   (i.e. no fact change was committed to it). If it has, re-verify the changed
   fact against the schematic or official source before building.
2. Use the existing board profile under `boards/`; do not modify the generic
   RTL for board differences.
3. Reject empty pins, non-XC7Z020 parts, and unsupported profile fields.

The build must stop on synthesis, implementation, DRC, unconstrained I/O, or
timing failure. Do not downgrade critical DRC checks to warnings.

## Simulation gates

For `video-pip`, treat the xsim markers as gates:

```text
STAGE1_TIMING_AND_PATTERN_OK
STAGE2_PIP_OK
STAGE3_EFFECT_PIPE_OK
STAGE4_BUTTON_CONTROL_OK
SIM_OK
```

For `eth-ps-pl-hdmi-pass-through`, the sim target is the AXI framebuffer line
reader; require:

```text
AXI_FRAMEBUFFER_LINE_READER_OK
SIM_OK
```

Read `references/board-profile.md` when adding a board.
