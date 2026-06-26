# Current Cycle

Status: active implementation cycle (baseline-checkpoint); the hardware
experiment cycle eth-ps-pl-hdmi-pass-through remains paused waiting for a TF
card.

## Rule

Open a cycle here before starting implementation work that should end in a
commit. A cycle must have a concrete objective, verification plan, and closure
criteria.

## Cycle Template

```text
Cycle ID:
Objective:
Scope:
Verification plan:
Board action:
Evidence target:
Closure criteria:
Highest-risk assumption this cycle falsifies:
Cheapest alternative way to falsify the same assumption:
```

The last two fields are the human review gate for opening a cycle. They force
the cycle author to state, before any work begins, which assumption is the
riskiest one being tested and whether a cheaper experiment could falsify the
same assumption. If the "cheapest alternative" line names a much shorter path
than the planned scope, the cycle direction should be reconsidered before
approval, not after debugging. These two lines exist to be read by a human at
cycle open time; they are not a self-audit checklist for cycle close.

## Active Cycle

```text
Cycle ID: baseline-checkpoint
Objective: commit the completed eth-ps-pl-hdmi-pass-through work surface and
  supporting tooling into git, eliminating dangling references from
  roadmap/skill/README to untracked files, and returning the repository to the
  clean baseline required by docs/project-start-standard.md.
Scope: stage the currently untracked examples/eth-ps-pl-hdmi-pass-through,
  software/, docs/protocols/, docs/boards/lookup-log.md,
  docs/reports/eth-ps-pl-hdmi-pass-through.md,
  docs/reports/third-party-review-2026-06-26.md, and tools/*.{ps1,py,tcl},
  plus the already-modified .gitignore, skills/zynq7020-vivado/scripts/sim.tcl,
  and docs/boards/hellofpga-smart-zynq-sl.md. No RTL/Tcl/software logic changes;
  this is a source-checkpoint cycle only. Retired custom-reader files are
  committed as-is for historical traceability; their cleanup is a later cycle.
Verification plan: after commit, git status --short shows no files in this
  cycle's scope; every path referenced by README/roadmap/skill resolves to a
  git-tracked object; tools/downloads remains gitignored and is not staged.
Board action: none. This cycle does not touch hardware.
Evidence target: the commit itself, plus a docs/cycle-log.md entry.
Closure criteria:
  1. All 16 untracked items and the in-scope modified files are committed.
  2. git status --short shows no in-scope files remaining.
  3. docs/cycle-log.md has a baseline-checkpoint entry with the commit id.
  4. README/roadmap/skill referenced paths are all git-tracked.
Highest-risk assumption this cycle falsifies:
  The working-tree files are complete and self-consistent as-is: no half-written
  sources, no dead references to deleted paths, no build products that should be
  gitignored but would be mistakenly staged.
Cheapest alternative way to falsify the same assumption:
  Per-file inspection before staging: check the eth example .v/.tcl/.xdc point
  to the VDMA path (not the retired custom-reader as the live path), check
  tools/downloads is still blocked by .gitignore, check sim.tcl's edit matches
  the committed eth example. Pure file checks, zero hardware cost, under an hour.
```

## Paused Cycle

The hardware experiment cycle remains paused waiting for a TF card. It is
recorded here so it can be resumed unchanged when the card arrives.

```text
Cycle ID: eth-ps-pl-hdmi-pass-through
Objective: pass original PC-sent video/static frames through Ethernet, PS DDR,
  VDMA framebuffer readout, and HDMI with no video effects.
Status: paused; route gate is the TF-card Linux ping experiment.
Verification plan: official TF-card Linux boot plus PC ping to the board over
  the PL-side RTL8211E network path.
Board action: when the TF card arrives, boot the official Linux all-test image
  from TF card. Do not write QSPI, NAND, eMMC, or other nonvolatile storage.
Evidence target: docs/reports/tf-card-linux-resume-2026-06-26.md and a new
  dated report under docs/reports/ after the experiment.
Closure criteria: official Linux either responds to ping, selecting the
  Linux/socket route, or fails with recorded UART/Linux/network evidence that
  justifies returning to lower-level PHY/RGMII debug.
```

Resume procedure when the TF card arrives: follow
`docs/reports/tf-card-linux-resume-2026-06-26.md`.

## Current Decision

The active implementation route is:

```text
PC UDP RGB888 frame -> PS/Linux or PS fallback receiver -> DDR framebuffer
-> VDMA MM2S -> v_axi4s_vid_out -> rgb2dvi -> HDMI
```

The old route is retired for the active cycle:

```text
PC UDP RGB565 -> PS baremetal lwIP -> 0x10000000 custom AXI reader
-> custom TMDS HDMI
```

Do not use the retired route as completion evidence.

## Current Evidence

Known-good subchains:

```text
Official VDMA HDMI image passed on connected board and PC HDMI capture.
Official pure-PL UDP loopback passed over the same PC/RJ45/RTL8211E path.
Project baremetal board-to-PC UDP heartbeat works.
```

Known blocker:

```text
Project baremetal PC-to-board UDP RX through the hand-written RGMII bridge is
not reliable enough to assemble a frame. Static ARP and slow UDP pacing do not
close the gap. The IDELAY=9 idea has already been applied to the custom bridge;
the remaining suspect is the implementation sub-route itself, especially the
hand-written RGMII/GMII crossing versus the official Xilinx gmii_to_rgmii IP or
the vendor Linux network stack.
```

Next action when TF card is available:

```text
Follow docs/reports/tf-card-linux-resume-2026-06-26.md.
```
