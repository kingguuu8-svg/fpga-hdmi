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

Exception: a TF-card Linux ping experiment is now a route gate, not a media
stack milestone. When a TF card is available, boot the official vendor Linux
image and verify whether the board can be pinged over the PL-side RTL8211E
network path. This decides whether to continue on a Linux/socket route or fall
back to a baremetal official-IP route.

## Post-MVP Direction

After the MVP is stable, move toward a network-unified board control model:

```text
Phase A:
  Route gate: official Linux image boots and responds to ping over Ethernet

Phase B:
  UART control + Ethernet video + HDMI output

Phase C:
  Same command protocol over TCP/UDP
  UART remains as fallback

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

MVP is complete only when all of the following are true:

```text
1. PC can send a known 800x600 RGB888 test video frame stream over Ethernet.
2. Board receives frames and updates a DDR-backed frame buffer.
3. VDMA/PL consumes the frame buffer and displays it through HDMI.
4. HDMI capture shows the same original input frame with no effects.
5. JTAG can still rebuild/program/recover the board.
6. A run report records commands, versions, interface status, and evidence.
7. The later effects/control stage is opened only after this pass-through
   criterion is met.
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
