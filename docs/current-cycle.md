# Current Cycle

Status: no active implementation cycle is open.

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
Cycle ID: ethernet-video-userspace-receiver
Result: PASSED. A Linux userspace ARM receiver now accepts the project UDP
  RGB888 frame protocol on port 5005, assembles a complete 800x600 frame,
  maps protocol RGB into the actual /dev/fb0 channel byte order, and writes the
  frame to the proven VDMA/DRM HDMI framebuffer. PC sent one rgb-stripes frame
  as 1200 UDP packets; board log showed packets=1200 dropped=0 and HDMI
  capture validation returned HDMI_CAPTURE_OK.
Evidence: docs/reports/ethernet-video-userspace-receiver.md
Board action: ran a userspace binary from /tmp after downloading it over
  Ethernet, sent UDP from the PC, and captured HDMI. No Vivado rebuild, no
  PetaLinux rebuild, no JTAG programming, and no QSPI, NAND, eMMC, or other
  board flash writes.

Cycle ID: hdmi-linux-fixed-mode-connector
Result: PASSED. Linux now exposes a connected fixed-mode HDMI connector,
  /dev/dri/card0, and /dev/fb0. The VDMA DMA-decode failure was traced to a
  Linux CMA allocation outside the official VDMA DDR window documented in
  docs/boards/hellofpga-smart-zynq-sl.md; moving CMA inside that window removed
  VDMA errors and flip timeouts. A userspace /dev/fb0 write changed HDMI from
  the Linux login console to a deterministic three-stripe image, and automated
  HDMI capture validation passed.
Evidence: docs/reports/hdmi-linux-fixed-mode-connector.md
Board action: replaced image.ub on the TF-card FAT boot partition via board
  Linux wget over Ethernet, retained backups, rebooted from TF card, wrote a
  test frame through /dev/fb0, and captured HDMI. No JTAG programming, QSPI,
  NAND, eMMC, or other board nonvolatile storage writes.

Cycle ID: hdmi-linux-display-stack
Result: PARTIAL. The project image now enables Xilinx PL display DRM
  (CONFIG_DRM_XLNX=y, CONFIG_DRM_XLNX_PL_DISP=y), boots from the TF card, and
  exposes /dev/dri/card0. HDMI capture still sees stable 800x600 color bars.
  The image is not yet Linux-controllable because DRM has no connector/mode
  provider: /dev/fb* is absent, /sys/class/drm/card0 has no status/modes/enabled
  files, and dmesg says "[drm] Cannot find any crtc or sizes".
Evidence: docs/reports/hdmi-linux-display-stack.md
Board action: replaced image.ub on the TF-card FAT boot partition via board
  Linux wget over Ethernet, backed up the old image.ub on the same partition,
  rebooted from TF card, and captured UART/HDMI evidence. No JTAG programming,
  QSPI, NAND, eMMC, or other nonvolatile board storage writes.

Cycle ID: petalinux-vdma-hdmi-minimal-project
Result: PASSED. The VDMA HDMI hardware description was made Linux-consumable by
  connecting VDMA MM2S/S2MM interrupts to PS IRQ_F2P. PetaLinux 2018.3 built
  image.ub in the Ubuntu 18.04 chroot, packaged BOOT.BIN, and copied BOOT.BIN +
  image.ub to the ZYNQBOOT TF-card partition with matching SHA256 hashes.
Evidence: docs/reports/petalinux-vdma-hdmi-minimal-project.md
Board action: TF-card file write only; no board boot or nonvolatile flash write.

Cycle ID: vdma-boot-probe-verify
Result: PASSED. The project-built TF-card image boots to Linux userspace,
  accepts root/root over UART, eth0 links at 1000/Full and pings from the PC
  with 0% loss, and the VDMA node binds to the xilinx-vdma platform driver.
  No /dev/dri or /dev/fb* node appears, so HDMI/display output remains a
  separate device-tree/display-stack follow-up.
Evidence: docs/reports/vdma-boot-probe-verify.md
Board action: booted generated image from TF card only; no JTAG programming,
  QSPI, NAND, eMMC, or other nonvolatile board storage writes.
```

## Active Cycle

No active implementation cycle is open.

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
Project Linux exposes a connected DRM HDMI output and /dev/fb0.
Linux userspace framebuffer writes pass automated HDMI capture validation.
Project Linux userspace UDP receiver receives a complete 800x600 RGB888 frame
and updates the physical HDMI output through /dev/fb0.
```

Retired dead end:

```text
Project baremetal PC-to-board UDP RX through the hand-written RGMII bridge:
rx=0, rxfcs rising, no frames reach lwIP. Root cause confirmed by the Linux
ping result as the hand-written bridge BUFIO/BUFG crossing, not the physical
layer. Do not resume this work.
```

## Next Cycle Direction

The first-stage pass-through MVP is closed. Open the next cycle only after
choosing the stage-2 focus: sustained low-FPS video streaming, UART-controlled
demo state, or the first board-side visual effect. Do not combine all three in
one cycle.
