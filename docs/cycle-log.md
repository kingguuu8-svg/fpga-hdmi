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
