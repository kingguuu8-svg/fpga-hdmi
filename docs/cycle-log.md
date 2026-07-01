# Cycle Log

This file records completed project cycles. Keep entries short and auditable.

## Entry Template

```text
Date:
Cycle ID:
Commit:
Objective:
Changed scope:
Verification:
Board action:
Evidence:
Result:
Residual risks:
```

## 2026-06-25 - management-bootstrap

Commit: 593c405 (`docs: establish project management workflow`)

Objective:

Establish the project-management workflow before opening further hardware
implementation cycles.

Changed scope:

- Registered project-management documents in `AGENTS.md`.
- Added the current-cycle file.
- Added the cycle ledger.
- Added the committed report directory policy.

Verification:

- Documentation-only cycle.
- No simulation required.
- No board programming required.

Board action:

- Not run; this cycle does not change hardware behavior.

Evidence:

- `AGENTS.md`
- `docs/current-cycle.md`
- `docs/cycle-log.md`
- `docs/reports/README.md`

Result:

- Project-management workflow is defined.

Residual risks:

- Existing source directories are still untracked because this cycle only
  established project-management documents.

## 2026-06-25 - project-opening-baseline

Commit: this commit (`cycle: establish project opening baseline`)

Objective:

Reach the repository state required to start formal implementation cycles.

Changed scope:

- Added the project-start readiness standard.
- Registered the readiness standard in `AGENTS.md`.
- Added current boards, examples, skills, and tools as the initial source
  baseline.
- Ignored Python bytecode caches.

Verification:

- Project-management cycle.
- File audit confirms source directories are ready to track.
- No simulation required.
- No board programming required.

Board action:

- Not run; this cycle does not change hardware behavior.

Evidence:

- `docs/project-start-standard.md`
- `docs/current-cycle.md`
- `docs/cycle-log.md`
- Git status after commit

Result:

- Project is ready to open the first formal implementation cycle after final
  clean git status verification.

Residual risks:

- No remote repository is configured yet.

## 2026-06-26 - baseline-checkpoint

Commit: this commit (`cycle: checkpoint eth pass-through work surface into git`)

Objective:

Commit the completed eth-ps-pl-hdmi-pass-through work surface and supporting
tooling into git so the repository returns to the clean baseline required by
`docs/project-start-standard.md`, and so the route-pivot documents committed
earlier the same day no longer dangle-reference untracked files.

Changed scope:

- Added `examples/eth-ps-pl-hdmi-pass-through/` (RTL, Tcl, XDC, sim testbench,
  README) covering both the active VDMA/RGB888/800x600 path and the retired
  custom-reader/RGB565/640x480 path (kept for historical traceability).
- Added `software/eth_pass_through/` (protocol, receiver, SDK app, host unit
  test, build scripts).
- Added `docs/protocols/video-udp.md`, `docs/boards/lookup-log.md`,
  `docs/reports/eth-ps-pl-hdmi-pass-through.md`, and
  `docs/reports/third-party-review-2026-06-26.md`.
- Added 10 `tools/*.{ps1,py,tcl}` helper scripts (UART capture, UDP send/probe,
  VDMA capture, bit+ELF program, DAP recovery, HDF probe).
- Modified `.gitignore` (ignore `/NA/`), `skills/zynq7020-vivado/scripts/sim.tcl`
  (add eth-ps-pl sim target), `docs/boards/hellofpga-smart-zynq-sl.md`
  (promoted board facts), and `docs/current-cycle.md` (new baseline-checkpoint
  cycle using the new risk-field template; prior eth cycle moved to paused).

Verification:

- Source-checkpoint cycle; no simulation or board programming required.
- Pre-stage inspection confirmed: all untracked items are source/docs/scripts,
  no build products; `tools/downloads/`, `NA/`, `build/` remain gitignored and
  were not staged; every path referenced by README/roadmap/skill resolves to a
  git-tracked object after this commit.

Board action:

- Not run; this cycle does not change hardware behavior.

Evidence:

- The commit itself and this log entry.
- `git status --short` clean for all in-scope files after commit.

Result:

- Completed eth-ps-pl-hdmi-pass-through work surface is durably in git.
- Route-pivot documents (commit `bca631f`) no longer dangle-reference
  untracked files.
- Repository meets the clean-baseline requirement of
  `docs/project-start-standard.md` for the in-scope files.

Residual risks:

- The retired custom-reader RTL/Tcl (`eth_ps_pl_hdmi_board_top.v`,
  `axi_framebuffer_line_reader.v`, `build_stage1_board.tcl`,
  `create_ps_emio_hp0_bd.tcl`) is committed as-is. README marks the
  `build-stage1-board-wsl.ps1` entry point as intentionally failing. A later
  cleanup cycle should delete or archive these to prevent accidental reuse.
- Build reproducibility still depends on gitignored `tools/downloads/` (the
  official HelloFPGA BD Tcl and rgb2dvi IP repo). A clean clone cannot build
  until this dependency is either committed or documented in the README.
- Historical note: at this point the hardware experiment cycle was still
  blocked by TF-card availability. It was resolved by the 2026-06-29
  `tf-card-linux-ping-route-gate` entry below.

## 2026-06-26 - skill-env-baseline

Commit: this commit (`cycle: add environment baseline, make skills event-triggered`)

Objective:

Stop the project skills from re-probing a known-stable environment on every
cycle, and close the skill gaps left by the earlier route pivot: the vivado
skill was missing the eth-ps-pl build/sim entry point and was restating board
facts that the fact-consistency rule now assigns to the board reference.

Changed scope:

- Added `docs/environment-baseline.md`: a git-tracked, one-time-confirmed
  record of this machine's environment facts (Vivado 2018.3 paths, JTAG
  adapter, device, board, UART, HDMI capture, Ethernet IP) with explicit
  invalidation conditions. It is the fact owner for "current environment
  facts" under the AGENTS.md fact-consistency rule.
- Edited `skills/zynq7020-environment/SKILL.md`: added a "When to probe"
  section that skips probing when the baseline is valid and only re-probes on
  invalidation events.
- Edited `skills/zynq7020-pipeline/SKILL.md`: step 1 now reads the baseline and
  skips probing when it is valid, instead of mandating a probe every cycle.
- Edited `skills/zynq7020-vivado/SKILL.md`: build-prep board-fact verification
  now references `docs/boards/hellofpga-smart-zynq-sl.md` instead of restating
  the facts; added the eth-ps-pl sim and VDMA build commands and its sim
  marker (`AXI_FRAMEBUFFER_LINE_READER_OK`); marked the retired custom-reader
  build entry point as not to be used.
- Updated `docs/current-cycle.md`: new skill-env-baseline active cycle;
  baseline-checkpoint moved to a Recently Closed Cycle section.

Verification:

- Skill-rule cycle; no simulation or board programming required.
- Dry-checked every command path named in the edited skills against the file
  tree: all 10 paths resolve to tracked files.
- Cross-checked the vivado skill's eth sim marker against
  `skills/zynq7020-vivado/scripts/sim.tcl:27` — both say
  `AXI_FRAMEBUFFER_LINE_READER_OK`.
- Cross-checked the baseline's Vivado/SDK paths against
  `probe-environment.ps1` defaults — both are `E:\Xilinx\Vivado\2018.3` and
  `E:\Xilinx\SDK\2018.3`.
- Cross-checked the pipeline skill's tf-card report reference resolves to a
  tracked file.

Board action:

- Not run; this cycle does not change hardware behavior. The baseline it
  records was already confirmed by prior probe runs.

Evidence:

- The commit itself and this log entry.
- `git status --short` clean for all in-scope files after commit.

Result:

- Skills no longer mandate per-cycle environment probing on a stable machine;
  probing is now event-triggered by baseline invalidation.
- vivado skill no longer violates the fact-consistency rule by restating board
  facts; it references the board reference.
- vivado skill now has the eth-ps-pl sim/build entry point that the route
  pivot required.

Residual risks:

- The baseline is event-triggered, not time-triggered. Silent environment drift
  that never touches an active JTAG/UART/Ethernet operation will not be caught
  until the affected interface is next used. This is accepted: the drift
  surfaces as a probe contradiction at that time.
- The vivado skill still lists concrete command invocations alongside
  referencing the pipeline skill as the entry-point owner. If the two ever
  diverge, the pipeline skill wins per the fact-consistency rule; a future
  cleanup could make the vivado skill reference-only.
- The `examples/eth-ps-pl-hdmi-pass-through` sim target tests the retired
  AXI framebuffer line reader, not the active VDMA path. The sim marker is
  accurate for what sim.tcl actually runs, but it is not proof of the active
  HDMI output path.

## 2026-06-29 - tf-card-linux-ping-route-gate

Commit: this commit (`cycle: TF-card Linux ping route gate passed, retire baremetal RGMII bridge`)

Objective:

Run the route-deciding experiment from `docs/reports/tf-card-linux-resume-2026-06-26.md`:
boot the official vendor Linux image from TF card and ping the board over the
PL-side RTL8211E Ethernet path, to decide whether the project continues on a
Linux/socket route or falls back to baremetal official-IP debugging.

Changed scope:

- Prepared TF card: 1GB FAT32 partition, copied BOOT.BIN + image.ub from
  `Smart_ZYNQ_SP2_LINUX_ALL_TEST_20240906.zip`.
- Booted official Linux on the connected board from SD; logged full U-Boot +
  kernel boot via UART (COM16).
- Logged in as root via UART, set static IP `192.168.1.10/24` on eth0 (no DHCP
  on direct link).
- Pinged the board from the PC: 4/4 received, 0% loss, <1ms.
- Updated `docs/environment-baseline.md`: UART COM identity corrected (COM16 =
  CH340 board UART, COM13 = FTDI JTAG serial channel), Ethernet facts split
  into baremetal and Linux rows with distinct MACs, confirmed date 2026-06-29.
- Updated `docs/boards/hellofpga-smart-zynq-sl.md`: added Official Linux network
  row to Ethernet PHY facts.
- Updated `docs/boards/lookup-log.md`: added 2026-06-29 Official Linux Network
  Ping Route Gate entry.
- Updated `docs/current-cycle.md`: route gate marked PASSED, paused cycle
  resolved, hand-written baremetal RGMII bridge formally retired, next cycle
  direction set to Linux/socket video receiver.
- Updated `skills/zynq7020-pipeline/SKILL.md`: route gate marked passed, Linux
  boot path recorded as a verified entry point per the skill-dynamic-optimization
  rule, baremetal bridge work forbidden.
- Added `docs/reports/tf-card-linux-ping-2026-06-29.md`: full experiment report.

Verification:

- Board action: booted official Linux from TF card, programmed no flash (SD
  only, no QSPI/NAND/eMMC writes).
- UART boot log (498 lines) confirms U-Boot → kernel → userspace → eth0 link
  up at 1000/Full with RX errors=0.
- PC ping result: 4/4 received, 0% loss, <1ms.
- All evidence logs under `build/` (gitignored); concise facts promoted to
  tracked docs.

Board action:

- Booted official Linux from TF card. No flash written. Static IP set via UART
  after boot (runtime only, not persisted to the image).

Evidence:

- `docs/reports/tf-card-linux-ping-2026-06-29.md`
- `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_linux_boot.log`
- `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_linux_setip.log`

Result:

- Route gate PASSED (Outcome A). The project proceeds on the Linux/socket
  route. The hand-written baremetal RGMII bridge is retired as a dead end:
  the same physical path that fails under the hand-written bridge works
  perfectly under Linux + official macb driver.
- The pipeline skill now records the verified Linux boot path as a reference
  entry point, satisfying the skill-dynamic-optimization rule.

Residual risks:

- HDMI output and VDMA framebuffer access under Linux are not yet verified.
  The official Linux image is a generic all-test image, not a video-pipeline
  image; the next cycle must confirm VDMA/HDMI works from Linux userspace.
- The Linux image uses DHCP by default; on a direct link without a DHCP
  server, a static IP must be set manually after each boot. A production setup
  needs either a DHCP server on the PC or a static IP baked into the rootfs.
- The Linux image MAC differs from the baremetal MAC; PC ARP must be cleared
  when switching between images.

## 2026-06-29 - petalinux-wsl-install-2018.3

Commit: this commit (`cycle: install PetaLinux 2018.3 in WSL`)

Objective:

Install PetaLinux 2018.3 in WSL Ubuntu 22.04 so the project can create and
build a Linux/socket route image that matches the existing Vivado/SDK 2018.3
toolchain.

Changed scope:

- Used the downloaded
  `C:/Users/中二哲人/Downloads/petalinux-v2018.3-final-installer.run`
  installer.
- Created Linux user `petalinux`; the installer refuses to run as root.
- Installed required WSL packages and i386 support for the 2018.3 toolchain.
- Added a local `python` compatibility package with `equivs` so the legacy
  installer sees `python 2.7.18` on Ubuntu 22.04.
- Generated `en_US.UTF-8` locale for the Yocto SDK installers.
- Reconfigured `/bin/sh` to bash, as recommended by PetaLinux.
- Installed PetaLinux to `/opt/petalinux-v2018.3`.
- Updated `docs/current-cycle.md`, `docs/environment-baseline.md`,
  `docs/project-roadmap.md`, `README.md`, and the install report.

Verification:

- Sourced `/opt/petalinux-v2018.3/settings.sh` as user `petalinux` from a clean
  environment.
- Confirmed `PETALINUX=/opt/petalinux-v2018.3` and `PETALINUX_VER=2018.3`.
- Confirmed these commands resolve:
  `petalinux-build`, `petalinux-create`, `petalinux-config`,
  `petalinux-package`, and `petalinux-util`.
- Ran `petalinux-create --help` successfully.

Board action:

- Not run; this cycle changes host tooling only.

Evidence:

- `docs/reports/petalinux-wsl-install-2018.3-2026-06-29.md`
- `/home/petalinux/petalinux_installation_log` inside WSL

Result:

- PetaLinux 2018.3 host tooling is installed and command-visible in WSL.
- The earlier blocked cycle is closed.
- The project can open the next cycle: create/build a minimal PetaLinux project
  from the VDMA HDMI hardware design.

Residual risks:

- Ubuntu 22.04 is not an officially supported host for PetaLinux 2018.3; the
  environment still prints an unsupported-OS warning.
- No TFTP server is installed. This is accepted because the next route uses
  TF-card boot first.
- The next cycle must still prove that a project-built PetaLinux image preserves
  the known-good Ethernet path and exposes a usable VDMA/HDMI path.

## 2026-06-30 - petalinux-vdma-hdmi-minimal-project

Commit: this commit (`cycle: build PetaLinux VDMA HDMI TF image`)

Objective:

Create and build a minimal PetaLinux 2018.3 project from the VDMA HDMI hardware
description, package boot artifacts, and write them to the TF-card boot
partition.

Changed scope:

- Fixed the VDMA HDMI Vivado BD generator so `axi_vdma_0/mm2s_introut` and
  `axi_vdma_0/s2mm_introut` connect through `vdma_irq_concat` to
  `processing_system7_0/IRQ_F2P`.
- Added a hard Tcl check that fails the Vivado build if PS `IRQ_F2P` is not
  exposed after enabling fabric interrupts.
- Recorded the Ubuntu 18.04 chroot as the preferred PetaLinux 2018.3 build
  host under WSL.
- Added the cycle report for the PetaLinux VDMA HDMI minimal project.
- Updated the current-cycle file to close this cycle and point the next cycle
  at board boot verification.

Verification:

- Vivado batch rebuild passed for `eth_ps_vdma_hdmi_stage1_board`.
- Timing passed with WNS = 0.347 ns.
- Post-route DRC reported 0 errors and 0 critical warnings.
- HDF inspection confirmed `PCW_IRQ_F2P_INTR=1`,
  `C_NUM_F2P_INTR_INPUTS=16`, and VDMA IRQ connections to PS `IRQ_F2P`.
- PetaLinux `petalinux-build` succeeded in the Ubuntu 18.04 chroot:
  3065 tasks attempted, all succeeded.
- `petalinux-package --boot` generated `BOOT.BIN`.
- SHA256 hashes matched between PetaLinux output, repo artifact snapshot, and
  `D:\` TF-card boot partition.
- Simulation was not run; this cycle used Vivado BD validation, implementation,
  timing/DRC, HDF inspection, and PetaLinux device-tree generation as the
  automated verification gates for the interrupt-topology fix.

Board action:

- TF-card file write only: copied `BOOT.BIN` and `image.ub` to `D:\`
  (`ZYNQBOOT`, FAT32, removable). No board boot, SRAM programming, QSPI, NAND,
  or eMMC write in this cycle.

Evidence:

- `docs/reports/petalinux-vdma-hdmi-minimal-project.md`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/stage1_vdma_board_console.log`
- `build/petalinux/vdma-hdmi-minimal-bionic/images/BOOT.BIN`
- `build/petalinux/vdma-hdmi-minimal-bionic/images/image.ub`
- `D:\BOOT.BIN`
- `D:\image.ub`

Result:

- PetaLinux VDMA HDMI boot artifacts are built and written to the TF card.
- The original PetaLinux device-tree failure is resolved at the correct layer:
  the hardware description now exposes VDMA interrupts to the PS interrupt
  controller.

Residual risks:

- The generated TF-card image has not yet been booted on the board.
- Ethernet and HDMI behavior under this project-built image remain unverified
  until the next hardware cycle.
- The PetaLinux project lives under the WSL ext4 path
  `/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic`; the
  repo only keeps source changes and concise evidence, not the full generated
  Yocto project.

## 2026-06-30 - vdma-boot-probe-verify

Commit: this commit (`cycle: verify project image boot and VDMA probe`)

Objective:

Boot the generated project TF-card image and verify the shortest Linux runtime
gate: UART login, Ethernet ping, VDMA driver binding, and display device-node
status.

Changed scope:

- Opened and closed `vdma-boot-probe-verify` in `docs/current-cycle.md`.
- Added `docs/reports/vdma-boot-probe-verify.md`.
- Added `tools/uart_run_commands.ps1`, a reusable UART command runner for
  hardware cycles that need to log in and collect shell evidence.
- Updated the pipeline skill with the verified project-image boot/probe path.

Verification:

- UART COM16 is still the CH340 board UART.
- Project image reached PetaLinux userspace and login prompt.
- Login succeeded with `root/root`.
- Kernel identity:
  `Linux vdma-hdmi-minimal-bionic 4.14.0-xilinx-v2018.3`.
- Runtime Ethernet configuration:
  `eth0 192.168.1.10/24`, MAC `00:0A:35:00:1E:53`, link `1000/Full`.
- PC ping result: 4/4 received, 0% loss.
- VDMA probe evidence:
  `xilinx-vdma 43000000.dma: Xilinx AXI VDMA Engine Driver Probed!!`.
- sysfs binding evidence:
  `/sys/bus/platform/devices/43000000.dma/driver` points to
  `bus/platform/drivers/xilinx-vdma`.
- VDMA compatible strings:
  `xlnx,axi-vdma-6.3`, `xlnx,axi-vdma-1.00.a`.
- Display-device evidence:
  `/dev/dri` and `/dev/fb*` do not exist.

Board action:

- Booted generated image from TF card. No JTAG programming, SRAM programming,
  QSPI, NAND, eMMC, or other nonvolatile board storage writes.

Evidence:

- `docs/reports/vdma-boot-probe-verify.md`
- `build/vdma-boot-probe-verify/uart_newline_probe.log`
- `build/vdma-boot-probe-verify/uart_probe_session_root_root.log`
- `build/vdma-boot-probe-verify/uart_sysfs_vdma_probe_session.log`

Result:

- Boot/probe gate PASSED. The project-built TF-card image boots, Ethernet
  works, and VDMA probes under Linux.
- HDMI/display output remains unresolved. The next cycle should patch/repack
  the Linux device tree or display stack for the rgb2dvi / v_axi4s_vid_out /
  VTC chain, rather than revisiting boot, Ethernet, or VDMA interrupt wiring.

Residual risks:

- A full cold-boot UART log was not captured because the board was already at
  the login prompt when probed. Userspace login and runtime kernel evidence were
  captured, so this does not block the boot/probe gate.
- Static IP is runtime-only and must be set again after reboot until a later
  image bakes in networking configuration.
- No HDMI output device exists yet from Linux's perspective; this is the next
  cycle's target.

## 2026-06-30 - hdmi-linux-display-stack

Commit: this commit (`cycle: expose PL display DRM card`)

Objective:

Make the project PetaLinux image expose a Linux-managed HDMI output path,
preferably `/dev/dri/card0` and secondarily `/dev/fb0`, without using
userspace `/dev/mem` MMIO as the main route.

Changed scope:

- Added a reproducible PetaLinux meta-user overlay under
  `software/petalinux/hdmi-linux-display-stack/`.
- Enabled `CONFIG_DRM_XLNX=y` and `CONFIG_DRM_XLNX_PL_DISP=y`.
- Added a `xlnx,pl-disp` DT node bound to VDMA MM2S channel 0 with `RG24`
  format.
- Added chroot helper scripts for the verified PetaLinux 2018.3 Ubuntu 18.04
  build path and for one-off bitbake/PetaLinux commands.
- Updated the current-cycle report and pipeline skill with the verified
  overlay/build/board-update path.

Verification:

- Inspected kernel source and bindings for `xlnx,pl-disp`, `xlnx,drm`, and VTC.
- Proved `bitbake -e virtual/kernel` includes `file://user.cfg`.
- Forced `do_kernel_configme`; verified the kernel build `.config` has
  `CONFIG_DRM_XLNX=y` and `CONFIG_DRM_XLNX_PL_DISP=y`.
- PetaLinux build passed: 3065 tasks attempted, all succeeded.
- Decompiled generated `system.dtb`; verified `drm-pl-disp-drv` with
  `compatible = "xlnx,pl-disp"` and `xlnx,vformat = "RG24"`.
- Board booted new `image.ub`; kernel version changed to build `#4`.
- Runtime showed `/dev/dri/card0`, VDMA probe, and Xilinx PL display probe.
- Runtime also showed no `/dev/fb*`, no connector status/modes/enabled files,
  and dmesg `Cannot find any crtc or sizes`.
- HDMI capture device 1 / DirectShow / 800x600 captured stable color bars.
- Ethernet remained good: board pinged PC `192.168.1.2` with 2/2 received.

Board action:

- Replaced `image.ub` on the TF-card FAT boot partition from the running board
  over Ethernet using `wget`; backed up the old `image.ub` on the same
  partition; rebooted from TF card. No JTAG programming, SRAM programming,
  QSPI, NAND, eMMC, or other nonvolatile board storage writes.

Evidence:

- `docs/reports/hdmi-linux-display-stack.md`
- `build/hdmi-linux-display-stack/petalinux-build.log`
- `build/hdmi-linux-display-stack/uart_board_image_update_session.log`
- `build/hdmi-linux-display-stack/uart_board_reboot_session.log`
- `build/hdmi-linux-display-stack/uart_board_drm_probe_session.log`
- `build/hdmi-linux-display-stack/hdmi-capture-device1-dshow/latest.png`

Result:

- PARTIAL. Linux now exposes `/dev/dri/card0` for the PL display pipeline, and
  HDMI output is physically present. Linux cannot yet control the HDMI image
  because no connector/mode provider exists.

Residual risks:

- The current VTC instance has no AXI-Lite register interface, so the Linux VTC
  bridge cannot be represented correctly without a Vivado BD change.
- A VTC bridge alone is not enough; the DRM stack still needs a connector/mode
  provider for the fixed rgb2dvi HDMI output.
- The next cycle must make a Linux userspace modeset or fbdev write visibly
  change HDMI output before the Ethernet video receiver cycle is opened.

## 2026-06-30 - hdmi-linux-fixed-mode-connector

Commit: this commit (`cycle: expose fixed-mode HDMI framebuffer`)

Objective:

Add the missing fixed-mode Linux DRM connector and prove that Linux userspace
can change the board's physical HDMI output through the VDMA framebuffer.

Changed scope:

- Added a minimal Xilinx DRM component driver for a fixed HDMI-A connector.
- Added the OF graph and fixed display timing to the PetaLinux overlay.
- Reserved Linux CMA inside the official VDMA DDR decode window.
- Added an `rgb-stripes` HDMI capture validation profile.
- Updated board facts, the active roadmap, and the preferred pipeline skill.

Verification:

- PetaLinux build passed all 3065 tasks.
- Kernel config and symbol map contain the fixed HDMI driver.
- Final DT contains the fixed HDMI graph and CMA reservation.
- Board exposes `/dev/dri/card0`, `/dev/fb0`, a connected connector, and the
  expected mode.
- VDMA start address is inside the official DDR window; status has no error
  bits before or after the framebuffer write.
- Boot log has no VDMA decode errors or atomic flip timeouts.
- A userspace raw-frame write changed HDMI to deterministic RGB stripes.
- Automated DirectShow HDMI capture returned `HDMI_CAPTURE_OK`.

Board action:

- Updated only `image.ub` on the TF-card FAT boot partition over Ethernet,
  retained recovery copies, rebooted, and wrote a userspace test frame through
  `/dev/fb0`. No JTAG programming or board flash write.

Evidence:

- `docs/reports/hdmi-linux-fixed-mode-connector.md`
- `build/hdmi-linux-fixed-mode-connector-cma-fix/petalinux-build.log`
- `build/hdmi-linux-fixed-mode-connector/uart-final-acceptance.log`
- `build/hdmi-linux-fixed-mode-connector/hdmi-cma-after-pattern-verified/latest-validation.json`

Result:

- PASSED. Linux owns a usable fixed-mode DRM/fbdev output, and userspace writes
  are visible and machine-validated through physical HDMI capture.

Residual risks:

- The connector has no EDID or hot-plug detection.
- The physical VTC remains fixed.
- The next receiver should prevent framebuffer-console writes from corrupting
  video frames.

## 2026-06-30 - ethernet-video-userspace-receiver

Commit: this commit (`cycle: close Ethernet UDP HDMI pass-through`)

Objective:

Receive the project UDP RGB888 frame protocol in Linux userspace, write
complete frames to the proven `/dev/fb0` path, and prove through HDMI capture
that a PC-sent known frame reaches the display.

Changed scope:

- Added a Linux userspace ARM receiver:
  `software/eth_pass_through/linux_app/src/fb_video_udp_receiver.c`.
- Added framebuffer channel mapping helpers and tests:
  `software/eth_pass_through/src/video_framebuffer.*` and
  `software/eth_pass_through/tests/test_linux_framebuffer_writer.c`.
- Added a WSL build/test wrapper:
  `software/eth_pass_through/scripts/build-linux-receiver-wsl.ps1`.
- Extended `tools/send_video_udp.py` with the `rgb-stripes` pattern.
- Updated `docs/current-cycle.md`, `docs/project-roadmap.md`, `README.md`,
  `software/eth_pass_through/README.md`, and the pipeline skill to record the
  verified pass-through route.
- Added `docs/reports/ethernet-video-userspace-receiver.md`.

Verification:

- Host unit tests passed:
  `VIDEO_UDP_RECEIVER_TEST_OK` and `VIDEO_FB_COPY_TEST_OK`.
- ARM cross-compile passed with PetaLinux 2018.3 toolchain. Output binary:
  32-bit ARM EABI5 Linux executable, SHA-256
  `3914d374fe5e5fc15a22da7c47b8a6fdc26df98f02454bf3c272413594946da4`.
- Board networking passed: PC ping to `192.168.1.10` 4/4, 0% loss; board ping
  to `192.168.1.2` 2/2, 0% loss.
- Board receiver log showed `/dev/fb0` 800x600, 24bpp, 2400-byte stride,
  channel bytes red=2 green=1 blue=0.
- PC sent one `rgb-stripes` 800x600 RGB888 frame as 1200 UDP packets.
- Board receiver log showed complete-frame and receiver-done markers with
  `packets=1200` and `dropped=0`.
- HDMI DirectShow capture with `rgb-stripes` validation returned
  `HDMI_CAPTURE_OK`.

Board action:

- Ran a userspace binary from `/tmp` after downloading it over Ethernet with
  `wget`. No Vivado rebuild, no PetaLinux rebuild, no JTAG programming, no
  QSPI, NAND, eMMC, or other board flash write.

Evidence:

- `docs/reports/ethernet-video-userspace-receiver.md`
- `build/ethernet-video-userspace-receiver/test_video_udp_receiver.log`
- `build/ethernet-video-userspace-receiver/test_linux_framebuffer_writer.log`
- `build/ethernet-video-userspace-receiver/uart_receiver_after_send_bgrfix.log`
- `build/ethernet-video-userspace-receiver/hdmi-after-udp-frame-bgrfix/latest-validation.json`

Result:

- PASSED. The first-stage Ethernet video pass-through MVP is physically closed:
  PC UDP RGB888 frame -> Linux userspace socket receiver -> `/dev/fb0` ->
  VDMA/DRM HDMI -> PC HDMI capture validation.

Residual risks:

- This proves single-frame pass-through at low packet rate, not sustained
  realtime video throughput.
- No loss recovery exists; incomplete UDP frames are dropped.
- The receiver is not yet packaged into the PetaLinux rootfs or started by
  init.
- Effects and runtime control remain later cycles.

## 2026-06-30 - sustained-low-fps-stream

Commit: this commit (`cycle: prove sustained low-FPS stream`)

Objective:

Prove the Linux UDP receiver can handle a sustained low-FPS multi-frame stream,
not just a single frame, while continuing to update HDMI through `/dev/fb0`.

Changed scope:

- Added elapsed-time markers to `fb_video_udp_receiver`.
- Added `tools/run_sustained_stream_probe.ps1`, a reproducible build/deploy/send
  and capture helper for low-FPS stream checks.
- Added `docs/reports/sustained-low-fps-stream.md`.
- Updated `docs/current-cycle.md`, `docs/cycle-log.md`, and the pipeline skill
  with the verified multi-frame route.

Verification:

- Host tests passed: `VIDEO_UDP_RECEIVER_TEST_OK` and
  `VIDEO_FB_COPY_TEST_OK`.
- ARM cross-compile passed. Output binary SHA-256:
  `b9a675bf12af95df866076083d6e547ce53bda9f1b9d3b834d30fbc3b7ab1b67`.
- One-shot PowerShell/.NET file server served the receiver binary to the board;
  board SHA-256 check passed.
- PC sent five 800x600 RGB888 frames: 6000 UDP packets total.
- Board logs showed five frame-write markers and
  `VIDEO_UDP_RECEIVER_DONE frames=5 packets=6000 dropped=0`.
- Ethernet counters after the stream showed RX/TX errors=0 and dropped=0.
- HDMI capture with `rgb-stripes` validation returned `HDMI_CAPTURE_OK`.

Board action:

- Ran a userspace binary from `/tmp` after Ethernet download, sent UDP frames
  from the PC, and captured HDMI. No Vivado rebuild, no PetaLinux rebuild, no
  JTAG programming, and no board flash write.

Evidence:

- `docs/reports/sustained-low-fps-stream.md`
- `build/sustained-low-fps-stream/send_video_udp.log`
- `build/sustained-low-fps-stream/uart_after_stream.log`
- `build/sustained-low-fps-stream/hdmi-after-stream/latest-validation.json`

Result:

- PASSED. The UDP-to-framebuffer-to-HDMI path handles a five-frame low-FPS
  stream without receiver drops.

Residual risks:

- This is a paced low-FPS proof, not a high-throughput realtime target.
- The pattern is static across frames; this proves repeated transport/display
  updates, not visual motion.
- UART control and board-side effects remain later cycles.

## 2026-06-30 - uart-control-endpoint

Commit: this commit (`cycle: add UART receiver control endpoint`)

Objective:

Add a UART-driven control path to the Linux receiver process and prove that a
UART command changes receiver behavior while UDP video input and HDMI output
remain working.

Changed scope:

- Added `software/eth_pass_through/src/video_control.*`.
- Added `software/eth_pass_through/tests/test_video_control.c`.
- Added `--control-fifo` support to the Linux receiver.
- Added `tools/run_uart_control_probe.ps1`.
- Added `--start-frame-id` to `tools/send_video_udp.py`.
- Added `docs/reports/uart-control-endpoint.md` and updated current-cycle,
  roadmap, cycle-log, and pipeline skill entries.

Verification:

- Host tests passed: `VIDEO_UDP_RECEIVER_TEST_OK`, `VIDEO_FB_COPY_TEST_OK`,
  and `VIDEO_CONTROL_TEST_OK`.
- ARM cross-compile passed. Output binary SHA-256:
  `41a7509a7e744054066e6f583f419e2d33193657e0735bd7db75d2d96469a575`.
- Board SHA-256 check passed after Ethernet download.
- UART command `pause` produced `CONTROL_PAUSED`.
- A complete UDP frame while paused produced
  `VIDEO_UDP_FRAME_SKIPPED_PAUSED frame_id=100`.
- UART commands `resume` and `status` produced `CONTROL_RESUMED` and
  `CONTROL_STATUS paused=0`.
- A subsequent UDP frame produced `VIDEO_UDP_FRAME_WRITTEN frame_id=101` and
  `VIDEO_UDP_RECEIVER_DONE frames=1 skipped=1 packets=2400 dropped=0`.
- HDMI capture with `rgb-stripes` validation returned `HDMI_CAPTURE_OK`.

Board action:

- Ran a userspace binary from `/tmp`, sent UART shell commands to the FIFO
  endpoint, sent UDP frames from the PC, and captured HDMI. No Vivado rebuild,
  no PetaLinux rebuild, no JTAG programming, and no board flash write.

Evidence:

- `docs/reports/uart-control-endpoint.md`
- `build/uart-control-endpoint/test_video_control.log`
- `build/uart-control-endpoint/uart_final.log`
- `build/uart-control-endpoint/hdmi-after-uart-control/latest-validation.json`

Result:

- PASSED. The receiver now has a verified UART fallback control endpoint.

Residual risks:

- The FIFO endpoint is intentionally minimal and not yet packaged as a daemon.
- TCP/UDP command transport is not implemented.
- Board-side visual effects remain the next cycle.

## 2026-06-30 - first-board-side-effect

Commit: this commit (`cycle: add first board-side video effect`)

Objective:

Add the first board-side visual effect to the Linux receiver and prove that the
board changes the displayed frame while the PC sends the same deterministic
non-camera input pattern.

Changed scope:

- Added `software/eth_pass_through/src/video_effect.*`.
- Added `software/eth_pass_through/tests/test_video_effect.c`.
- Added `--effect none|invert` to the Linux receiver.
- Added `inverted-rgb-stripes` validation to `tools/capture_hdmi.py`.
- Added `tools/run_first_effect_probe.ps1`.
- Added `docs/reports/first-board-side-effect.md`.
- Updated current-cycle, cycle-log, roadmap, README, and pipeline skill entries.

Verification:

- Host tests passed: `VIDEO_UDP_RECEIVER_TEST_OK`, `VIDEO_FB_COPY_TEST_OK`,
  `VIDEO_CONTROL_TEST_OK`, and `VIDEO_EFFECT_TEST_OK`.
- ARM cross-compile passed. Output binary SHA-256:
  `73ef6f5b0e6ac03528ad1c73eb5d2bdcd665ad12514e1d436bff4bdcab1c35ab`.
- Board SHA-256 check passed after Ethernet download.
- PC sent a deterministic generated `rgb-stripes` frame; no camera/webcam input
  was used.
- Board log showed `VIDEO_UDP_FRAME_WRITTEN frame_id=200 ... effect=invert`
  and `VIDEO_UDP_RECEIVER_DONE frames=1 skipped=0 packets=1200 dropped=0`.
- HDMI capture with `inverted-rgb-stripes` validation returned
  `HDMI_CAPTURE_OK`.

Board action:

- Ran a userspace binary from `/tmp`, sent one generated UDP frame from the PC,
  and captured HDMI for output verification. No camera/webcam input, no Vivado
  rebuild, no PetaLinux rebuild, no JTAG programming, and no board flash write.

Evidence:

- `docs/reports/first-board-side-effect.md`
- `build/first-board-side-effect/test_video_effect.log`
- `build/first-board-side-effect/uart_after_effect_frame.log`
- `build/first-board-side-effect/hdmi-after-invert-effect/latest-validation.json`

Result:

- PASSED. The receiver applies a verified board-side RGB invert transform before
  framebuffer output.

Residual risks:

- This is a CPU software effect, not yet a PL PIP/rotate/scale pipeline.
- Runtime effect switching through UART is not implemented yet.
- Throughput remains unoptimized.

## 2026-07-01 - visual-dashboard-scaffold

Commit: this commit (`cycle: add visual dashboard scaffold`)

Objective:

Add the first PC-side visual dashboard scaffold with input preview, FPGA output
preview, and a control/log panel skeleton.

Changed scope:

- Added `tools/dashboard/pc_dashboard.py`.
- Added `tools/dashboard/README.md`.
- Added `docs/reports/visual-dashboard-scaffold.md`.
- Updated current-cycle, cycle-log, roadmap, README, and pipeline skill entries.

Verification:

- Ran:
  `rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\visual-dashboard-scaffold"`
- Result: `DASHBOARD_SCAFFOLD_SELF_TEST_OK`.
- Self-test fetched dashboard HTML, state JSON, generated input SVG, and FPGA
  output placeholder SVG.
- Self-test asserted input, output, and control panel regions exist.
- Self-test asserted camera input and custom-file input are disabled.

Board action:

- None. PC dashboard scaffold only.

Evidence:

- `docs/reports/visual-dashboard-scaffold.md`
- `build/visual-dashboard-scaffold/state.json`
- `build/visual-dashboard-scaffold/index.html`

Result:

- PASSED. The PC dashboard scaffold is available and self-tested.

Residual risks:

- UDP sender integration and UART control integration remain later dashboard
  cycles.
- FPGA output preview is a slot/placeholder until a capture file is supplied.

## 2026-07-01 - fixed-demo-video-sender

Commit: this commit (`cycle: add fixed dashboard demo sender`)

Objective:

Add a fixed built-in dynamic video source for the dashboard MVP without adding
camera/webcam capture or user-selected input files.

Changed scope:

- Added `tools/dashboard/demo_source.py`, a deterministic RGB888 dynamic frame
  generator.
- Added `tools/send_demo_video_udp.py`, a PC-side UDP sender that uses the
  existing project video packet format.
- Added `tools/dashboard/__init__.py` for package imports.
- Updated dashboard, roadmap, current-cycle, README, and pipeline skill docs.

Verification:

- Ran:
  `rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\fixed-demo-video-sender"`
- Result: `DEMO_VIDEO_SENDER_SELF_TEST_OK`.
- Parser inspection returned
  `DEMO_VIDEO_SENDER_CLI_NO_CAMERA_OR_FILE_OK` and showed no camera/webcam/file
  option.
- Self-test proved generated frame size, dynamic frame difference, localhost UDP
  packetization, received packet count, payload byte count, and frame id.
- Self-test recorded `camera_input=false` and `custom_file_input=false`.

Board action:

- None. PC-side fixed demo sender only.

Evidence:

- `docs/reports/fixed-demo-video-sender.md`
- `build/fixed-demo-video-sender/self-test.json`

Result:

- PASSED. The dashboard MVP now has a deterministic dynamic source that can feed
  the existing board UDP receiver without a camera, webcam, file picker, or
  custom media path.

Residual risks:

- The generated source is not arbitrary video-file playback.
- This cycle proves localhost packetization, not board receive/display.
- Dashboard action integration remains the next cycle.

## 2026-07-01 - dashboard-control-integration

Commit: this commit (`cycle: integrate dashboard controls`)

Objective:

Wire the PC visual dashboard to actionable stream/control commands while
keeping verification deterministic and PC-side.

Changed scope:

- Extended `tools/dashboard/pc_dashboard.py` with `/api/actions`,
  `/api/action`, button handlers, dry-run action runner, and control state.
- Added `docs/reports/dashboard-control-integration.md`.
- Updated current-cycle, roadmap, README, dashboard README, and pipeline skill.
- Preserved the no-camera/no-custom-file MVP input policy.

Verification:

- Ran:
  `rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-control-integration"`
- Results:
  `DASHBOARD_SCAFFOLD_SELF_TEST_OK` and
  `DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK`.
- Self-test fetched HTML/state/previews, fetched `/api/actions`, posted six
  dry-run actions, and verified final stream, receiver pause, selected effect,
  logs, and disabled camera/custom-file policy.

Board action:

- None. PC dashboard action-surface integration only.

Evidence:

- `docs/reports/dashboard-control-integration.md`
- `build/dashboard-control-integration/actions.json`
- `build/dashboard-control-integration/action-results.json`
- `build/dashboard-control-integration/final-state.json`

Result:

- PASSED. The dashboard has a tested dry-run control surface for sender,
  UART/FIFO command semantics, and effect launch semantics.

Residual risks:

- The dashboard does not yet start/stop a real sender subprocess.
- The dashboard does not yet transmit UART/FIFO commands.
- Runtime effect switching is not yet proven.

## 2026-07-01 - dashboard-live-minimal-controls

Commit: this commit (`cycle: make dashboard controls functional`)

Objective:

Make the dashboard functional and visually minimal.

Changed scope:

- Reworked `tools/dashboard/pc_dashboard.py` into a plain functional web view
  without decorative backgrounds, gradient buttons, shadows, or card styling.
- Changed default dashboard action mode to live.
- Made `start-stream` launch a real dashboard-owned
  `tools/send_demo_video_udp.py` subprocess.
- Made `stop-stream` terminate that subprocess.
- Wired UART/FIFO receiver actions through `tools/uart_run_commands.ps1` when a
  UART port is configured.
- Extended `tools/send_demo_video_udp.py` with `--frames 0` continuous send.
- Updated README, dashboard README, roadmap, current-cycle, and pipeline skill.

Verification:

- Ran:
  `rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-live-minimal-controls"`
- Results:
  `DASHBOARD_SCAFFOLD_SELF_TEST_OK`,
  `DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK`,
  `DASHBOARD_MINIMAL_UI_SELF_TEST_OK`, and
  `DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK`.
- Self-test proved minimal HTML, real sender subprocess start, real localhost
  `ZVID` UDP packet reception, sender stop, explicit UART-not-configured
  failure, and no camera/custom-file input.
- Ran sender self-test and Python compile check.

Board action:

- None. UART live binding was implemented but not exercised against the board.

Evidence:

- `docs/reports/dashboard-live-minimal-controls.md`
- `build/dashboard-live-minimal-controls/action-results.json`
- `build/dashboard-live-minimal-controls/final-state.json`
- `build/dashboard-live-minimal-controls/sender.out.log`

Result:

- PASSED. The dashboard is now a minimal functional control panel.

Residual risks:

- The dashboard does not deploy or start the board receiver process.
- UART/FIFO buttons require board shell and `/tmp/video_ctl` readiness.
- Runtime effect switching remains future work.

## 2026-07-01 - dashboard-hdmi-capture-binding

Commit: this commit (`cycle: bind dashboard HDMI capture`)

Objective:

Make the dashboard output panel capture HDMI after `start-stream`.

Changed scope:

- Added `none` validation profile to `tools/capture_hdmi.py`.
- Added dashboard capture configuration and the `capture-output` action.
- Changed `start-stream` to launch the sender and then attempt one HDMI capture.
- Changed the output preview to refresh during dashboard polling.
- Updated README, dashboard README, roadmap, current-cycle, and pipeline skill.

Verification:

- Ran Python compile check for the dashboard, capture tool, and sender.
- Ran:
  `rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-hdmi-capture-binding"`
- Results:
  `DASHBOARD_SCAFFOLD_SELF_TEST_OK`,
  `DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK`,
  `DASHBOARD_MINIMAL_UI_SELF_TEST_OK`, and
  `DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK`.
- Ran live HDMI preview capture with `--validation-profile none`; result:
  `HDMI_CAPTURE_OK device_index=0 backend=dshow`.

Board action:

- PC-side HDMI capture only. No Vivado rebuild, PetaLinux rebuild, JTAG
  programming, or board flash write.

Evidence:

- `docs/reports/dashboard-hdmi-capture-binding.md`
- `build/dashboard-hdmi-capture-binding/final-state.json`
- `build/dashboard-hdmi-capture-binding/hdmi-capture/latest-validation.json`
- `build/dashboard-hdmi-capture-binding/hdmi-capture/latest.png`

Result:

- PASSED for dashboard/capture binding. The dashboard now calls HDMI capture
  from `start-stream` and `capture-output`.

Residual risks:

- The live capture image was near black (`mean_luma=0.05`). Capture invocation
  is wired, but meaningful board output still depends on the receiver/display
  path being active.
- `start-stream` does not deploy or start the board receiver.
- The output preview is action-triggered capture, not continuous live video.

## 2026-07-01 - dashboard-hdmi-capture-timeout-fix

Commit: this commit (`fix: extend dashboard HDMI capture timeout`)

Objective:

Fix the real dashboard `start-stream` path timing out during HDMI capture.

Changed scope:

- Increased the dashboard capture subprocess timeout to at least 90 seconds.
- Reduced default dashboard preview capture frames from 20 to 8.
- Added the timeout-fix report.

Verification:

- Ran Python compile check for `tools/dashboard/pc_dashboard.py`.
- Ran:
  `rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-hdmi-capture-timeout-fix"`
- Results:
  `DASHBOARD_SCAFFOLD_SELF_TEST_OK`,
  `DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK`,
  `DASHBOARD_MINIMAL_UI_SELF_TEST_OK`, and
  `DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK`.
- Restarted the local dashboard and tested the actual user path:
  `start-stream` returned `HDMI_CAPTURE_OK`, `capture_status=ok`, and
  `image_exists=true`; `stop-stream` stopped the sender.

Board action:

- PC-side dashboard process and HDMI capture only. No Vivado, PetaLinux, JTAG,
  or board flash action.

Evidence:

- `docs/reports/dashboard-hdmi-capture-timeout-fix.md`
- `build/dashboard-hdmi-capture-timeout-fix/final-state.json`
- `build/dashboard-live/hdmi-capture/latest-validation.json`
- `build/dashboard-live/hdmi-capture/latest.png`

Result:

- PASSED. Clicking `start-stream` now triggers HDMI capture successfully.

Residual risks:

- The captured frame is still near black (`mean_luma=0.14`), so the remaining
  issue is board receiver/output readiness.
- Output preview is not continuous realtime capture yet.

## 2026-07-01 - dashboard-board-live-loop

Commit: this commit (`cycle: close dashboard board live loop`)

Objective:

Complete a displayable dashboard-driven board video loop.

Changed scope:

- Added `tools/run_dashboard_board_live_loop.ps1`.
- Added `non-black` HDMI validation to `tools/capture_hdmi.py`.
- Allowed `tools/dashboard/pc_dashboard.py` to use
  `--capture-profile non-black`.
- Added the cycle report and updated README, dashboard README, roadmap,
  current-cycle, cycle-log, and pipeline skill.

Verification:

- Ran script parse check, Python compile check, and dashboard self-test.
- Ran:
  `rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-board-live-loop -CaptureDevice auto -CaptureFrames 8 -Frames 5 -Fps 1 -InterPacketUs 200`
- Marker file:
  `DASHBOARD_BOARD_LIVE_LOOP_OK frames=5 written=5`.
- Receiver deployment showed `/tmp/fb_video_udp_receiver: OK`,
  `CONTROL_FIFO_READY`, and `VIDEO_UDP_LINUX_RECEIVER_READY`.
- Dashboard `start-stream` returned `HDMI_CAPTURE_OK`, `capture_status=ok`,
  and `image_exists=true`.
- Sender sent five generated RGB888 frames as 6000 UDP packets.
- Receiver wrote five frames and reported
  `VIDEO_UDP_RECEIVER_DONE frames=5 skipped=0 packets=6000 dropped=0`.
- HDMI capture profile `non-black` passed with `mean_luma=136.39` on selected
  DirectShow index 1.

Board action:

- Ran a Linux userspace receiver from `/tmp`, sent UDP frames from the PC
  through Dashboard, and captured HDMI. No Vivado rebuild, PetaLinux rebuild,
  JTAG programming, or board flash write.

Evidence:

- `docs/reports/dashboard-board-live-loop.md`
- `build/dashboard-board-live-loop/dashboard_board_live_loop.marker.txt`
- `build/dashboard-board-live-loop/dashboard_start_stream.json`
- `build/dashboard-board-live-loop/uart_after_dashboard_stream.log`
- `build/dashboard-board-live-loop/hdmi-capture/latest-validation.json`
- `build/dashboard-board-live-loop/hdmi-capture/latest.png`

Result:

- PASSED. The project now has a displayable dashboard-driven closed loop.

Residual risks:

- Output preview is action-triggered HDMI capture, not continuous live video.
- Pause/resume controls were not exercised in this cycle.
- Runtime effect switching remains future work.

## 2026-07-01 - dashboard-truthful-loop-validation

Commit: this commit (`cycle: validate truthful dashboard loop`)

Objective:

Correct the dashboard closed-loop demo so the visible input, dashboard control
state, and HDMI evidence describe the real data path instead of a decorative
input preview plus one stale HDMI snapshot.

Changed scope:

- Replaced the dashboard SVG input preview with a BMP endpoint generated from
  the exact `demo_source.py` frame function used by the UDP sender.
- Changed HDMI capture actions to schedule a background capture thread so
  `start-stream` returns after sender launch and capture scheduling.
- Added sample saving and dynamic sample-hash validation to the board-live
  helper.
- Added UART Ctrl-C recovery before deployment so a stale foreground `wget`
  does not make later UART commands appear to run while the shell is blocked.
- Updated report, roadmap, README, dashboard README, current-cycle, and
  pipeline skill.

Verification:

- Ran Python compile check for dashboard, demo source, sender, and HDMI capture.
- Ran:
  `rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-truthful-loop-validation-selftest"`
- Results:
  `DASHBOARD_SCAFFOLD_SELF_TEST_OK`,
  `DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK`,
  `DASHBOARD_MINIMAL_UI_SELF_TEST_OK`, and
  `DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK`.
- Ran:
  `rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-truthful-loop-validation -CaptureDevice 1 -CaptureBackend dshow -CaptureFrames 90 -CaptureSaveSamples 6 -Frames 12 -Fps 2 -InterPacketUs 200`
- Marker:
  `DASHBOARD_BOARD_LIVE_LOOP_OK frames=12 written=12 dynamic_samples_unique=5`.
- Receiver wrote 12 frames, 14400 UDP packets, dropped=0.
- HDMI capture selected DirectShow index 1, read 90 frames, passed non-black
  validation with mean_luma=137.36, and saved six samples with five unique
  hashes.

Board action:

- Ran a Linux userspace receiver from `/tmp`, sent generated UDP frames from
  the PC through Dashboard, and captured HDMI. No Vivado rebuild, PetaLinux
  rebuild, JTAG programming, TF-card write, or board flash write.

Evidence:

- `docs/reports/dashboard-truthful-loop-validation.md`
- `build/dashboard-truthful-loop-validation/dashboard_board_live_loop.marker.txt`
- `build/dashboard-truthful-loop-validation/dashboard_start_stream.json`
- `build/dashboard-truthful-loop-validation/dashboard_capture_done_state.json`
- `build/dashboard-truthful-loop-validation/uart_after_dashboard_stream.log`
- `build/dashboard-truthful-loop-validation/hdmi_dynamic_sample_hashes.json`
- `build/dashboard-truthful-loop-validation/hdmi-capture/latest-validation.json`
- `build/dashboard-truthful-loop-validation/hdmi-capture/latest-sample-00.png`
- `build/dashboard-truthful-loop-validation/hdmi-capture/latest-sample-05.png`

Result:

- PASSED. The dashboard closed-loop demo now has an honest input preview, a
  non-blocking action path, and dynamic HDMI evidence from the connected board.

Residual risks:

- The browser output panel is still a periodically refreshed HDMI snapshot, not
  a continuous video widget.
- Windows reports the HDMI/UVC adapter as camera access; this is output capture
  only and does not enable webcam/video input.
- Pause/resume/effect live choreography remains a later demo cycle.

## 2026-07-01 - dashboard-live-pass-through-preview

Commit: this commit (`cycle: add live HDMI return preview`)

Objective:

Make the dashboard right panel show the live HDMI return path for no-effect
pass-through, instead of presenting a static capture image as video.

Changed scope:

- Added `/api/output-stream.mjpeg` to `tools/dashboard/pc_dashboard.py`.
- Changed the dashboard right panel to consume the live HDMI MJPEG endpoint.
- Changed `start-stream` to start the sender and report
  `HDMI_RETURN_STREAM_READY` by default, leaving still capture as a manual
  fallback action.
- Added `tools/probe_mjpeg_stream.py` to validate the same MJPEG stream the
  browser consumes.
- Updated `tools/run_dashboard_board_live_loop.ps1` to validate live MJPEG
  return frames instead of only static HDMI capture artifacts.
- Updated report, roadmap, README, dashboard README, current-cycle, and
  pipeline skill.

Verification:

- Ran Python compile check for dashboard, MJPEG probe, demo source, sender, and
  HDMI capture.
- Ran PowerShell parse check for `tools/run_dashboard_board_live_loop.ps1`.
- Ran:
  `rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-live-pass-through-preview-selftest"`
- Results:
  `DASHBOARD_SCAFFOLD_SELF_TEST_OK`,
  `DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK`,
  `DASHBOARD_MINIMAL_UI_SELF_TEST_OK`, and
  `DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK`.
- Ran:
  `rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-live-pass-through-preview -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -Frames 12 -Fps 2 -InterPacketUs 200`
- Marker:
  `DASHBOARD_BOARD_LIVE_LOOP_OK frames=12 written=12 mjpeg_frames=80 mjpeg_unique=26`.
- Receiver wrote 12 frames, 14400 UDP packets, dropped=0.
- MJPEG probe read 80 returned HDMI frames from `/api/output-stream.mjpeg` with
  26 unique hashes.

Board action:

- Ran a Linux userspace receiver from `/tmp`, sent generated UDP frames from
  the PC through Dashboard, and streamed HDMI back through the PC HDMI capture
  adapter. No Vivado rebuild, PetaLinux rebuild, JTAG programming, TF-card
  write, or board flash write.

Evidence:

- `docs/reports/dashboard-live-pass-through-preview.md`
- `build/dashboard-live-pass-through-preview/dashboard_board_live_loop.marker.txt`
- `build/dashboard-live-pass-through-preview/dashboard_start_stream.json`
- `build/dashboard-live-pass-through-preview/dashboard_final_state.json`
- `build/dashboard-live-pass-through-preview/uart_after_dashboard_stream.log`
- `build/dashboard-live-pass-through-preview/mjpeg-return/mjpeg-stream-probe.json`
- `build/dashboard-live-pass-through-preview/mjpeg-return/mjpeg-frame-00.jpg`
- `build/dashboard-live-pass-through-preview/mjpeg-return/mjpeg-frame-79.jpg`

Result:

- PASSED. The right dashboard panel now uses a live HDMI return stream for the
  no-effect pass-through demo.

Residual risks:

- This is live visual pass-through, not pixel-perfect source/output equality.
  HDMI/UVC capture and MJPEG encoding can change exact pixels.
- The browser input preview and HDMI return preview are not frame-locked.
- Pause/resume/effect live choreography remains a later demo cycle.
