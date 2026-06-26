# Current Cycle

Status: paused.

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
Cycle ID: eth-ps-pl-hdmi-pass-through
Objective: pass original PC-sent video/static frames through Ethernet, PS DDR,
  VDMA framebuffer readout, and HDMI with no video effects.
Scope: route is paused until TF-card Linux Ethernet can be checked. While
  paused, keep the repository aligned to the VDMA/RGB888 path and do not spend
  more time tuning the hand-written baremetal RGMII bridge.
Verification plan: next hardware gate is official TF-card Linux boot plus PC
  ping to the board over the PL-side RTL8211E network path.
Board action: when the TF card arrives, boot the official Linux all-test image
  from TF card. Do not write QSPI, NAND, eMMC, or other nonvolatile storage.
Evidence target: docs/reports/tf-card-linux-resume-2026-06-26.md and a new
  dated report under docs/reports/ after the experiment.
Closure criteria: official Linux either responds to ping, selecting the
  Linux/socket route, or fails with recorded UART/Linux/network evidence that
  justifies returning to lower-level PHY/RGMII debug.
```

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
