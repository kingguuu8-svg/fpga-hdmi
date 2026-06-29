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
- The hardware experiment cycle `eth-ps-pl-hdmi-pass-through` remains paused
  waiting for a TF card; see `docs/reports/tf-card-linux-resume-2026-06-26.md`.

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
