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
Cycle ID: dashboard-truthful-loop-validation
Result: PASSED. Corrected the dashboard closed-loop demo so the input preview
  is generated from the exact sender source, start-stream schedules HDMI
  capture asynchronously instead of blocking the button response, and the
  board-live helper requires dynamic HDMI sample hashes. The connected board
  wrote 12 generated frames, 14400 UDP packets, dropped=0; HDMI capture on
  DirectShow index 1 passed non-black validation and saved six samples with
  five unique hashes.
Evidence: docs/reports/dashboard-truthful-loop-validation.md
Board action: ran a Linux userspace receiver from /tmp, sent generated UDP
  frames from the PC through Dashboard, and captured HDMI. No Vivado/PetaLinux/
  JTAG/TF-card/flash action.

Cycle ID: dashboard-board-live-loop
Result: PASSED. Added a displayable board-live loop helper. It builds/deploys
  the Linux receiver to /tmp, starts it with /tmp/video_ctl, starts the
  dashboard, triggers Dashboard `start-stream`, sends five generated RGB888
  frames, verifies five VIDEO_UDP_FRAME_WRITTEN markers and
  VIDEO_UDP_RECEIVER_DONE frames=5 packets=6000 dropped=0, and validates HDMI
  capture with non-black mean_luma=136.39. The captured image shows the
  generated demo frame.
Evidence: docs/reports/dashboard-board-live-loop.md
Board action: ran a Linux userspace receiver from /tmp, sent UDP frames from
  the PC through Dashboard, and captured HDMI. No Vivado/PetaLinux/JTAG/flash
  action.

Cycle ID: dashboard-hdmi-capture-timeout-fix
Result: PASSED. Real dashboard `start-stream` initially hit
  HDMI_CAPTURE_TIMEOUT because the dashboard timeout was shorter than the
  DirectShow capture latency. The timeout is now at least 90 seconds and the
  default preview capture frame count is 8. Retest returned HDMI_CAPTURE_OK,
  capture_status=ok, and image_exists=true.
Evidence: docs/reports/dashboard-hdmi-capture-timeout-fix.md
Board action: PC-side dashboard process and HDMI capture only. No
  Vivado/PetaLinux/JTAG/flash action.

Cycle ID: dashboard-hdmi-capture-binding
Result: PASSED. Added HDMI preview capture binding to the dashboard. The
  capture tool now supports validation-profile none for preview captures.
  `start-stream` launches the sender and then attempts HDMI capture;
  `capture-output` refreshes HDMI manually. Live capture opened DirectShow
  device index 0 and wrote latest.png, but the frame was near black
  (mean_luma=0.05), so meaningful board output still depends on receiver
  readiness.
Evidence: docs/reports/dashboard-hdmi-capture-binding.md
Board action: PC-side HDMI capture only. No Vivado/PetaLinux/JTAG/flash action.

Cycle ID: dashboard-live-minimal-controls
Result: PASSED. The dashboard UI is now a plain functional view with no
  decorative background, gradients, shadows, or card styling. Start stream
  launches a real dashboard-owned demo sender subprocess; Stop stream
  terminates it. Self-test received a real localhost ZVID UDP packet from the
  sender and verified UART actions return UART_NOT_CONFIGURED when no UART port
  is provided.
Evidence: docs/reports/dashboard-live-minimal-controls.md
Board action: none. UART live binding was implemented but not exercised against
  the connected board in this automated cycle.

Cycle ID: dashboard-control-integration
Result: PASSED. The PC dashboard now exposes `/api/actions` and `/api/action`
  plus active control buttons. Self-test posted six dry-run actions covering
  sender start/stop, UART/FIFO pause/resume/status semantics, and effect launch
  semantics. Final state recorded stream_state=stopped, receiver_paused=false,
  selected_effect=invert, and no camera/custom-file input.
Evidence: docs/reports/dashboard-control-integration.md
Board action: none. PC-side dry-run dashboard action surface only.

Cycle ID: fixed-demo-video-sender
Result: PASSED. Added a fixed built-in deterministic RGB888 dynamic video
  source and UDP sender for the dashboard MVP. Self-test proved generated frame
  size, dynamic frame difference, localhost UDP packetization, 30/30 received
  packets, full payload byte count, and stable frame id. Parser inspection
  confirmed there is no camera/webcam/file input option. The result explicitly
  keeps camera/webcam input disabled and custom-file input deferred after MVP.
Evidence: docs/reports/fixed-demo-video-sender.md
Board action: none. PC-side fixed demo-video sender only.

Cycle ID: visual-dashboard-scaffold
Result: PASSED. Added a Python-stdlib PC dashboard scaffold with three visual
  regions: generated input preview, FPGA HDMI-output preview slot, and
  function-control/log panel skeleton. Self-test fetched the HTML, state JSON,
  generated input SVG, and output placeholder SVG. The state explicitly reports
  camera_enabled=false and custom_file_enabled=false.
Evidence: docs/reports/visual-dashboard-scaffold.md
Board action: none. PC dashboard scaffold only.

Cycle ID: first-board-side-effect
Result: PASSED. The Linux receiver now supports a board-side RGB invert effect.
  PC sent the deterministic non-camera rgb-stripes UDP frame; board logs showed
  VIDEO_UDP_FRAME_WRITTEN frame_id=200 effect=invert and
  VIDEO_UDP_RECEIVER_DONE frames=1 packets=1200 dropped=0. HDMI capture using
  the inverted-rgb-stripes profile returned HDMI_CAPTURE_OK.
Evidence: docs/reports/first-board-side-effect.md
Board action: ran a userspace binary from /tmp, sent one generated UDP frame
  from the PC, and captured HDMI for output verification. No camera/webcam
  video input, no Vivado rebuild, no PetaLinux rebuild, no JTAG programming,
  and no board flash writes.

Cycle ID: uart-control-endpoint
Result: PASSED. The Linux receiver now supports a FIFO control endpoint that
  can be driven from the UART shell. UART `pause` caused a complete UDP frame
  to log VIDEO_UDP_FRAME_SKIPPED_PAUSED instead of writing /dev/fb0; UART
  `resume` and `status` were accepted, the next UDP frame was written, and HDMI
  capture returned HDMI_CAPTURE_OK.
Evidence: docs/reports/uart-control-endpoint.md
Board action: ran a userspace binary from /tmp, wrote control commands through
  the UART shell to /tmp/video_ctl, sent UDP frames from the PC, and captured
  HDMI. No Vivado rebuild, no PetaLinux rebuild, no JTAG programming, and no
  board flash writes.

Cycle ID: sustained-low-fps-stream
Result: PASSED. The Linux UDP receiver handled a five-frame 800x600 RGB888
  low-FPS stream. PC sent 6000 UDP packets; board logs showed five
  VIDEO_UDP_FRAME_WRITTEN markers and VIDEO_UDP_RECEIVER_DONE frames=5
  packets=6000 dropped=0. HDMI capture after the stream returned
  HDMI_CAPTURE_OK.
Evidence: docs/reports/sustained-low-fps-stream.md
Board action: ran a userspace binary from /tmp after downloading it through a
  one-shot Ethernet file server, sent UDP frames from the PC, and captured
  HDMI. No Vivado rebuild, no PetaLinux rebuild, no JTAG programming, and no
  board flash writes.

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
Project Linux exposes a connected DRM HDMI output and /dev/fb0.
Linux userspace framebuffer writes pass automated HDMI capture validation.
Project Linux userspace UDP receiver receives a complete 800x600 RGB888 frame
and updates the physical HDMI output through /dev/fb0.
Project Linux userspace UDP receiver handles a five-frame low-FPS stream with
6000 UDP packets, dropped=0, and HDMI capture validation after the stream.
Project Linux receiver accepts UART-shell-driven pause/resume/status commands
through a FIFO control endpoint without breaking UDP receive or HDMI output.
Project Linux receiver applies a board-side RGB invert effect to generated PC
UDP input and HDMI capture validates the inverted output.
PC dashboard scaffold exposes generated input preview, FPGA output preview,
and function-control/log panel regions without camera or custom-file input.
PC fixed demo sender generates deterministic dynamic RGB888 frames and
packetizes them through the existing UDP protocol without camera or custom-file
input.
PC dashboard control API exposes tested dry-run sender, UART/FIFO, and effect
actions without camera or custom-file input.
PC dashboard is now minimal and `start-stream`/`stop-stream` control a real
local demo sender subprocess. UART/FIFO controls are wired to the UART helper
but require a ready board receiver FIFO.
PC dashboard `start-stream` and `capture-output` call HDMI preview capture and
refresh the output panel. Current live preview capture opened the adapter but
returned a near-black frame, so board receiver readiness remains separate.
Real dashboard `start-stream` now returns HDMI_CAPTURE_OK and image_exists=true
after the capture timeout fix; the captured frame is still near black.
Dashboard board-live loop now deploys/starts the receiver, drives Dashboard
`start-stream`, receives/writes five generated frames with dropped=0, and
captures a non-black generated HDMI image.
```

Retired dead end:

```text
Project baremetal PC-to-board UDP RX through the hand-written RGMII bridge:
rx=0, rxfcs rising, no frames reach lwIP. Root cause confirmed by the Linux
ping result as the hand-written bridge BUFIO/BUFG crossing, not the physical
layer. Do not resume this work.
```

## Next Cycle Direction

No active implementation cycle is open. A natural next cycle is dashboard
control demonstration: exercise pause/resume through `/tmp/video_ctl`, then add
an effect launch/switch flow suitable for a recorded demo.
