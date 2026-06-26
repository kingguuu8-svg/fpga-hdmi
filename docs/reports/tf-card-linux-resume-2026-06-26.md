# TF-Card Linux Resume Plan

Date: 2026-06-26

## Status

The first-stage network-video mainline is paused because no TF card is
available. Do not continue hand-written RGMII bridge timing work while waiting
for the card.

## Route Gate

Run one decisive experiment when the TF card arrives:

```text
Official vendor Linux image boots from TF card
-> board Ethernet comes up over the PL-side RTL8211E path
-> PC can ping the board
```

This gate decides whether the project should continue on a Linux/socket route
or fall back to a baremetal official-IP route.

## Required Local Inputs

Already identified local image archive:

```text
C:/Users/中二哲人/Downloads/Smart_ZYNQ_SP2_LINUX_ALL_TEST_20240906.zip
```

The archive was previously inspected and contains:

```text
BOOT.BIN
image.ub
```

Expected board-side boot medium:

```text
microSD / TF card, FAT32 boot partition
```

## Preparation Before Card Arrives

Keep these project facts stable:

```text
PC direct Ethernet address: 192.168.1.2/24 on interface "以太网 2"
Baremetal board default address: 192.168.1.10
Known board MAC in Xilinx lwIP examples: 00:0a:35:00:01:02
HDMI capture device: DirectShow index 1 when available
UART: COM16 observed during the latest run
```

Do not treat these as Linux image defaults. Re-check Linux UART output, IP
address, and MAC after boot.

## Resume Procedure

1. Format the TF card with a FAT32 boot partition.
2. Copy `BOOT.BIN` and `image.ub` from the official Linux all-test archive to
   the boot partition.
3. Set the board boot mode for TF/SD boot according to the board manual.
4. Connect UART and Ethernet.
5. Power-cycle the board and capture UART boot output.
6. Identify the Linux IP address from UART logs, DHCP lease table, or ARP scan.
7. From the PC, ping the board IP.
8. Record exact commands, UART log, PC route, ARP entry, ping result, and any
   Ethernet LEDs observed.

## Decision

Outcome A: ping works.

```text
Proceed with Linux/socket MVP:
PC UDP/TCP sender -> Linux userspace receiver -> DDR/framebuffer write
-> VDMA HDMI output.
Retire the hand-written baremetal RGMII bridge as a debug-only dead end.
```

Outcome B: ping fails.

```text
Do not return immediately to video work.
Debug the physical/driver layer using Linux evidence first:
dmesg, ip addr, ethtool if available, PHY link status, route, ARP, and ping.
Only if Linux confirms PHY/RGMII failure should PL ILA/RGMII capture become
the next action.
```

## Baremetal Fallback If Linux Is Not Usable

If Linux cannot be used after the route gate, do not continue with the
hand-written RGMII bridge by default. The fallback is:

```text
Restore the official Xilinx gmii_to_rgmii IP from the official PS EMIO NET
reference, prove one echo/ping/UDP packet first, then layer the video receiver
back in at the smallest useful frame size.
```

The current VDMA/RGB888 software path remains the intended output path:

```text
PC UDP RGB888 -> PS DDR buffer -> VDMA framebuffer at 0x01100000
-> VDMA MM2S -> HDMI
```

## Evidence Targets

Commit concise results to:

```text
docs/reports/
docs/current-cycle.md
docs/cycle-log.md
docs/boards/lookup-log.md
docs/boards/hellofpga-smart-zynq-sl.md
```

Raw logs and captures should remain under:

```text
build/reports/
build/eth-ps-pl-hdmi-pass-through/
```
