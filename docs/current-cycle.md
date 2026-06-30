# Current Cycle

Status: no active implementation cycle.

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

### Optional third-party review (recorded after cycle close, non-blocking)

A closed cycle may carry a `## Third-party review` section appended after the
cycle's own report. It records an external reviewer's verification findings:
what was independently checked, whether claims hold up, and any residual
concerns the reviewer spotted that the cycle's own closure criteria did not
cover. This section is non-blocking — it does not reopen the cycle or gate the
next one. Its purpose is to leave a durable, checked record so that the next
agent or the human can read the reviewer's view alongside the cycle's own PASSED
claim, and decide whether the residual concerns deserve a follow-up cycle.
If no review was performed, omit the section entirely; do not write a
placeholder.

## Recently Closed Cycle

```text
Cycle ID: petalinux-vdma-hdmi-minimal-project
Result: PASSED. The VDMA HDMI hardware description was made Linux-consumable by
  connecting VDMA MM2S/S2MM interrupts to PS IRQ_F2P. PetaLinux 2018.3 built
  image.ub in the Ubuntu 18.04 chroot, packaged BOOT.BIN, and copied BOOT.BIN +
  image.ub to the ZYNQBOOT TF-card partition with matching SHA256 hashes.
Evidence: docs/reports/petalinux-vdma-hdmi-minimal-project.md
Board action: TF-card file write only; no board boot or nonvolatile flash write.
```

## Active Cycle

```text
None.
```

## Resolved Route Gate

The TF-card Linux ping route gate PASSED on 2026-06-29.

```text
Cycle ID: eth-ps-pl-hdmi-pass-through (route-gate phase)
Result: PASSED. Official Linux boots from TF card, eth0 link up at 1000/Full,
  PC ping 192.168.1.10 = 4/4 received, 0% loss.
Evidence: docs/reports/tf-card-linux-ping-2026-06-29.md
Decision: Outcome A - proceed on Linux/socket route, retire hand-written
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
Official Linux boots from TF card, eth0 1000/Full, RX errors=0, ping 0% loss.
PetaLinux 2018.3 host tooling is installed and command-visible in WSL.
Project baremetal board-to-PC UDP heartbeat works (but PC-to-board RX does not).
```

Retired dead end:

```text
Project baremetal PC-to-board UDP RX through the hand-written RGMII bridge:
rx=0, rxfcs rising, no frames reach lwIP. Root cause confirmed by the Linux
ping result as the hand-written bridge BUFIO/BUFG crossing, not the physical
layer. Do not resume this work.
```

## Next Cycle Direction

```text
Cycle ID: petalinux-vdma-hdmi-boot-verify
Objective: boot the generated TF-card image and confirm UART login, eth0 link,
  static IP, PC ping, and any HDMI/VDMA-related kernel/device-tree status.
Scope: hardware boot verification only; no QSPI, NAND, eMMC, or other
  nonvolatile board storage writes.
Verification plan: insert TF card, SD boot, UART capture, static IP, ping,
  inspect dmesg for macb and VDMA/video nodes.
Board action: boot generated image from TF card.
Evidence target: docs/reports/petalinux-vdma-hdmi-boot-verify.md
Closure criteria: generated image boots and preserves Ethernet ping, or the
  report captures the boot failure root evidence.
Highest-risk assumption this cycle falsifies:
  The project-built image preserves the board's known-good Linux Ethernet path
  while using our VDMA HDMI hardware description.
Cheapest alternative way to falsify the same assumption:
  Boot without HDMI validation first; if UART or Ethernet fails, stop before
  debugging the video stack.
```
