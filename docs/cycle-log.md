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
