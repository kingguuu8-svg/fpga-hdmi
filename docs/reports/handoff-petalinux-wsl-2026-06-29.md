# Handoff: PetaLinux on WSL for Smart ZYNQ SL

Date: 2026-06-29
From: previous session (context running low)
To: Codex / next agent

## Read this first

This is a handoff document, not a cycle report. The previous session ran out of
context. Read it fully before starting work. Also read:

- `AGENTS.md` — project rules, especially fact-consistency and skill-dynamic-optimization
- `docs/current-cycle.md` — current cycle state (no active cycle; route gate passed)
- `docs/environment-baseline.md` — confirmed environment facts
- `docs/reports/tf-card-linux-ping-2026-06-29.md` — route gate result (Linux ping works)
- `docs/project-roadmap.md` — MVP is 800x600 RGB888 VDMA pass-through

## Current verified state

```text
Board: HelloFPGA Smart ZYNQ SL, xc7z020clg484-1
TF card: 64GB SanDisk, NOW PARTITIONED for PetaLinux dual-boot:
         - partition 1: D: ZYNQBOOT FAT32 1GB (boot: BOOT.BIN + image.ub)
         - partition 2: F: rootfs 57.2GB (currently NTFS, will be reformatted
           ext4 by PetaLinux burn script or WSL mkfs.ext4 when rootfs is ready)
         The previous single-FAT32 all-test image was wiped by repartitioning.
         Original all-test zip is still at:
         C:/Users/中二哲人/Downloads/Smart_ZYNQ_SP2_LINUX_ALL_TEST_20240906.zip
Ethernet: confirmed working under Linux (macb driver, 1000/Full, ping 0% loss)
HDMI/VDMA under Linux: NOT working — the all-test image has no VDMA/HDMI driver,
         only a 240x240 SPI LCD framebuffer (fb_st7789v). See probe log:
         build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_linux_probe.log
Vivado: 2018.3 at E:\Xilinx\Vivado\2018.3 (Windows + WSL batch)
SDK/XSCT: 2018.3 at E:\Xilinx\SDK\2018.3
WSL: Ubuntu 22.04, root, 908GB free, NO PetaLinux toolchain yet
WSL proxy: http://172.27.96.1:7890 (Clash allow-lan enabled, verified working)
VMware: user reports it is incomplete; prefer WSL route
```

## User's goal

Build a complete PetaLinux system on the 64GB TF card that:
1. Boots Linux from SD card on the connected board.
2. Uses the full 64GB card capacity (not a tiny initramfs).
3. Includes VDMA + HDMI driver support so the video pass-through path works
   under Linux (this is what the current all-test image lacks).
4. Once built, the user does not want to keep re-tinkering with the image.

The user explicitly chose PetaLinux over Xillinux/PYNQ because PetaLinux is the
FPGA-standard toolchain that syncs PL hardware changes to the Linux device tree
automatically. The project will modify PL hardware (video effects IP), so a
frozen-image distribution is not suitable long-term.

## Why PetaLinux specifically

Zynq = PS (ARM) + PL (FPGA). Linux runs on PS but must know about PL hardware
(VDMA, HDMI controller, custom AXI IP) via device tree + kernel drivers.
PetaLinux reads the Vivado HDF export and auto-generates the device tree and
driver config. When PL hardware changes, PetaLinux re-syncs. Frozen images
(Xillinux/PYNQ/all-test) cannot do this — their device tree is baked.

## Key constraint

PetaLinux only runs on Linux (Ubuntu officially). The user's machine is Windows.
WSL is available but does NOT have PetaLinux installed. Installing PetaLinux
requires:
- ~30GB disk space
- Download from AMD/Xilinx (needs login, large file)
- Compatible with the Vivado version: PetaLinux 2018.3 matches Vivado 2018.3
- Source the settings script before use

The user has Clash Verge proxy running (needed for Xilinx downloads from China).

## Official PetaLinux tutorial for this board (10 chapters)

These are the reference steps. Follow them adapted to WSL instead of VMware:

1. Ch1 - Vivado hardware project: http://www.hellofpga.com/index.php/2025/02/23/smart_zynq_petalinux_01/
2. Ch2 - PetaLinux project creation & compilation (TF boot): http://www.hellofpga.com/index.php/2025/02/23/smart_zynq_building_petalinux/
3. Ch3 - Creating bootable SD card (boot + rootfs partitions): http://www.hellofpga.com/index.php/2025/02/23/zynq_creating_sd_card/
4. Ch4 - Boot verification: http://www.hellofpga.com/index.php/2025/02/25/petalinux_boot_test/
5. Ch5 - SSH remote login: http://www.hellofpga.com/index.php/2025/02/23/zynq-petalinux-ssh/
6. Ch6 - SCP file transfer: http://www.hellofpga.com/index.php/2025/02/23/petalinux_scp_test/
7. Ch7 - GPIO: http://www.hellofpga.com/index.php/2025/02/28/petalinux_sys_gpio/
8. Ch8 - GPIO app: http://www.hellofpga.com/index.php/2023/04/30/petalinux_gpio_app-2/
9. Ch10 - QSPI boot: http://www.hellofpga.com/index.php/2023/04/28/zynq-linux_qspi_flash_uart-2/

PetaLinux install tutorial: http://www.hellofpga.com/index.php/2022/11/28/petalinux/

## What the next agent should do

This is a multi-day effort. Break it into cycles per AGENTS.md rules. Suggested
cycle sequence:

### Cycle 1: PetaLinux environment setup in WSL

```text
Objective: install PetaLinux 2018.3 toolchain in WSL so petalinux commands work
Scope: download PetaLinux 2018.3 installer (use Clash proxy if needed for
  Xilinx site access), install into WSL, source settings, verify petalinux
  --version runs
Verification: petalinux --version prints 2018.3 in WSL
Board action: none
```

### Cycle 2: PetaLinux project from existing hardware

```text
Objective: create a PetaLinux project from the existing VDMA HDMI hardware
  design (the one that passed official VDMA color-bar test), configure for
  SD boot, and build BOOT.BIN + image.ub
Scope: use the Vivado HDF from the VDMA HDMI BD as hardware input; configure
  PetaLinux for SD boot with rootfs on a separate partition; build
Verification: build completes, produces BOOT.BIN + image.ub + rootfs
Board action: none yet (build only)
```

### Cycle 3: SD card with full-capacity rootfs

```text
Objective: partition the 64GB card with a FAT32 boot partition and an ext4
  rootfs partition using the remaining space; write BOOT.BIN + image.ub to
  boot partition; write rootfs to the ext4 partition; boot and verify
Scope: repartition card, write images, boot, verify Linux comes up with full
  rootfs mounted and networking works
Verification: board boots Linux, df shows rootfs using most of the 64GB,
  eth0 link up, ping works
Board action: boot from SD, no flash writes
```

### Cycle 4: VDMA/HDMI verification under Linux

```text
Objective: confirm VDMA + HDMI output works under PetaLinux (write a frame to
  the framebuffer, capture on HDMI, verify)
Scope: locate the VDMA/framebuffer device under Linux, write a test pattern,
  HDMI capture on PC, compare
Verification: HDMI capture shows the test pattern
Board action: boot from SD, HDMI output
```

## Important rules to follow

- Open a cycle in docs/current-cycle.md before each step, using the template
  with the two risk fields (Highest-risk assumption / Cheapest alternative).
- One commit per cycle. Use `cycle: <result>` commit messages.
- Update docs/environment-baseline.md if any environment fact changes.
- Update docs/boards/lookup-log.md for any board web page / tutorial inspected.
- Do not commit PetaLinux build output or the 30GB toolchain. Commit only
  configs, scripts, and concise reports.
- The hand-web tutorials are in Chinese; extract facts into lookup-log, do not
  copy whole articles.
- PetaLinux 2018.3 must match Vivado 2018.3 — do not mix versions.
- Clash Verge proxy is running on the host; WSL may need proxy env vars set
  (http_proxy / https_proxy) to reach Xilinx download servers from China.

## Files already in place that help

- `examples/eth-ps-pl-hdmi-pass-through/tcl/create_ps_emio_vdma_hdmi_bd.tcl` —
  the VDMA HDMI BD creation script (uses official downloaded reference)
- `docs/boards/hellofpga-smart-zynq-sl.md` — board pin facts, VDMA HDMI facts
- `docs/boards/lookup-log.md` — all official reference projects logged
- `docs/reports/tf-card-linux-ping-2026-06-29.md` — proof Linux networking works
- `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_linux_probe.log` —
  proof the all-test image lacks VDMA/HDMI

## What NOT to do

- Do not build PetaLinux on Windows directly — it is Linux-only.
- Do not use a newer PetaLinux version than 2018.3 — must match Vivado.
- Do not skip the route-gate evidence — Ethernet is proven under Linux; the
  remaining unknown is HDMI/VDMA under Linux, which is why PetaLinux is needed.
- Do not format the card as a single FAT32 — PetaLinux SD boot uses a FAT32
  boot partition + ext4 rootfs partition (Ch3).
- Do not commit the PetaLinux installer or build artifacts to git.
