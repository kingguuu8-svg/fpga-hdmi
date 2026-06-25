---
name: zynq7020-pipeline
description: Orchestrate the repository-local XC7Z020 end-to-end MVP workflow using project skills. Use for full pipeline requests spanning environment validation, board-profile selection, Vivado RTL build, timing and DRC gates, JTAG programming, connected-board verification, and reproducible build reports.
---

# Zynq-7020 Pipeline

Run the shortest safe path in this order:

1. Load `../zynq7020-environment/SKILL.md` and probe tools, USB, UART, and JTAG.
2. Identify the exact carrier board and create a verified profile under
   `boards/`. Stop rather than guessing pins.
3. Load `../zynq7020-vivado/SKILL.md` and build the shortest verified example:
   `examples/led-static` when no board clock is verified, `examples/led-chaser`
   after clock and LED constraints are verified, or `examples/video-pip` when
   the HDMI pins are schematic-backed and the user asks for the video pipeline.
4. Require clean DRC and non-negative setup slack.
5. Load `../zynq7020-hardware/SKILL.md`, select the working JTAG backend, and
   program SRAM.
6. Confirm the LED sequence physically and preserve all reports.

Use `scripts/run-mvp.ps1 -BoardProfile <path> -Backend auto` after the board
profile and JTAG driver are ready. Pass `-Example led-static` only when the
board profile has no verified clock yet.

For video stage 1/2, run xsim first and require both stage markers before
building or programming:

```text
STAGE1_TIMING_AND_PATTERN_OK
STAGE2_PIP_OK
STAGE3_EFFECT_PIPE_OK
STAGE4_BUTTON_CONTROL_OK
SIM_OK
```

Do not add PS software, FSBL, U-Boot, or Linux until this PL-only loop passes.
Those stages are the next incremental milestone, not part of the first MVP.
