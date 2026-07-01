# Project Roadmap

## Project Definition

Build a Zynq-7020 network video effects system.

The board receives video frames from the PC over Ethernet, applies realtime
video effects on the board, and outputs the result over HDMI. Runtime control
uses UART first, with a later path to reuse the same command protocol over
Ethernet.

## MVP Scope

The current first-stage MVP is a pass-through proof, not the final effects
demo. It has three independent links:

```text
Video input:
  PC -> Ethernet -> Zynq PS -> DDR frame buffer -> PL video pipeline

Control:
  PC -> UART/USB-serial -> Zynq control endpoint -> PL control registers

Video output:
  PL video pipeline -> HDMI -> PC capture/display
```

Current first-stage target:

```text
Input video: 800x600 RGB888, UDP, low frame rate acceptable for proof
Output video: 800x600 HDMI through VDMA MM2S + v_axi4s_vid_out + rgb2dvi
Effects: none in stage 1; original frame must be returned first
Control: UART command protocol remains the first fallback after video closes
Download/debug: keep USB-JTAG as the reliable development recovery path
```

Video source policy:

```text
Do not use a camera or webcam as the project video input source.
Use deterministic PC-generated frames first. A fixed preselected demo video
file is allowed after MVP, but user-selectable custom files are not part of the
MVP.
HDMI capture devices may be used only as output verification instruments, not
as input video sources.
```

The old 320x240/640x480 RGB565 custom-framebuffer-reader route is retired for
the active stage-1 path. It remains only as historical code until deleted or
archived; it must not be used as completion evidence for this MVP.

## Why This Boundary

Ethernet video input requires the PS side because the board must receive
packets, buffer frames, and expose frame data to PL. The MVP should prove that
path without also trying to remove JTAG, replace UART, or boot entirely from the
network.

Keeping UART as the first control channel is intentional:

```text
UART is simple to debug
UART remains available when the network stack is broken
The command protocol can later be transported over TCP/UDP unchanged
```

Keeping USB-JTAG is also intentional:

```text
It is the recovery and programming path during development
Network boot/update can be added after PS software is stable
```

## Non-MVP Items

These are explicitly out of the first-stage pass-through MVP:

```text
Replacing the downloader with Ethernet
Wireless LAN development through a router
Remote bitstream update through Linux FPGA Manager
USB gadget video transport
Compressed video decode such as H.264
High-definition raw video input
Full Linux media stack / GStreamer pipeline
```

They are valid later milestones, not first-stage requirements.

The TF-card Linux ping experiment was the route gate, not a media-stack
milestone. It passed on 2026-06-29: the official vendor Linux image booted from
TF card and the PC pinged the board over the PL-side RTL8211E network path with
0% loss. The project now continues on the Linux/socket route.

## Post-MVP Direction

After the MVP is stable, move toward a network-unified board control model:

```text
Phase A:
  DONE - official Linux image boots and responds to ping over Ethernet

Phase B:
  DONE - PetaLinux project + Linux socket receiver + Ethernet video +
  HDMI output
  Fixed-mode HDMI gate: PASSED. Linux exposes a connected DRM output and
  userspace framebuffer writes are visible through HDMI capture.
  UDP framebuffer gate: PASSED. A PC-sent RGB888 frame reaches the Linux
  userspace receiver, /dev/fb0, and HDMI capture.

Phase C:
  IN PROGRESS - control path
  UART fallback gate: PASSED. The Linux receiver accepts pause/resume/status
  through a FIFO endpoint driven from the UART shell.
  First effect gate: PASSED. The Linux receiver applies a board-side RGB invert
  effect to generated PC UDP input; HDMI validates inverted output.
  Dashboard scaffold gate: PASSED. The PC dashboard has input preview, FPGA
  output preview, and control/log panel regions. Custom file input remains
  deferred after MVP.
  Fixed demo-video sender gate: PASSED. The PC can generate deterministic
  dynamic RGB888 frames and packetize them through the existing UDP protocol.
  Dashboard control-integration gate: PASSED. The PC dashboard exposes a
  tested dry-run action API for sender start/stop, UART/FIFO control semantics,
  and effect launch semantics. Live board binding remains a later cycle.
  Dashboard minimal live-control gate: PASSED. The dashboard UI is reduced to a
  plain functional view, and start/stop controls a real local demo sender
  subprocess. UART/FIFO controls are bound to the existing UART helper but need
  a ready board receiver FIFO to succeed.
  Dashboard HDMI-capture binding gate: PASSED. The dashboard can call the
  existing HDMI capture tool from start-stream or capture-output and refresh
  the output panel. The latest preview capture opened the adapter but saw a
  near-black frame, so board receiver/display readiness remains the next live
  issue.
  Dashboard board-live loop gate: PASSED. The helper deployed the board
  receiver, drove Dashboard `start-stream`, sent five generated RGB888 frames,
  wrote five frames to /dev/fb0 with dropped=0, and HDMI capture validated a
  non-black generated demo image.
  Dashboard truthful-loop validation gate: PASSED. The dashboard input preview
  now comes from the exact generated UDP source, stream/capture actions return
  asynchronously, and HDMI samples captured during the stream show dynamic
  output changes.
  Dashboard live pass-through preview gate: PASSED. The right panel now uses
  the live HDMI MJPEG return endpoint, and the board-live helper verified 80
  returned MJPEG frames with dynamic changes while the receiver wrote 12
  no-effect source frames with dropped=0.
  Dashboard color-block loop and UART audit gate: PASSED. The PC source is now
  full-screen sequential color blocks; the board-live helper classified the
  returned HDMI MJPEG stream as source colors, removed the Linux console cursor
  overlay, and verified Dashboard UART pause/resume/status responses from the
  running receiver.
  Unified pass-through validator calibration gate: PASSED. The reusable trace
  validator now rejects black/no-frame output, wrong frame order, missing
  frames, wrong content, and excessive latency in synthetic calibration. The
  next hardware loop must use this already-committed validator for 15 fps
  frame_id correspondence, latency, and drop-rate evidence.
  Later: carry the same command semantics over TCP/UDP.

Phase D:
  Board reachable through LAN router
  PC controls board by IP address

Phase E:
  Linux FPGA Manager / PCAP based remote bitstream update
  JTAG remains recovery path

Phase F:
  Optional USB RNDIS/ECM fallback
  USB behaves as a network interface, not as a custom video protocol
```

## Acceptance Criteria

MVP is complete. The completed acceptance facts are:

```text
1. PC sent a known 800x600 RGB888 frame over Ethernet.
2. Board received the frame and updated the Linux DDR-backed framebuffer.
3. VDMA/PL consumed the framebuffer and displayed it through HDMI.
4. HDMI capture showed the same original test pattern with no effects.
5. JTAG remains the reliable rebuild/program/recovery path.
6. Run reports record commands, versions, interface status, and evidence.
7. Later effects/control work is now allowed to open as stage 2.
```

## Current Interface Baseline

The currently known good physical arrangement is recorded in:

```text
build/reports/interface-check-2026-06-25.md
```

Important current facts:

```text
JTAG restored: XSCT sees APU and xc7z020
HDMI restored: USB Video VID_534D PID_2109 opens as DirectShow index 1
UART available: COM27 and COM16 open at 115200 8N1
Ethernet physical link: Realtek adapter Up at 1 Gbps
Ethernet IP: direct-link Windows interface uses 192.168.1.2/24 for current tests
```
