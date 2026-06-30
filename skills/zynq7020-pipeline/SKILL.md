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

Verified PetaLinux build path for the active VDMA HDMI image (2026-06-30):

```text
1. Build or rebuild examples/eth-ps-pl-hdmi-pass-through with:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1
2. Require STAGE1_VDMA_BOARD_BUILD_OK, non-negative WNS, and DRC with no errors.
3. Inspect the HDF if device-tree generation fails. The VDMA interrupts must
   terminate at processing_system7_0/IRQ_F2P. In the verified design:
   axi_vdma_0/mm2s_introut -> vdma_irq_concat/In0
   axi_vdma_0/s2mm_introut -> vdma_irq_concat/In1
   vdma_irq_concat/dout -> processing_system7_0/IRQ_F2P[15:0]
4. Use the Ubuntu 18.04 chroot at /opt/chroots/ubuntu18-petalinux2018, not
   direct Ubuntu 22.04, for PetaLinux 2018.3 full image builds.
5. Re-import the HDF, run petalinux-build, then package:
   petalinux-package --boot --fsbl images/linux/zynq_fsbl.elf --fpga <bit> --u-boot images/linux/u-boot.elf --force -o images/linux/BOOT.BIN
6. Copy BOOT.BIN and image.ub to the ZYNQBOOT FAT32 TF-card partition and
   verify hashes before booting the board.
```

Verified project-image boot/probe path (2026-06-30):

```text
1. Boot the generated project image from the TF card.
2. If no new UART output appears, send Enter on COM16; an already-booted board
   may be sitting at:
   vdma-hdmi-minimal-bionic login:
3. Log in as root/root for the generated PetaLinux image.
4. Configure direct-link Ethernet when DHCP is absent:
   ifconfig eth0 192.168.1.10 netmask 255.255.255.0 up
5. Clear stale PC ARP and ping 192.168.1.10 from the PC.
6. Require 4/4 ping before continuing video work.
7. Confirm VDMA probe:
   dmesg | grep -i vdma
   readlink /sys/bus/platform/devices/43000000.dma/driver
8. Confirm whether Linux exposes a display node:
   ls -l /dev/dri /dev/fb* 2>&1
```

Current result for the generated image:

```text
Boot/probe PASSED: Linux boots, eth0 links at 1000/Full, PC ping is 4/4 with
0% loss, and 43000000.dma binds to xilinx-vdma.

Display output follow-up (2026-06-30):
/dev/dri/card0 now exists after enabling CONFIG_DRM_XLNX and
CONFIG_DRM_XLNX_PL_DISP and adding an xlnx,pl-disp DT node. HDMI capture still
shows stable 800x600 color bars. The path is not yet Linux-controllable:
/dev/fb* is absent, card0 has no status/modes/enabled connector files, and
dmesg reports "[drm] Cannot find any crtc or sizes".
```

Verified PetaLinux PL-display overlay path (2026-06-30):

```text
1. Apply the repository overlay to the WSL PetaLinux project:
   rtk wsl -d Ubuntu-22.04 -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/apply-overlay.sh /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic
2. If kernel config fragments do not refresh, force kernel config metadata:
   rtk wsl -d Ubuntu-22.04 -u root -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/run-command-in-chroot.sh /opt/chroots/ubuntu18-petalinux2018 /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic bash -lc 'source /opt/petalinux-v2018.3/components/yocto/source/layers/core/oe-init-build-env build >/tmp/oe-init.log && bitbake virtual/kernel -c kernel_configme -f'
3. Build in the verified Ubuntu 18.04 chroot:
   rtk wsl -d Ubuntu-22.04 -u root -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/build-in-chroot.sh /opt/chroots/ubuntu18-petalinux2018 /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic /mnt/e/main/fpga-hdml/build/hdmi-linux-display-stack
4. Verify generated artifacts before board update:
   - kernel build .config has CONFIG_DRM_XLNX=y and CONFIG_DRM_XLNX_PL_DISP=y
   - decompiled system.dtb contains drm-pl-disp-drv compatible "xlnx,pl-disp"
   - image.ub hash is recorded in the cycle report
5. If the TF card is in the board, update image.ub without removing it:
   - serve build/hdmi-linux-display-stack/image.ub from the PC on 192.168.1.2
   - board wget downloads to /tmp/image.ub.new
   - board verifies sha256, backs up /run/media/mmcblk0p1/image.ub, copies the
     new image, syncs, and reboots
6. After reboot, require:
   - Linux kernel build number changed
   - /dev/dri/card0 exists
   - dmesg shows xilinx-vdma probe and xlnx-pl-disp probe
   - current known blocker is recorded if no connector/modes exist
```

Do not resume hand-written baremetal RGMII bridge work. The Linux route is
confirmed; future network-video work builds on Linux sockets, not baremetal lwIP.
