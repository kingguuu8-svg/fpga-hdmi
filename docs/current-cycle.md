# Current Cycle

Status: no active implementation cycle. The TF-card Linux ping route gate
PASSED on 2026-06-29 (see docs/reports/tf-card-linux-ping-2026-06-29.md).
The next cycle should implement the Linux/socket video path. The hand-written
baremetal RGMII bridge is retired.

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

## Resolved Route Gate

The TF-card Linux ping route gate PASSED on 2026-06-29. The paused cycle's
closure criterion is met: official Linux responds to ping, selecting the
Linux/socket route.

```text
Cycle ID: eth-ps-pl-hdmi-pass-through (route-gate phase)
Result: PASSED. Official Linux boots from TF card, eth0 link up at 1000/Full,
  PC ping 192.168.1.10 = 4/4 received, 0% loss.
Evidence: docs/reports/tf-card-linux-ping-2026-06-29.md
Decision: Outcome A — proceed on Linux/socket route, retire hand-written
  baremetal RGMII bridge.
```

## Current Decision

The active implementation route is now confirmed by hardware evidence:

```text
PC UDP RGB888 frame -> Linux userspace socket receiver -> DDR framebuffer
-> VDMA MM2S -> v_axi4s_vid_out -> rgb2dvi -> HDMI
```

The hand-written baremetal RGMII bridge + lwIP route is retired. It was
verified as a dead end: the same physical path that fails under the hand-written
bridge works perfectly under Linux + official macb driver (RX errors=0, ping
0% loss). The bridge code remains in the repo as negative evidence only.

## Current Evidence

Known-good subchains:

```text
Official VDMA HDMI image passed on connected board and PC HDMI capture.
Official pure-PL UDP loopback passed over the same PC/RJ45/RTL8211E path.
Official Linux boots from TF card, eth0 1000/Full, RX errors=0, ping 0% loss.  [NEW 2026-06-29]
Project baremetal board-to-PC UDP heartbeat works (but PC-to-board RX does not).
```

Retired dead end:

```text
Project baremetal PC-to-board UDP RX through the hand-written RGMII bridge:
rx=0, rxfcs rising, no frames reach lwIP. Root cause confirmed by the Linux
ping result as the hand-written bridge BUFIO/BUFG crossing, not the physical
layer. Do not resume this work.
```

Next cycle direction:

```text
Implement the Linux/socket video receiver: PC UDP -> Linux socket -> DDR
framebuffer write -> VDMA HDMI output. Start at the smallest frame size that
proves the loop, then scale up.
```
