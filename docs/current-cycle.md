# Current Cycle

Status: active implementation cycle (skill-env-baseline); the hardware
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
Cycle ID: skill-env-baseline
Objective: stop the skills from re-probing a known-stable environment on every
  cycle, and close the skill gaps left by the route pivot (vivado skill missing
  the eth-ps-pl build/sim entry, skills holding stale command copies that
  violate the new fact-consistency rule).
Scope: add docs/environment-baseline.md as a git-tracked, one-time-confirmed
  environment fact; edit the three project skills so probing is triggered by
  baseline-invalidation events instead of every cycle; make vivado skill
  reference the board reference and pipeline skill for facts it currently
  restates; verify the sim/build command chain resolves to real files.
  No RTL/XDC/Tcl logic changes; no board programming.
Verification plan: read each edited skill and confirm the trigger logic is
  present and correct; dry-check that every command path named in the skills
  resolves to a tracked file; confirm environment-baseline.md facts match the
  probe scripts' default paths and the board reference.
Board action: none. This cycle does not touch hardware; the baseline it records
  was already confirmed by prior probe runs.
Evidence target: the commit, plus a docs/cycle-log.md entry.
Closure criteria:
  1. docs/environment-baseline.md exists, is git-tracked, and its facts match
     the probe-script defaults and board reference.
  2. environment, pipeline, and vivado skills contain the baseline-trigger
     logic and no longer mandate per-cycle probing when the baseline is valid.
  3. vivado skill no longer restates board facts; it references the board
     reference and pipeline skill per the fact-consistency rule.
  4. Every sim/build command path named in the skills resolves to a tracked file.
Highest-risk assumption this cycle falsifies:
  The environment facts being written into the baseline file are still true on
  this machine right now (Vivado paths, JTAG adapter, device, board profile,
  UART, HDMI capture, Ethernet IP), and the skill command paths all resolve.
Cheapest alternative way to falsify the same assumption:
  Cross-check each baseline fact against the probe-script default paths and the
  board reference's Current Interface Baseline section, and dry-check each
  skill-named command path against the tracked file tree. Pure file checks, no
  hardware, no Vivado invocation.
```

## Recently Closed Cycle

```text
Cycle ID: baseline-checkpoint
Commit: bef3299
Result: committed the eth-ps-pl-hdmi-pass-through work surface (52 files) into
  git; working tree is clean; route-pivot documents no longer dangle-reference
  untracked files. See docs/cycle-log.md for the full entry.
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
