# HelloFPGA Smart ZYNQ SL Board Reference

Use this file as the first lookup point for board facts. Do not re-read the
schematic unless this file is missing a required fact or marks it as unverified.

## Evidence Sources

- Official board page: `http://www.hellofpga.com/index.php/2023/05/10/smart-zynq-sl/`
- Local schematic copy: `build/reports/SmartZynq_SL_Schematic_V1d3_20241005.pdf`
- Local extracted text: `build/reports/SmartZynq_SL_Schematic_V1d3_20241005.txt`
- Active Vivado profile: `boards/hellofpga-smart-zynq-sl-7020.tcl`
- Local hardware reports: `build/reports/environment.json`,
  `build/reports/hardware.yml`, `build/reports/interface-check-2026-06-25.md`

`build/` is ignored by git. If a schematic-derived fact is promoted into source
constraints, copy the concise fact into this document or the board profile.

## Board Identity

| Item | Value | Status |
| --- | --- | --- |
| Board | HelloFPGA Smart ZYNQ SL | confirmed |
| FPGA | XC7Z020 | confirmed by JTAG |
| Vivado part | `xc7z020clg484-1` | used by active profile |
| Active profile | `boards/hellofpga-smart-zynq-sl-7020.tcl` | tracked |
| JTAG target | APU + `xc7z020` | confirmed |

## Existing Constraint-Ready Pins

These facts are already encoded in the active board profile and may be used by
build scripts.

| Function | Port/net | FPGA pin | I/O standard | Notes |
| --- | --- | --- | --- | --- |
| 50 MHz clock | `clk` | `M19` | `LVCMOS33` | `clock_period_ns = 20.000` |
| LED1 | `led[0]` | `P20` | `LVCMOS33` | active-high |
| LED2 | `led[1]` | `P21` | `LVCMOS33` | active-high |
| KEY1 | `key[0]` | `K21` | `LVCMOS33` | active-low, currently not used by HDMI top |
| KEY2 | `key[1]` | `J20` | `LVCMOS33` | active-low, currently not used by HDMI top |
| HDMI clock P | `hdmi_clk_p` | `N19` | `TMDS_33` | N side inferred by differential pair |
| HDMI data P0 | `hdmi_d_p[0]` | `M21` | `TMDS_33` | N side inferred by differential pair |
| HDMI data P1 | `hdmi_d_p[1]` | `L21` | `TMDS_33` | N side inferred by differential pair |
| HDMI data P2 | `hdmi_d_p[2]` | `J21` | `TMDS_33` | N side inferred by differential pair |

## Ethernet PHY

| Item | Value | Status |
| --- | --- | --- |
| PHY device | `RTL8211E-VB-CG` | confirmed from schematic text |
| Board block | `1G GIGE PHY (Rtl8211e)` | confirmed |
| Interface type | RGMII-class signal set | inferred from net names |
| PHY side | PL-side nets, not direct PS MIO | confirmed by board discussion and schematic net names |

Confirmed Ethernet nets:

```text
ETH_TXD0
ETH_TXD1
ETH_TXD2
ETH_TXD3
ETH_TXCTL
ETH_TXC
ETH_RXD0
ETH_RXD1
ETH_RXD2
ETH_RXD3
ETH_RXCTL
ETH_RXC
ETH_MDIO
ETH_MDC
ETH_RST
ETH_INT
```

Constraint status:

```text
Do not write Ethernet XDC from this document yet.
The net names are confirmed, but the package-pin mapping must still be
cross-checked from the schematic drawing or an official constraint file.
```

MVP implication:

```text
Ethernet PHY -> PL pins -> PS GEM through EMIO -> PS baremetal lwIP
```

Do not implement a pure RTL UDP stack for the first pass-through cycle unless
the PS GEM EMIO path is proven impossible.

## UART

| Item | Value | Status |
| --- | --- | --- |
| UART nets | `PL_UART_TX`, `PL_UART_RX` | confirmed from schematic text |
| USB-UART nets | `CH340_UART_RX`, `CH340_UART_TX` | confirmed from schematic text |
| Runtime COM port | `COM27` observed previously | environment-dependent |
| Physical side | PL-side UART nets | confirmed by board discussion and schematic net names |

Constraint status:

```text
Do not write UART XDC from this document yet.
The net names are confirmed, but the exact package pins must still be mapped.
```

Preferred MVP connection:

```text
UART pins -> AXI UARTLite in PL -> PS baremetal stdout/commands
```

This keeps UART debugging available without assuming PS MIO UART pins.

## DDR / PS

| Item | Value | Status |
| --- | --- | --- |
| DDR controller | PS DDR controller | confirmed |
| DDR part text | `MT41K256M16TW-107` | confirmed from schematic text |
| PS DDR nets | `PS_DDR_DQ0..DQ31` and related address/control nets | confirmed |
| DDR usable range in default PS7 IP | `0x00100000` to `0x1fffffff` | Vivado default inspection, not board tuned |

Important caution:

```text
The PS7 DDR timing/preset is not yet board-verified in source.
Do not assume Vivado default DDR configuration is valid for the board.
Find an official PS7 preset, exported XSA/HDF, or working HelloFPGA reference
before treating PS DDR initialization as verified.
```

## Current Interface Baseline

Previously observed connected interfaces:

| Interface | Observed status |
| --- | --- |
| JTAG | XSCT sees APU and `xc7z020` |
| HDMI capture | USB Video adapter opens and reads 640x480 frames |
| UART | `COM27` and `COM16` opened at 115200 8N1 in prior checks |
| Ethernet physical link | PC Realtek adapter up at 1 Gbps, APIPA before static IP setup |

Use `build/reports/interface-check-2026-06-25.md` for the detailed historical
probe output.

## First-Stage Architecture

The agreed first-stage implementation chain is:

```text
PC fixed video/static frame
  -> UDP over Ethernet
  -> RTL8211E PHY on PL pins
  -> PL RGMII/EMIO wiring
  -> PS GEM + baremetal lwIP
  -> PS writes DDR frame buffer
  -> PL reads DDR frame buffer
  -> HDMI raw pass-through
  -> PC HDMI capture
```

The first-stage success criterion is:

```text
The original input image/video frame returns through HDMI without PIP, rotation,
scale, filter, test stripes, random blocks, or other effects.
```

## Open Board Facts Needed Before Hardware Build

The following facts block a correct first-stage hardware build:

1. Ethernet package-pin mapping for all `ETH_*` nets.
2. UART package-pin mapping for `PL_UART_TX` and `PL_UART_RX`.
3. Board-verified PS7 DDR configuration or a working exported hardware design.
4. Exact PS GEM EMIO RGMII clock/reset wiring required by Vivado 2018.3.

Do not guess these values. If no official source is found, create a small
pin-audit report before editing XDC or PS7 block design constraints.

