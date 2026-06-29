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

For the active network-video path, the accepted direction is confirmed by
hardware evidence (2026-06-29):

```text
PC UDP RGB888 -> Linux userspace socket receiver -> DDR framebuffer
-> VDMA MM2S -> HDMI
```

Route gate result: PASSED.

```text
The official Smart_ZYNQ_SP2_LINUX_ALL_TEST image boots from a FAT32 TF card.
Linux macb driver brings up eth0 at 1000/Full with RX errors=0. PC ping
192.168.1.10 = 4/4, 0% loss. The hand-written baremetal RGMII bridge is
retired as a dead end; its RX failure was the bridge implementation, not the
physical layer. See docs/reports/tf-card-linux-ping-2026-06-29.md.
```

Verified Linux boot path (for reference when the board needs to be brought up
for network-video work):

```text
1. Format TF card: 1GB FAT32 partition (Windows does not offer FAT32 above 32GB).
2. Copy BOOT.BIN + image.ub from Smart_ZYNQ_SP2_LINUX_ALL_TEST to the partition.
3. Set board DIP switch to SD boot, insert card, press POR RST.
4. UART (COM16, CH340, 115200) prints U-Boot then Linux boot.
5. Login as root (no password) via UART.
6. ifconfig eth0 192.168.1.10 netmask 255.255.255.0 up  (no DHCP on direct link).
7. Clear stale PC ARP (arp -d 192.168.1.10) — Linux MAC differs from baremetal.
8. ping 192.168.1.10 from PC.
```

Do not resume hand-written baremetal RGMII bridge work. The Linux route is
confirmed; future network-video work builds on Linux sockets, not baremetal lwIP.
