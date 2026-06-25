# Project Roadmap

## Project Definition

Build a Zynq-7020 network video effects system.

The board receives video frames from the PC over Ethernet, applies realtime
video effects on the board, and outputs the result over HDMI. Runtime control
uses UART first, with a later path to reuse the same command protocol over
Ethernet.

## MVP Scope

The MVP has three independent links:

```text
Video input:
  PC -> Ethernet -> Zynq PS -> DDR frame buffer -> PL video pipeline

Control:
  PC -> UART/USB-serial -> Zynq control endpoint -> PL control registers

Video output:
  PL video pipeline -> HDMI -> PC capture/display
```

MVP target:

```text
Input video: 320x240 RGB565, UDP, 15-30 fps
Output video: 640x480 HDMI
Effects: PIP, move, scale, rotate/rotate-like transform where feasible
Control: UART command protocol with deterministic fallback behavior
Download/debug: keep USB-JTAG as the reliable development recovery path
```

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

These are explicitly out of the MVP:

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

## Post-MVP Direction

After the MVP is stable, move toward a network-unified board control model:

```text
Phase A:
  UART control + Ethernet video + HDMI output

Phase B:
  Same command protocol over TCP/UDP
  UART remains as fallback

Phase C:
  Board reachable through LAN router
  PC controls board by IP address

Phase D:
  Linux FPGA Manager / PCAP based remote bitstream update
  JTAG remains recovery path

Phase E:
  Optional USB RNDIS/ECM fallback
  USB behaves as a network interface, not as a custom video protocol
```

## Acceptance Criteria

MVP is complete only when all of the following are true:

```text
1. PC can send a known 320x240 RGB565 test video stream over Ethernet.
2. Board receives frames and updates a DDR-backed frame buffer.
3. PL consumes the frame buffer and displays it through HDMI.
4. UART commands can change at least one visible effect parameter.
5. HDMI capture shows the changed output.
6. JTAG can still rebuild/program/recover the board.
7. A run report records commands, versions, interface status, and evidence.
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
Ethernet IP: currently APIPA; static IP plan still needed
```

