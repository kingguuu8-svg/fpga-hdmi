---
name: zynq7020-pipeline
description: Orchestrate the repository-local XC7Z020 end-to-end MVP workflow using project skills. Use for full pipeline requests spanning environment validation, board-profile selection, Vivado RTL build, timing and DRC gates, JTAG programming, connected-board verification, and reproducible build reports.
---

# Zynq-7020 Pipeline

Run the shortest safe path in this order:

1. Read `docs/environment-baseline.md`. If it exists and none of its
   invalidation conditions are met, trust the baseline and skip environment
   probing. Otherwise load `../zynq7020-environment/SKILL.md` and probe tools,
   USB, UART, and JTAG; after a successful probe, update the baseline.
2. Identify the exact carrier board and create a verified profile under
   `boards/`. Stop rather than guessing pins.
3. Load `../zynq7020-vivado/SKILL.md` and build the shortest verified example:
   `examples/led-static` when no board clock is verified, `examples/led-chaser`
   after clock and LED constraints are verified, `examples/video-pip` only for
   the PL-only side demo, or `examples/eth-ps-pl-hdmi-pass-through` for the
   network-video pass-through path.
4. Require clean DRC and non-negative setup slack.
5. Load `../zynq7020-hardware/SKILL.md`, select the working JTAG backend, and
   program SRAM.
6. Confirm the LED sequence physically and preserve all reports.

Use `scripts/run-mvp.ps1 -BoardProfile <path> -Backend auto` after the board
profile and JTAG driver are ready. Pass `-Example led-static` only when the
board profile has no verified clock yet.

For the PL-only video side demo, run xsim first and require all relevant stage
markers before building or programming:

```text
STAGE1_TIMING_AND_PATTERN_OK
STAGE2_PIP_OK
STAGE3_EFFECT_PIPE_OK
STAGE4_BUTTON_CONTROL_OK
SIM_OK
```

For the active network-video path, the accepted direction is not PL-only:

```text
PC UDP RGB888 -> PS/Linux or PS fallback receiver -> DDR framebuffer
-> VDMA MM2S -> HDMI
```

Current route gate:

```text
No TF card is available, so the network-video path is paused. When a TF card
arrives, follow docs/reports/tf-card-linux-resume-2026-06-26.md and boot the
official Linux all-test image to verify Ethernet ping before more baremetal
RGMII bridge work.
```

Do not continue tuning the hand-written baremetal RGMII bridge unless the
Linux route gate fails and the failure evidence points back to PHY/RGMII.
