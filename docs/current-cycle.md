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

## Recently Closed Cycle

```text
Cycle ID: petalinux-wsl-install-2018.3
Result: PASSED. PetaLinux 2018.3 is installed in WSL Ubuntu 22.04 at
  /opt/petalinux-v2018.3. Core commands are available after sourcing
  settings.sh in a clean non-root petalinux user environment.
Evidence: docs/reports/petalinux-wsl-install-2018.3-2026-06-29.md
Board action: none; host tooling only.
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
Cycle ID: petalinux-vdma-hdmi-minimal-project
Objective: create the first minimal PetaLinux project from the VDMA HDMI
  hardware design and build/boot an image that preserves the confirmed Ethernet
  path.
Scope: project creation, hardware-description import, minimal rootfs/kernel
  configuration, image build, TF-card boot, UART + Ethernet verification.
Verification plan: petalinux-create/config/build/package, boot from TF card,
  confirm UART login, eth0 link, static IP, and PC ping.
Board action: boot generated image from TF card only; do not write QSPI, NAND,
  eMMC, or other nonvolatile board storage.
Evidence target: docs/reports/petalinux-vdma-hdmi-minimal-project.md
Closure criteria: generated image boots, eth0 works at least as well as the
  official Linux route-gate image, and the report records build commands and
  residual VDMA/HDMI risks.
Highest-risk assumption this cycle falsifies:
  A project-built PetaLinux 2018.3 image can reproduce the board's known-good
  Linux Ethernet path while using our VDMA HDMI hardware description.
Cheapest alternative way to falsify the same assumption:
  Before a full image build, create/configure the project and inspect generated
  device tree / macb / PHY / clock nodes against the official boot log and board
  facts. If the hardware import cannot preserve Ethernet, stop before a full
  build.
```
