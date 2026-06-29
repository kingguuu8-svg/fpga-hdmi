# HelloFPGA Smart ZYNQ SL Board Reference

Use this file as the first lookup point for board facts. Do not re-read the
schematic unless this file is missing a required fact or marks it as unverified.
For chronological lookup history and sources not yet promoted into stable facts,
use `docs/boards/lookup-log.md`.

## Evidence Sources

- Official board page: `http://www.hellofpga.com/index.php/2023/05/10/smart-zynq-sl/`
- Board lookup log: `docs/boards/lookup-log.md`
- Local schematic copy: `build/reports/SmartZynq_SL_Schematic_V1d3_20241005.pdf`
- Local extracted text: `build/reports/SmartZynq_SL_Schematic_V1d3_20241005.txt`
- Active Vivado profile: `boards/hellofpga-smart-zynq-sl-7020.tcl`
- Local hardware reports: `build/reports/environment.json`,
  `build/reports/hardware.yml`, `build/reports/interface-check-2026-06-25.md`

`build/` is ignored by git. If a schematic-derived fact is promoted into source
constraints, copy the concise fact into this document or the board profile.

## Fact Promotion Rule

Use this document for stable board facts only. Use
`docs/boards/lookup-log.md` for chronological source notes, downloaded-project
paths, and facts that still need extraction or cross-checking.

Before checking any board source again:

1. Check this document for promoted facts.
2. Check `docs/boards/lookup-log.md` for prior source lookups.
3. Re-open the external source only if the needed fact is missing, unverified,
   or contradicted.

When a new fact is promoted here, keep it concise and implementation-facing:
pin, clock, voltage, IP parameter, software setting, verified interface status,
or a decision that directly affects the FPGA/PS build. Keep source chronology,
download locations, and unresolved raw notes in `docs/boards/lookup-log.md`.

Promoted facts should be written in a form that can answer a future engineering
question without reopening the original source:

| Required field | Meaning |
| --- | --- |
| Topic | Interface, pin group, clock, IP block, voltage, software route, or test setup. |
| Reusable fact | The concrete value or decision to reuse. |
| Status | `confirmed`, `inferred`, `environment-dependent`, or `blocked`. |
| Source pointer | The lookup-log entry, local report path, or source-backed evidence. |
| Implementation impact | Which RTL, XDC, Tcl, software, or test decision this fact affects. |

## Quick Lookup Index

Use this section before re-opening any schematic, web page, Vivado project, or
hardware probe output.

| Topic | Current reusable fact | Detail section |
| --- | --- | --- |
| Board/part | HelloFPGA Smart ZYNQ SL, `xc7z020clg484-1` | [Board Identity](#board-identity) |
| PL clock/reset/LED/key/HDMI pins | 50 MHz `M19`, LEDs `P20/P21`, keys `K21/J20`, HDMI TMDS P pins `N19/M21/L21/J21` | [Existing Constraint-Ready Pins](#existing-constraint-ready-pins) |
| Ethernet physical route | RTL8211E RGMII pins are on PL; current next gate is official TF-card Linux ping before more baremetal bridge work | [Ethernet PHY](#ethernet-phy) |
| Ethernet official IP setup | PS ENET0 EMIO -> GMII-to-RGMII, PHY address `8`, internal IDELAY enabled | [Ethernet PHY](#ethernet-phy) |
| UART route | PL-side CH340 pins; official reference uses PS UART0 over EMIO at 115200 | [UART](#uart) |
| DDR/PS baseline | PS DDR3 config from official EMIO Ethernet project; HP0 is the source-backed PL DDR access path | [DDR / PS](#ddr--ps) |
| HDMI frame-buffer output | Official VDMA design reads RGB888 framebuffer from DDR and drives HDMI at 800x600; hardware control image passed | [HDMI / VDMA](#hdmi--vdma) |
| Connected PC interfaces | JTAG, HDMI capture, UART, and Ethernet were observed previously; re-probe before board runs | [Current Interface Baseline](#current-interface-baseline) |
| Accepted stage-1 chain | PC UDP RGB888 -> PS/Linux or PS fallback -> DDR VDMA framebuffer -> HDMI | [First-Stage Architecture](#first-stage-architecture) |
| Official reference examples | PS EMIO Ethernet, PL UDP loopback, PL/PS DDR interaction, VDMA HDMI color-bar | [Official Reference Examples](#official-reference-examples) |
| Still blocking facts | Whether official Linux can bring up the board Ethernet path and respond to ping | [Open Board Facts Needed Before Hardware Build](#open-board-facts-needed-before-hardware-build) |

## Lookup Workflow

For every future board-information lookup:

1. Search this quick index and the relevant section below.
2. Search `docs/boards/lookup-log.md` for raw source history and unresolved
   uncertainties.
3. Re-open external sources only when the fact is absent, contradicted, stale,
   or explicitly marked unverified.
4. Record the lookup in `docs/boards/lookup-log.md` using its template.
5. Promote only stable implementation facts back into this file.

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
| Package-pin mapping | see table below | confirmed from local schematic layout text |
| Official PS route | PS ENET0 over EMIO + GMII-to-RGMII IP | confirmed from HelloFPGA EMIO Ethernet article, pending project extraction |
| Official I/O standard | `LVCMOS33` for RGMII and MDIO | confirmed from official EMIO Ethernet project XDC |
| Official RGMII RX clock | 8.000 ns on `RGMII_0_rxc` | confirmed from official EMIO Ethernet project XDC |
| Official RGMII TX drive hint | `SLEW FAST` on TXD/TXCTL/TXC | confirmed from official EMIO Ethernet project XDC |
| GMII-to-RGMII PHY address | `8` | confirmed from official IP XCI |
| GMII-to-RGMII delay setup | internal IDELAY control enabled, TXC skew `0` | confirmed from official IP XCI |
| Runtime RTL8211E delay bits | extension page `0xa4`, register `0x1c` reported `0x8577`; RX delay and TX delay bits are both set | confirmed from stage-1 UART diagnostic |
| Runtime direction split (baremetal) | board-to-PC UDP heartbeat works; PC-to-board ping/ZVID UDP does not reach lwIP | confirmed from stage-1 UART and PC listener diagnostics; root cause is the hand-written bridge, see Linux row below |
| Runtime PHY loopback probe | BMCR loopback `0x1140 -> 0x5140` produced at least one GEM RX/RXBC count, but also an FCS count | diagnostic only |
| Official pure-PL UDP loopback | `17_PL_NET_TEST_Smart_ZYNQ_S` bit receives and echoes UDP on the connected board | passed on hardware |
| Official PL RX delay reference | custom `rgmii_to_gmii` uses `IDELAY_VALUE = 9` on RX data/control | confirmed from official UDP project |
| Official Linux network | `Smart_ZYNQ_SP2_LINUX_ALL_TEST` boots from TF card; `macb` driver brings up eth0 at 1000/Full, RX errors=0, TX errors=0; PC ping 192.168.1.10 = 4/4, 0% loss, <1ms | passed on connected hardware 2026-06-29; confirms physical path is good and baremetal RX failure is in the hand-written bridge |

Confirmed Ethernet net to package-pin mapping:

| Net | FPGA pin | Schematic signal |
| --- | --- | --- |
| `ETH_RST` | `H17` | `GPIO_H17` |
| `ETH_RXD0` | `A22` | `GPIO_A22_L15N` |
| `ETH_RXD1` | `A18` | `GPIO_A18_L10P` |
| `ETH_RXD2` | `A19` | `GPIO_A19_L10N` |
| `ETH_RXD3` | `B20` | `GPIO_B20_L13N` |
| `ETH_RXCTL` | `A21` | `GPIO_A21_L15P` |
| `ETH_RXC` | `B19` | `GPIO_B19_L13P` |
| `ETH_TXD0` | `E21` | `GPIO_E21_L17P` |
| `ETH_TXD1` | `F21` | `GPIO_F21_L23P` |
| `ETH_TXD2` | `F22` | `GPIO_F22_L23N` |
| `ETH_TXD3` | `G20` | `GPIO_G20_L22P` |
| `ETH_TXCTL` | `G22` | `GPIO_G22_L24N` |
| `ETH_TXC` | `D21` | `GPIO_D21_L17N` |
| `ETH_MDIO` | `H22` | `GPIO_H22_L24P` |
| `ETH_MDC` | `G21` | `GPIO_G21_L22N` |
| `ETH_INT` | `H18` | `GPIO_H18` |

Mapping evidence:

```text
build/reports/SmartZynq_SL_Schematic_V1d3_20241005-layout.txt
lines 203, 240-242, 271, 275, 288-289, 302-333
```

Constraint status:

```text
Ethernet package pins and LVCMOS33 I/O standard are now source-backed by the
schematic and official EMIO Ethernet project. The first-stage hardware design
must still reproduce the official PS ENET0 EMIO -> GMII-to-RGMII -> RGMII/MDIO
wiring and then add a verified PL DDR read path for HDMI.
```

Runtime RX caution:

```text
Do not treat RJ45 link lights or board-to-PC heartbeat as proof that
PC-to-board RX works. Current stage-1 evidence shows the PHY negotiates link and
the board transmits heartbeat packets to the PC, but PC-originated ping and
ZVID UDP packets do not reach lwIP. RTL8211E internal RX/TX delay bits are
already set, and disabling Windows Realtek offloads did not fix RX. PHY local
loopback proves the digital receive side is not completely inactive, but the
loopback sample also recorded FCS activity, so clean RX timing remains unproven.

However, the official pure-PL UDP loopback tutorial image
`17_PL_NET_TEST_Smart_ZYNQ_S` was programmed on the connected board and did
receive/echo a UDP packet from `192.168.1.2:1234` to `192.168.1.10:1234`. That
design uses a custom RGMII bridge with `IDELAY_VALUE = 9` on RX data/control.
This reduces the likelihood of a cable/adapter/RJ45/PHY analog failure. The
stage-1 hand-written PS/GMII/RGMII bridge remains incomplete, but further
manual bridge timing work is paused until the official TF-card Linux ping gate
decides whether the project can move up to the Linux/socket route.
```

MVP implication:

```text
Ethernet PHY -> PL pins -> official Linux network stack if the TF-card ping
gate passes; otherwise restore the official Xilinx gmii_to_rgmii IP before any
further baremetal fallback work.
```

Do not implement a pure RTL UDP stack for the first pass-through cycle unless
both Linux and official-IP PS fallback evidence prove the PS route unusable.

Official reference now identified for extraction:

```text
tools/downloads/10_PS_EMIO_NET_TEST/10_PS_EMIO_NET_TEST/NET_TEST/
```

This reference is useful because it targets `xc7z020clg484-1` and contains a
Vivado/SDK project for PS ENET0 EMIO, GMII-to-RGMII, MDIO EMIO, UART EMIO, and
lwIP echo testing. Extract minimal facts from it into tracked Tcl/XDC/software;
do not commit the downloaded project.

Extracted official EMIO Ethernet wiring:

```text
processing_system7_0/GMII_ETHERNET_0 -> gmii_to_rgmii_0/GMII
processing_system7_0/MDIO_ETHERNET_0 -> gmii_to_rgmii_0/MDIO_GEM
gmii_to_rgmii_0/MDIO_PHY -> MDIO_PHY_0 external
gmii_to_rgmii_0/RGMII -> RGMII_0 external
processing_system7_0/FCLK_CLK0 -> gmii_to_rgmii_0/clkin
processing_system7_0/FCLK_RESET0_N -> util_vector_logic_0 -> tx_reset/rx_reset
```

## UART

| Item | Value | Status |
| --- | --- | --- |
| UART nets | `PL_UART_TX`, `PL_UART_RX` | confirmed from schematic text |
| USB-UART nets | `CH340_UART_RX`, `CH340_UART_TX` | confirmed from schematic text |
| Runtime COM port | `COM27` observed previously | environment-dependent |
| Physical side | PL-side UART nets | confirmed by board discussion and schematic net names |
| Package-pin mapping | `PL_UART_TX=L17`, `PL_UART_RX=M17` | confirmed from local schematic layout text |
| Official route | PS UART0 over EMIO | confirmed from official EMIO Ethernet project |
| Official baud | 115200 | confirmed from official PS7 BD parameters |
| Official I/O standard | `LVCMOS33` | confirmed from official EMIO Ethernet project XDC |

Confirmed UART net to package-pin mapping:

| Net | FPGA pin | Schematic signal | Connects to |
| --- | --- | --- | --- |
| `PL_UART_TX` | `L17` | `GPIO_L17_L4P` | `CH340_UART_RX` |
| `PL_UART_RX` | `M17` | `GPIO_M17_L4N` | `CH340_UART_TX` |

Mapping evidence:

```text
build/reports/SmartZynq_SL_Schematic_V1d3_20241005-layout.txt
lines 218-220
```

Constraint status:

```text
UART package pins and LVCMOS33 I/O standard are now source-backed by the
schematic and official EMIO Ethernet project.
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
| Official PS7 DDR UI part | `MT41K256M16 RE-125` | confirmed from official EMIO Ethernet project BD |
| DDR type | DDR3 | confirmed from official EMIO Ethernet project BD |
| DDR UI bus width | 16-bit | confirmed from official EMIO Ethernet project BD |
| PS DQ width | 32 | confirmed from official EMIO Ethernet project BD |
| DDR frequency | 533.333 MHz | confirmed from official EMIO Ethernet project BD |
| DDR usable range | `0x00100000` to `0x1fffffff` | confirmed from official EMIO Ethernet project BD |
| PS input clock | 33.333333 MHz | confirmed from official EMIO Ethernet project BD |
| FCLK0 | 200 MHz, enabled | confirmed from official EMIO Ethernet project BD |
| PL DDR access port | `processing_system7_0/S_AXI_HP0` | confirmed from official PL/PS DDR and VDMA HDMI projects |
| PL DDR tester base | `0x10000000` | confirmed from official PL/PS DDR project |
| VDMA framebuffer base | `XPAR_PS7_DDR_0_S_AXI_BASEADDR + 0x01000000` | confirmed from official VDMA HDMI SDK |

Important caution:

```text
The official EMIO Ethernet project provides the first source-backed PS7 DDR
configuration for this repository. It is sufficient as the baseline to recreate
PS DDR init, but it does not by itself prove the new PL DDR read path required
for HDMI pass-through.

The official PL/PS DDR project proves the HP0 AXI route for PL access to PS
DDR, but its custom PL_DDR_RW IP is only a write/read/compare tester. For the
video MVP, prefer the official VDMA HDMI structure for DDR-to-HDMI rather than
turning the tester IP into a video reader.
```

## HDMI / VDMA

| Item | Value | Status |
| --- | --- | --- |
| Official HDMI framebuffer route | PS writes DDR framebuffer; AXI VDMA MM2S reads DDR through HP0; stream drives `v_axi4s_vid_out -> rgb2dvi -> HDMI` | hardware-verified with official control image |
| Resolution used by official MVP reference | 800x600 | confirmed |
| Pixel format | RGB888, 24-bit stream | confirmed |
| VDMA read burst | 64 | confirmed from official BD Tcl |
| VDMA framebuffer base | `XPAR_PS7_DDR_0_S_AXI_BASEADDR + 0x01000000` | confirmed from official SDK |
| Pixel/serial clocks | 40 MHz pixel clock, 200 MHz serial clock | confirmed from official tutorial and BD Tcl |
| PS FCLKs | FCLK0 50 MHz, FCLK1 150 MHz | confirmed from official VDMA HDMI project |
| HDMI data P pins | M21, L21, J21 | confirmed from official VDMA XDC and board profile |
| HDMI clock P pins | N19 for V1.3; official demo also exposes N22 for earlier boards | confirmed from official VDMA tutorial/XDC |
| HDMI capture device for current setup | DirectShow index 1, 800x600 | environment-dependent but verified in latest control run |
| Official VDMA control result | Captured stable bars with RGB means white/red/green/blue and validation score 6/6 | passed on connected hardware |

MVP implication:

```text
Use VDMA as the DDR-to-HDMI boundary.

PC UDP receiver on PS writes one RGB888 frame into the VDMA framebuffer, flushes
DCache, and lets VDMA continuously scan that buffer to HDMI. This removes the
need for a custom PL AXI framebuffer reader in the first-stage MVP.
```

Latest hardware control:

```text
Program:
build/reports/vdma-official-program/OFFICIAL_VDMA_HDMI_PROGRAM_OK.log

Capture:
build/reports/vdma-hdmi-capture-device1-dshow/latest-validation.json
build/reports/vdma-hdmi-capture-device1-dshow/latest.png

Result:
Official VDMA color bars passed on the connected board and HDMI capture path.
This proves the DDR framebuffer -> VDMA -> HDMI subchain, not Ethernet input.
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

The current first-stage implementation chain is:

```text
PC fixed video/static frame
  -> UDP over Ethernet
  -> RTL8211E PHY on PL pins
  -> PS/Linux socket receiver if the TF-card route gate passes
     or PS fallback receiver after restoring official Xilinx gmii_to_rgmii IP
  -> PS writes DDR VDMA frame buffer
  -> VDMA MM2S reads DDR frame buffer
  -> v_axi4s_vid_out -> rgb2dvi -> HDMI raw pass-through
  -> PC HDMI capture
```

The first-stage success criterion is:

```text
The original input image/video frame returns through HDMI without PIP, rotation,
scale, filter, test stripes, random blocks, or other effects.
```

## Official Reference Examples

The official SL resource page is a source index, not a single implementation.
For the current first-stage video pipeline, reuse these references selectively:

| Need | Official reference | Reuse decision |
| --- | --- | --- |
| PS-side Ethernet over PL pins | `smart-zynq_net_test-2` / PS experiment 10 | Source-backed baseline for PS ENET0 EMIO, MDIO EMIO, PS7 DDR, UART0 EMIO, and lwIP. If baremetal fallback resumes, restore its official Xilinx `gmii_to_rgmii` IP instead of continuing the hand-written bridge. |
| RGMII receive timing sanity | `udp_net_test` / FPGA experiment 17 | Already hardware-verified; proves the external PHY/RJ45/PC path can pass UDP. Do not use it as a reason to keep tuning the hand-written PS bridge while the Linux route gate is untested. |
| PL reads/writes PS DDR | `pl_ddr_ps_test` / PS experiment 14 | Use as the HP0/AXI proof and DDR-initialization caution; do not use its tester IP as the final video output engine. |
| HDMI frame display through memory | `vdma_01` / PS experiment 19 | Preferred DDR-to-HDMI implementation reference for stage-1: AXI VDMA MM2S + `v_axi4s_vid_out` + `rgb2dvi`; official color-bar image has passed on connected hardware. |
| Static image source from TF card | `vdma3` / PS experiment 20 | Secondary reference after the required official Linux ping gate. |
| PL-only HDMI output | `smart-zynqspsl_hdmi_test` / FPGA experiment 12 | Useful for HDMI pin/timing cross-checks; less useful than VDMA once PS DDR is involved. |
| PS-provided PL clock | `smart-zynqspampsl_clk_ps_pl` / PS experiment 16 | Useful if replacing local clock assumptions with PS FCLK-derived PL clocks. |

Schematic caution:

```text
The refreshed official SL page currently links
SmartZynq_SL_Schematic_V1d3B_20260415.pdf. The connected board is reported by
the user to be from before 2026-03-02, so do not silently replace the existing
V1d3 20241005 schematic-derived constraints with the 20260415 schematic.
Use the newer schematic only as a comparison source until board revision
compatibility is confirmed.
```

## Open Board Facts Needed Before Hardware Build

The following facts block a correct first-stage hardware close:

1. Whether the official TF-card Linux image can bring up the PL-side RTL8211E
   Ethernet path and respond to PC ping.
2. If Linux ping works: Linux userspace or driver path for writing received
   frame data into the VDMA framebuffer.
3. If Linux ping fails: physical receive direction, RTL8211E/board path, or
   official Xilinx `gmii_to_rgmii`/PS GEM receive path.
4. PC-to-DDR software integration after Ethernet RX is fixed: copy received
   RGB data into the proven VDMA framebuffer and flush DCache before display.

Do not guess these values. If no official source is found, create a small
pin-audit report before editing XDC or PS7 block design constraints.
