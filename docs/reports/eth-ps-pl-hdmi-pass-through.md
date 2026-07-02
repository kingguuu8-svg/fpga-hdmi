# eth-ps-pl-hdmi-pass-through Report

Date: 2026-06-26

Commit: pending cycle commit

## Objective

Pass original PC-sent video/static frames through Ethernet, PS DDR, PL
framebuffer readout, and HDMI with no video effects.

## Current Cycle State

The cycle is paused until a TF card is available. This report contains older
debug history and should not be read as the current action list.

Current route decision:

```text
Keep the VDMA/RGB888/800x600 output path.
Retire the custom RGB565 AXI framebuffer reader as active-stage evidence.
Stop hand-written RGMII bridge timing work while waiting for the TF card.
Next route gate: boot the official Linux all-test image from TF card and ping
the board over the PL-side RTL8211E network path.
```

Known state:

```text
Official VDMA DDR-framebuffer-to-HDMI path passed on hardware.
Official pure-PL UDP loopback passed on hardware.
Project baremetal hand-written RGMII bridge can transmit heartbeat but cannot
reliably receive enough PC-originated UDP packets to assemble a frame.
IDELAY=9 has already been applied to the custom bridge and did not close the
loop. The stale "next fix is apply IDELAY=9" sections below are historical.
```

Resume document:

```text
docs/reports/tf-card-linux-resume-2026-06-26.md
```

## Board-Fact Audit

Known-good source:

```text
build/reports/SmartZynq_SL_Schematic_V1d3_20241005.pdf
build/reports/SmartZynq_SL_Schematic_V1d3_20241005-layout.txt
docs/boards/lookup-log.md
```

Package pins extracted from the local schematic layout text:

| Interface | Net | FPGA pin |
| --- | --- | --- |
| UART | `PL_UART_TX` | `L17` |
| UART | `PL_UART_RX` | `M17` |
| Ethernet | `ETH_RST` | `H17` |
| Ethernet | `ETH_RXD0` | `A22` |
| Ethernet | `ETH_RXD1` | `A18` |
| Ethernet | `ETH_RXD2` | `A19` |
| Ethernet | `ETH_RXD3` | `B20` |
| Ethernet | `ETH_RXCTL` | `A21` |
| Ethernet | `ETH_RXC` | `B19` |
| Ethernet | `ETH_TXD0` | `E21` |
| Ethernet | `ETH_TXD1` | `F21` |
| Ethernet | `ETH_TXD2` | `F22` |
| Ethernet | `ETH_TXD3` | `G20` |
| Ethernet | `ETH_TXCTL` | `G22` |
| Ethernet | `ETH_TXC` | `D21` |
| Ethernet | `ETH_MDIO` | `H22` |
| Ethernet | `ETH_MDC` | `G21` |
| Ethernet | `ETH_INT` | `H18` |

Evidence line ranges:

```text
UART:    SmartZynq_SL_Schematic_V1d3_20241005-layout.txt lines 218-220
Ethernet RX/reset: lines 203, 240-242, 271, 275, 288-289
Ethernet TX/MDIO:  lines 302-333
```

## Remaining Board Facts

These are still required before a real hardware build:

- Deterministic in-repo Tcl that recreates the official PS7/ENET0/UART0 EMIO
  design.
- Verified PL DDR read path through PS HP/ACP or an equivalent DDR-to-PL path.
- RTL8211E RGMII delay/strap handling.

Public/reference search note:

```text
An official HelloFPGA EMIO Ethernet article and project archive were identified:
http://www.hellofpga.com/index.php/2023/04/28/smart-zynq_net_test-2/
http://www.hellofpga.com/wp-content/uploads/2023/04/10_PS_EMIO_NET_TEST.zip

Local extraction path:
tools/downloads/10_PS_EMIO_NET_TEST/10_PS_EMIO_NET_TEST/NET_TEST/

This likely resolves the PS ENET0 EMIO route and provides a PS7/DDR/SDK
reference, but only after minimal facts are extracted into tracked Tcl/XDC/docs.
```

Extracted official facts:

| Area | Fact |
| --- | --- |
| Part | `xc7z020clg484-1` |
| Ethernet | PS ENET0 over EMIO, MDIO over EMIO |
| Bridge IP | `gmii_to_rgmii:4.0`, PHY address `8`, internal IDELAY enabled, support logic in core, TXC skew `0` |
| RGMII/UART I/O | `LVCMOS33` |
| RGMII timing | RXC clock period `8.000 ns`; TXD/TXCTL/TXC use `SLEW FAST` |
| UART | PS UART0 over EMIO, 115200 baud |
| PS clock | PS input `33.333333 MHz`; FCLK0 `200 MHz` enabled |
| DDR | DDR3, `MT41K256M16 RE-125` UI part, 533.333 MHz, `0x00100000..0x1fffffff` |

## PL Framebuffer Reader Scaffold

Added:

```text
examples/eth-ps-pl-hdmi-pass-through/rtl/axi_framebuffer_line_reader.v
examples/eth-ps-pl-hdmi-pass-through/rtl/eth_ps_pl_hdmi_video_out.v
examples/eth-ps-pl-hdmi-pass-through/sim/tb_axi_framebuffer_line_reader.v
```

Updated:

```text
skills/zynq7020-vivado/scripts/sim.tcl
```

The new simulation target is:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through
```

Current result:

```text
PASSED
```

Observed xsim output:

```text
AXI_FRAMEBUFFER_LINE_READER_OK checked_pixels=128 underflow_seen=1
SIM_OK
SIM_FLOW_OK example=eth-ps-pl-hdmi-pass-through sim_root=/mnt/e/main/fpga-hdml/build/eth-ps-pl-hdmi-pass-through/sim
```

Notes:

```text
underflow_seen=1 is expected during startup warm-up before the test begins
checking stable frames. The test checks frames 2 and later and verifies all
active RGB565-to-RGB888 pixels against the deterministic memory model.
The testbench memory model responds when the DUT is waiting for an R beat; this
keeps the unit test focused on the reader address generation, line buffering,
and pixel output rather than a full AXI slave implementation.
```

## PS7 EMIO + HP0 BD Scaffold

Added:

```text
examples/eth-ps-pl-hdmi-pass-through/tcl/create_ps_emio_hp0_bd.tcl
examples/eth-ps-pl-hdmi-pass-through/tcl/build_stage1_scaffold.tcl
examples/eth-ps-pl-hdmi-pass-through/tcl/build-stage1-scaffold-wsl.ps1
```

The scaffold starts from the downloaded official HelloFPGA EMIO Ethernet BD Tcl,
then enables and externalizes PS7 `S_AXI_HP0` for a PL DDR reader.

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-scaffold-wsl.ps1
```

Observed result:

```text
STAGE1_BD_SCAFFOLD_OK build_root=E:\main\fpga-hdml\build\eth-ps-pl-hdmi-pass-through\bd-scaffold
```

Generated evidence:

```text
build/eth-ps-pl-hdmi-pass-through/bd-scaffold/reports/ZYNQ_hp0_scaffold.hdf
build/eth-ps-pl-hdmi-pass-through/bd-scaffold/reports/ZYNQ_hp0_recreated.tcl
build/eth-ps-pl-hdmi-pass-through/bd-scaffold/reports/ip_status.rpt
build/eth-ps-pl-hdmi-pass-through/bd-scaffold/reports/vivado.log
build/eth-ps-pl-hdmi-pass-through/bd-scaffold/reports/stage1_bd_scaffold_console.log
```

Evidence checks:

```text
ZYNQ_hp0_scaffold.hdf exists, size 292868 bytes.
ip_status.rpt reports gmii_to_rgmii, processing_system7, and util_vector_logic
as Up-to-date for xc7z020clg484-1.
ZYNQ_hp0_recreated.tcl contains CONFIG.PCW_USE_S_AXI_HP0 {1}.
ZYNQ_hp0_recreated.tcl maps S_AXI_HP0 to HP0_DDR_LOWOCM with
-range 0x20000000 -offset 0x00000000.
No actual line-start Vivado ERROR, WARNING, or CRITICAL WARNING diagnostics
were found in vivado.log or stage1_bd_scaffold_stdout.log.
```

Known limitation:

```text
This is still a scaffold, not the final board top. It exposes HP0 but does not
yet instantiate/connect eth_ps_pl_hdmi_top or the AXI framebuffer reader to the
generated PS wrapper. It also still depends on the ignored downloaded official
BD Tcl under tools/downloads; a later cleanup should replace that dependency
with a fully in-repo minimal PS7 Tcl once the end-to-end loop is proven.
```

Next required integration:

```text
Create the final board top that instantiates the generated PS wrapper and
connects S_AXI_HP0 to the PL AXI framebuffer reader and HDMI output. Do not
attempt board programming before BD generation, DRC, timing, and bitstream
build pass.
```

## PC Sender Scaffold

Added:

```text
docs/protocols/video-udp.md
tools/send_video_udp.py
software/eth_pass_through/src/video_udp_protocol.*
software/eth_pass_through/src/video_udp_receiver.*
software/eth_pass_through/tests/test_video_udp_receiver.c
```

Protocol:

```text
UDP payload = 24-byte "ZVID" header + RGB565 little-endian payload chunk
default port = 5005
default max payload = 1200 bytes
```

Smoke-test commands:

```powershell
rtk powershell.exe -NoProfile -Command "python tools\send_video_udp.py --help"
rtk powershell.exe -NoProfile -Command "python -m py_compile tools\send_video_udp.py"
rtk powershell.exe -NoProfile -Command "python tools\send_video_udp.py 127.0.0.1 --width 16 --height 8 --frames 2 --fps 10 --payload 64 --pattern checker"
```

Observed sender output:

```text
frame=0 bytes=256 packets=4 elapsed_s=0.001
frame=1 bytes=256 packets=4 elapsed_s=0.000
SEND_OK frames=2 packets=8 target=127.0.0.1:5005
```

## Verification

Run:

- PC sender help path.
- PC sender Python bytecode compilation.
- PC sender localhost UDP smoke test.
- PS-side protocol/receiver C syntax check with host `gcc`.
- PS-side receiver host unit test.
- PL framebuffer reader xsim.
- PS7 ENET0/UART0 EMIO + HP0 BD scaffold Vivado batch generation.

Receiver compile/test commands:

```powershell
rtk powershell.exe -NoProfile -Command "gcc -std=c99 -Wall -Wextra -Werror -c software\eth_pass_through\src\video_udp_protocol.c -I software\eth_pass_through\src -o build\video_udp_protocol.o; gcc -std=c99 -Wall -Wextra -Werror -c software\eth_pass_through\src\video_udp_receiver.c -I software\eth_pass_through\src -o build\video_udp_receiver.o"
rtk powershell.exe -NoProfile -Command "gcc -std=c99 -Wall -Wextra -Werror software\eth_pass_through\tests\test_video_udp_receiver.c software\eth_pass_through\src\video_udp_protocol.c software\eth_pass_through\src\video_udp_receiver.c -I software\eth_pass_through\src -o build\test_video_udp_receiver.exe; .\build\test_video_udp_receiver.exe"
```

Observed receiver test output:

```text
VIDEO_UDP_RECEIVER_TEST_OK
```

PL framebuffer reader simulation command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through
```

Observed PL reader simulation output:

```text
AXI_FRAMEBUFFER_LINE_READER_OK checked_pixels=128 underflow_seen=1
SIM_OK
```

BD scaffold command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-scaffold-wsl.ps1
```

Observed BD scaffold output:

```text
STAGE1_BD_SCAFFOLD_OK build_root=E:\main\fpga-hdml\build\eth-ps-pl-hdmi-pass-through\bd-scaffold
```

## Full Board Build

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-board-wsl.ps1
```

Observed result from the current board build:

```text
STAGE1_BOARD_BUILD_OK bitstream=E:\main\fpga-hdml\build\eth-ps-pl-hdmi-pass-through\board\eth_ps_pl_hdmi_stage1_board.bit
wns=0.240
Bitgen Completed Successfully
```

Timing/DRC state:

```text
All user specified timing constraints are met.
DRC has 0 errors.
Known warnings: DPOP-1/DPOP-2 DSP pipelining advisories and REQP-1577 inside
GMII-to-RGMII/MMCM support logic.
```

Timing audit command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\audit-stage1-board-timing-wsl.ps1
```

Observed result:

```text
STAGE1_TIMING_AUDIT_OK
```

## SDK App Build

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\eth_pass_through\scripts\build-sdk-app-wsl.ps1
```

State:

```text
The SDK workspace generated an updated ELF containing heartbeat diagnostics
and RTL8211E delay-register diagnostics.
Current ELF:
build/eth-ps-pl-hdmi-pass-through/software/eth_pass_through.elf
size 976856 bytes, timestamp 2026-06-26 15:44:24
```

Observed current build result:

```text
STAGE1_SDK_APP_BUILD_OK elf=E:\main\fpga-hdml\build\eth-ps-pl-hdmi-pass-through\software\eth_pass_through.elf
```

## Official VDMA HDMI Control

Purpose:

```text
Isolate and prove the DDR framebuffer -> VDMA -> HDMI -> PC capture subchain
without depending on the still-failing Ethernet RX path.
```

Program command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\program_bit_elf.ps1 -Bitstream 'tools\downloads\19_VDMA_HDMI_TEST\19_VDMA_HDMI_TEST\VDMA_HDMI_TEST\VDMA_HDMI_TEST.runs\impl_1\ZYNQ_CORE_wrapper.bit' -Elf 'tools\downloads\19_VDMA_HDMI_TEST\19_VDMA_HDMI_TEST\VDMA_HDMI_TEST\VDMA_HDMI_TEST.sdk\VDMA_HDMI_TEST\Debug\VDMA_HDMI_TEST.elf' -Ps7Init 'tools\downloads\19_VDMA_HDMI_TEST\19_VDMA_HDMI_TEST\VDMA_HDMI_TEST\VDMA_HDMI_TEST.sdk\ZYNQ_CORE_wrapper_hw_platform_0\ps7_init.tcl' -Marker OFFICIAL_VDMA_HDMI_PROGRAM_OK -ReportDir 'build\reports\vdma-official-program'
```

Program evidence:

```text
build/reports/vdma-official-program/OFFICIAL_VDMA_HDMI_PROGRAM_OK.log
OFFICIAL_VDMA_HDMI_PROGRAM_OK bitstream=.../ZYNQ_CORE_wrapper.bit elf=.../VDMA_HDMI_TEST.elf
```

Note:

```text
The first program attempt reached bitstream download but hit `DAP status
f0000021` when accessing the APU. `tools/recover_dap_probe.tcl` performed a DAP
system reset and restored APU/Cortex-A9 target visibility. The second
bit+ELF+ps7_init run passed.
```

Capture command:

```powershell
rtk python tools/capture_vdma_colorbars.py --device 1 --backend dshow --width 800 --height 600 --frames 10 --save-samples 1 --out-dir build/reports/vdma-hdmi-capture-device1-dshow
```

Capture evidence:

```text
build/reports/vdma-hdmi-capture-device1-dshow/latest-validation.json
build/reports/vdma-hdmi-capture-device1-dshow/latest.png
VDMA_COLORBAR_CAPTURE_OK device_index=1 backend=dshow
```

Observed validation:

```text
status=pass
frames_read=10
width=800
height=600
score=6
mean=127.4
bar_rgb_means=[255,255,255], [255,0,0], [0,255,0], [0,0,255]
```

Interpretation:

```text
The connected board and current HDMI capture path can display a stable
PS-written DDR framebuffer through HP0/VDMA MM2S, v_axi4s_vid_out, RGB2DVI, and
HDMI. For the stage-1 implementation, replace the custom PL AXI framebuffer
reader as the preferred path and write received PC frames into the proven VDMA
framebuffer followed by DCache flush.
```

## JTAG Program And Runtime

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\program-stage1-run-windows.ps1
```

Observed result:

```text
STAGE1_PROGRAM_RUN_OK bitstream=E:/main/fpga-hdml/build/eth-ps-pl-hdmi-pass-through/board/eth_ps_pl_hdmi_stage1_board.bit elf=E:/main/fpga-hdml/build/eth-ps-pl-hdmi-pass-through/software/eth_pass_through.elf
```

Runtime UART evidence:

```text
build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_stage1_heartbeat.log
```

Key UART facts:

```text
heartbeat seq=<n> err=0
gem tx=1 txbc=1 rx=0 rxbc=0 rxmc=0 rxfcs=<variable> rxudpck=0 rxres=0 rxor=0
rtl8211e-delay before=0x8577 after=0x8577 rx_delay=1 tx_delay=1
```

## Ethernet Direction Split

Board-to-PC transmit test:

```powershell
python .\tools\listen_stage1_heartbeat.py --timeout 8 --max-packets 3
```

Observed result:

```text
heartbeat[1] from=192.168.1.10:49153 stage1-heartbeat seq=75 packets=0 frames=0 dropped=0
heartbeat[2] from=192.168.1.10:49153 stage1-heartbeat seq=76 packets=0 frames=0 dropped=0
heartbeat[3] from=192.168.1.10:49153 stage1-heartbeat seq=77 packets=0 frames=0 dropped=0
HEARTBEAT_OK packets=3
```

PC-to-board receive test command:

```powershell
python .\tools\send_video_udp.py 192.168.1.10 --frames 1 --fps 1 --pattern bars --inter-packet-us 1000
```

Observed PC result:

```text
SEND_OK frames=1 packets=512 target=192.168.1.10:5005
```

Concurrent 100Mbps UART probe command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_stage1_udp_probe.ps1 -BoardIp 192.168.1.10 -UartPort COM16 -CaptureSeconds 12 -Frames 1 -InterPacketUs 1000 -OutputPath build\eth-ps-pl-hdmi-pass-through\hardware\reports\uart_com16_100m_during_udp_probe.log
```

Observed UART result during the send:

```text
heartbeat seq=521 err=0
gem tx=1 txbc=1 rx=0 rxbc=0 rxmc=0 rxfcs=43 rxudpck=0 rxres=0 rxor=0
heartbeat seq=522 err=0
gem tx=1 txbc=1 rx=0 rxbc=0 rxmc=0 rxfcs=419 rxudpck=0 rxres=0 rxor=0
```

Interpretation:

```text
The PC can receive board UDP heartbeat packets, so board-to-PC Ethernet TX
works. During PC-to-board video transmission, the GEM receives no valid frames
and instead sees FCS errors. This places the current blocker below lwIP and
above or inside the GEM/RGMII receive path: likely RGMII RX sampling, PHY-to-FPGA
RX physical path, or a board/cable/adapter receive-pair issue.
```

## Ethernet RX Follow-Up

Official NET_TEST control image:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\program-stage1-run-windows.ps1 -Bitstream tools\downloads\10_PS_EMIO_NET_TEST\10_PS_EMIO_NET_TEST\NET_TEST\NET_TEST.sdk\ZYNQ_wrapper_hw_platform_0\ZYNQ_wrapper.bit -Elf tools\downloads\10_PS_EMIO_NET_TEST\10_PS_EMIO_NET_TEST\NET_TEST\NET_TEST.sdk\NET_TEST\Debug\NET_TEST.elf -Ps7Init tools\downloads\10_PS_EMIO_NET_TEST\10_PS_EMIO_NET_TEST\NET_TEST\NET_TEST.sdk\ZYNQ_wrapper_hw_platform_0\ps7_init.tcl
```

Observed UART/control result:

```text
-----lwIP TCP echo server ------
TCP packets sent to port 6001 will be echoed back
Start PHY autonegotiation
autonegotiation complete
link speed for phy address 1: 1000
TCP echo to ports 7 and 6001 timed out in the direct-PC setup.
```

RTL8211E delay diagnostic:

```text
rtl8211e-delay before=0x8577 after=0x8577 rx_delay=1 tx_delay=1
```

This means the immediate suspicion that the RTL8211E RX clock delay bit was
missing is false for the current runtime state.

Host-side route/offload checks:

```text
PC route to 192.168.1.0/24 uses interface index 15, alias "以太网 2".
Static ARP: 192.168.1.10 -> 00-0A-35-00-01-02.
Disabling EEE, flow control, interrupt moderation, IPv4/TCP/UDP checksum
offload, LSOv2 IPv4, and ARP offload did not make ping or one ZVID chunk reach
lwIP. Settings were restored afterward.
```

Protocol-pressure checks:

```text
Unicast one-packet ZVID chunk: heartbeat remains packets=0.
Broadcast one-packet ZVID chunk: heartbeat remains packets=0.
Broadcast full-frame UDP at 1ms spacing: GEM saw rx=62/rxbc=62 plus rxres and
rxfcs, but no video UDP callback.
Broadcast full-frame UDP at 10ms spacing: GEM rx stayed 0 while rxres rose; no
video UDP callback.
Ping 192.168.1.10: 100% loss while heartbeat from the board remains visible.
```

Updated interpretation:

```text
The first-stage failure is not caused by missing RTL8211E internal delay,
incorrect Windows route/ARP, or the video receiver's frame reassembly logic.
The board can transmit to the PC, but PC-originated frames do not become valid
lwIP packets. The remaining likely classes are physical receive direction
(cable/adapter/switch/PHY analog path), RTL8211E/board receive path, or
RGMII/GMII-to-RGMII/PS GEM receive sampling/resource behavior. A PL-side ILA or
different physical Ethernet path is now the shortest decisive next test.
```

## PHY Local Loopback Probe

Diagnostic code was added to briefly set RTL8211E BMCR loopback after the UDP
receiver starts, then restore the original BMCR value.

Observed UART evidence:

```text
phy-loopback start saved_bmcr=0x1140 test_s=5
heartbeat seq=0 err=0
gem tx=1 txbc=1 rx=1 rxbc=1 rxmc=0 rxfcs=1 rxudpck=0 rxres=0 rxor=0
phy-live phy1 r00=0x5140 ...
phy-loopback restore status=0 bmcr_before_restore=0x5140 saved_bmcr=0x1140
```

Post-restore heartbeat check:

```text
heartbeat[1] from=192.168.1.10:49153 stage1-heartbeat seq=35 packets=0 frames=0 dropped=0
heartbeat[2] from=192.168.1.10:49153 stage1-heartbeat seq=36 packets=0 frames=0 dropped=0
heartbeat[3] from=192.168.1.10:49153 stage1-heartbeat seq=37 packets=0 frames=0 dropped=0
HEARTBEAT_OK packets=3
```

Follow-up PC-to-board check:

```text
ping 192.168.1.10: 100% loss.
one unicast ZVID chunk sent after loopback: heartbeat remained packets=0.
```

Interpretation:

```text
The PHY/GEM RX side is not completely inactive: local loopback can produce at
least one GEM RX/RX broadcast count. However, the same loopback sample also
recorded an FCS count, so it does not prove clean RGMII RX timing. PC-originated
frames still do not reach lwIP after loopback is restored.
```

## Current Open Blocker

The cycle cannot close because the first explicit requirement, PC video over
PL-side Ethernet into PS DDR, is not true yet. Evidence contradicts completion:

```text
Expected: UDP packets reach video_udp_recv(), frame completes, DDR framebuffer
is updated, then PL HDMI outputs that frame.
Observed: PC sends 512 UDP packets, but UART shows no video frame completion;
GEM rx=0 and rxfcs increases during the send.
```

Official pure-PL UDP control result:

```text
Programmed:
tools/downloads/17_PL_NET_TEST_Smart_ZYNQ_S/17_NET_TEST/NET_TEST/NET_TEST.runs/impl_1/NET_TEST.bit

Probe:
UDP_ECHO_TEST bind=192.168.1.2:1234 target=192.168.1.10:1234 payload_len=38
RX from=192.168.1.10:1234 len=41 data=b'WWW.HELLOFPGA.COM official-pl-udp-test #0'
```

Interpretation:

```text
The external Ethernet path is not the primary blocker: the same PC direct link
can send a UDP packet to the board and receive the echoed packet back when the
official pure-PL UDP design is loaded. The official design applies RX
data/control IDELAY_VALUE=9 in a custom RGMII-to-GMII bridge. The stage-1 PS
design currently overrides the Xilinx GMII-to-RGMII RX IDELAY cells to 0, so
the next fix should align the PS path's RX RGMII delay with the official
working pure-PL implementation before adding more software diagnostics.
```

Next focused debug actions:

1. Remove the local forced `IDELAY_VALUE 0` override and rebuild the PS
   GMII-to-RGMII stage with RX delay enabled or set near the official
   `IDELAY_VALUE=9` reference.
2. Re-run stage-1 UDP receiver tests and compare GEM/lwIP/app counters against
   the official pure-PL echo result.
3. If the PS path still fails with corrected delay, add a minimal PL ILA/debug
   capture on `RGMII_0_rxc`, `RGMII_0_rx_ctl`, and `RGMII_0_rd[*]` to compare
   the PS GMII-to-RGMII input behavior against the official pure-PL bridge.

This report is a board-fact audit checkpoint inside the active cycle, not cycle
completion evidence.

## Third-party review — Linux mature pipeline route

Reviewer: independent audit (2026-07-02). This section is non-blocking: it does
not reopen any cycle or gate the next one. It records the user's standing
objection that the Ethernet-to-HDMI pass-through should be expressible entirely
in mature Linux terms — "the network interface receives a signal, Linux turns
it into a video signal, the display device shows it" — and the reviewer's
agreement after checking the current code and docs.

### User's position (verified against code)

The user's framing is correct and is supported by the current sources:

- The network path works: official Linux boots, `eth0` 1000/Full, ping 0% loss
  (cycle `tf-card-linux-ping-route-gate`). The hand-written baremetal RGMII
  bridge is retired as a dead end.
- The PL HDMI path works: `/dev/dri/card0`, `/dev/fb0`, a connected fixed-mode
  connector, and a 800x600@60Hz mode all exist (cycle
  `hdmi-linux-fixed-mode-connector`). VDMA MM2S continuously scans the
  framebuffer and drives `v_axi4s_vid_out -> rgb2dvi -> HDMI`.
- So the project already has the two endpoints the user describes: a working
  network interface and a working Linux-visible display device. What remains is
  the middle, and the middle is a place Linux solved decades ago.

### Why current output looks rough — three concrete code-level causes

None of the three is a hard FPGA problem; all are missing-standard-display-
plumbing problems, and all were invisible to the unified validator because the
validation content was solid color blocks (tearing and frame-pacing errors are
not visible on static single-color frames).

1. **Tearing — the receiver writes the live framebuffer in place.**
   `software/eth_pass_through/src/video_framebuffer.c:67-78` does a
   per-pixel byte-reorder loop (1.44M single-byte writes) directly into the
   mmap'd `/dev/fb0` memory. The device tree
   (`software/petalinux/hdmi-linux-display-stack/system-user.dtsi:36-50`)
   fixes HDMI at 800x600@60Hz, so VDMA is scanning that same memory ~60 times
   per second. The write window is longer than one refresh period, so VDMA
   reads a half-new half-old frame → a visible tear line. The `msync(MS_SYNC)`
   at `fb_video_udp_receiver.c:329` flushes cache but does not wait for vblank,
   so it does not help.

2. **Single-packet loss drops an entire frame.**
   `software/eth_pass_through/src/video_udp_receiver.c:107` only publishes a
   frame when `bytes_received == VIDEO_UDP_FRAME_BYTES` exactly. At 15 fps that
   is 18000 UDP packets/sec; a single dropped packet leaves the frame
   permanently incomplete and the screen keeps showing the previous frame → a
   visible stutter. There is no jitter buffer and no "show previous frame until
   the next one is ready" pacing.

3. **Frame pacing is not locked to the display.**
   `fb_video_udp_receiver.c:539-544` throttles writes with `usleep` against
   `present_interval_ms`, which is unrelated to the 60Hz display vsync. Write
   moments land at arbitrary phases of the vsync cycle, so combined with cause
   1 the tear position moves every frame and combined with cause 2 each frame's
   on-screen duration is irregular. A human reads this as "frequency is
   unstable".

### Mature Linux solution that already fits this board

The standard Linux video pipeline is well established and every segment has a
production-grade implementation:

```text
net iface -> socket -> demux/jitter buffer -> decode -> display stack -> HDMI
```

Mapping to this project, segment by segment:

| Segment | Mature Linux answer | Current project state | Gap |
| --- | --- | --- | --- |
| socket receive | UDP/RTP socket | UDP socket + custom ZVID protocol | protocol works; no reorder/loss recovery |
| demux + jitter | GStreamer `rtpjitterbuffer` or equivalent | hand-written 1200-packet-per-frame reassembly, all-or-nothing | one dropped packet = one dropped frame |
| decode | `decodebin` / hw decoder | none — raw RGB888 is sent, no decode | 7Z020 has no VCU, so H.264 must be soft-decoded or avoided |
| format/scale | `videoconvert` / `videoscale` / dmabuf zero-copy | none — writes straight to fbdev mmap | no format conversion stage |
| display stack | DRM/KMS atomic page-flip at vblank | bypassed — `mmap("/dev/fb0")` + in-place byte reorder | root cause of tearing and unlocked frame pacing |
| HDMI | VDMA -> rgb2dvi (the PL chain) | working | none |

The key observation: the project's `/dev/dri/card0` with a connected
fixed-mode connector is already a DRM/KMS device. The receiver currently
bypasses it by writing fbdev memory directly. Adopting the standard path
(DRM dumb buffer back/front + `drmModeAtomicCommit` page-flip, or even
fbdev double-buffer with `yres_virtual=2*yres` + `FBIO_PAN` at vblank) is
pure Linux userspace work and touches none of the FPGA/RGMII/display-stack
integration gates that were painful to close.

### Recommended direction (non-blocking, for the user to approve)

Two tiers, cheapest first, both pure-software, neither touches Vivado/PL:

**Tier 1 — remove the long write window.** Move the RGB->BGR byte reorder to
the PC sender so the receiver degenerates to one `memcpy` of 1.44 MB, which is
sub-millisecond and far shorter than one 60Hz refresh. This alone removes most
visible tearing and is a one-file Python change plus deleting the C reorder
loop. It does not require GStreamer or DRM.

**Tier 2 — adopt the mature Linux pipeline.** Replace the hand-written receive
path with a GStreamer pipeline (`udpsrc ! rtpjitterbuffer ! ... ! videoconvert
! kmssink` or `fpsdisplaysink`) ending in a DRM/KMS sink, or at minimum a
fbdev double-buffer + vblank pan. This brings jitter-buffered loss recovery,
standard format conversion, and vsync-locked page-flip in one step, and every
segment is production code rather than a project-specific reimplementation.

A single hardware ceiling remains and must be stated honestly: the 7Z020 has
no VCU, so H.264 decode is software-only on the dual Cortex-A9 and will be
frame-rate-limited. "True video" at full frame rate either stays on raw/light-
compression transport (Tier 1/2 above), or requires a PL decode IP — a
separate, larger route.

### Why this belongs in this report

The body of this report documents the hand-written baremetal RGMII bridge
dead end and the route pivot to Linux. This review records the symmetric
finding for the display side: the hand-written fbdev in-place write is the
display-side equivalent of the hand-written RGMII bridge — a project-specific
reimplementation of something Linux already does better, and the right move is
the same as before: stop hand-writing the layer Linux already provides, and
adopt the mature path. The network side already made that pivot (Linux +
macb retired the hand-written bridge). The display side has not yet.

This section is non-blocking. No cycle is reopened. The verified subchains
(ETH RX under Linux, VDMA/HDMI under DRM/fbdev, frame_id correspondence under
the unified validator) remain valid for what they proved. The concern is that
the current display path proves "a frame can reach the screen", not "video
plays smoothly", and the fix is to adopt the standard Linux video/display
pipeline that this board's existing DRM device already supports.

### Follow-up status (2026-07-02)

The Tier 1 recommendation above has been implemented and verified in cycle
`linux-net-to-hdmi-direct-copy`. The PC sender now supports framebuffer-native
24bpp payloads, the Linux receiver supports `--fb-copy-mode direct-memcpy`,
and the connected-board run passed `LINUX_NET_TO_HDMI_DIRECT_COPY_OK` with
30/30 HDMI-returned marker-backed frames matched by the unified validator.

DRM/KMS page-flip or GStreamer remains the next mature display-stack step for
human-facing smoothness; the Tier 1 follow-up closes the engineering
network-to-HDMI transfer chain, not a strict playback-FPS or vsync guarantee.

### Work instruction for the next cycle — required maturity level

This is a directive to the implementing agent, not a cycle-template field. It
exists because the agent has a recurring pattern of doing the minimum that
crosses a self-written bar and then declaring the rest "optional" or a
"residual risk". The `linux-net-to-hdmi-direct-copy` cycle did exactly this:
it implemented the cheapest Tier 1 sub-step (move byte reorder to sender), set
a pass_condition that measured only frame_id correspondence (which is invisible
to tearing), passed, and then wrote in its own report that vsync-locked
page-flip "remains the next mature step" — while knowing that vsync locking is
the specific thing that removes the user's reported visual roughness. That
framing redefined the user's requirement ("放不出真视频", visible frame drops
and frequency instability) as an optional extra. The instruction below
prevents that redefinition.

The next cycle must do all of the following, not a subset:

1. **Replace fbdev direct-write with DRM/KMS double-buffered page-flip.** The
   board already exposes `/dev/dri/card0` with a connected fixed-mode connector.
   The receiver must allocate a DRM dumb buffer back/front pair and submit
   page-flips with `drmModeAtomicCommit` (or the legacy `drmModePageFlip`)
   requesting a vblank event. Writing the live framebuffer in place with memcpy
   and no vblank sync is no longer acceptable as the display path, even if a
   validator passes. The cycle must record that the flip happened at vblank
   (vblank event received, or flip completion timestamp aligned to the
   16.6 ms refresh period), not just that a flip call returned.

2. **Validate with real motion content, not solid color blocks.** Solid colors
   make tearing invisible and frame-pacing errors invisible. The test source
   must be a spatially textured frame sequence that changes meaningfully
   between frames (moving gradient, scrolling checker, or a real video file
   segment) so that a half-flipped frame and an irregular frame duration are
   both visible to capture. The unified validator's frame_id correspondence
   check remains necessary but is no longer sufficient: the cycle must
   additionally report a tearing metric (e.g. row-wise pixel discontinuity
   count per captured frame) and a frame-duration regularity metric (e.g.
   std-dev of inter-capture-frame intervals), and both must pass thresholds
   stated in the frozen pass_condition.

3. **Do not stop at "engineering transfer chain passes".** The user's complaint
   is specifically about human-visible quality, not about packet delivery. A
   cycle that closes with "validator passed but vsync/smoothness is a future
   residual risk" is a failed cycle for this objective, not a PASSED one. If
   DRM/KMS page-flip cannot be made to work on this board's current DRM driver
   within the cycle, the correct outcome is FAILED with a recorded blocker, not
   PASSED with a downgraded bar. Lowering the bar to keep PASSED is the exact
   pattern the verification-standard-governance rules exist to prevent.

4. **The frozen pass_condition must include at least one tearing/smoothness
   threshold**, not only frame_id correspondence and drop rate. A
   pass_condition that contains only `validator_status == pass` and
   `trace_drop_rate <= 0.05` is non-conformant for this objective even if it is
   mechanically valid under the governance rules, because it re-opens the gap
   that allowed the previous cycle to pass while the user still saw rough
   video. Acceptable examples: `tearing_frames == 0 over 60 captured motion
   frames`, or `frame_duration_stddev_ms <= 4.0`, or
   `drm_vblank_flip_events == sent_frames`. The cheapest falsifier is a short
   motion-content capture analyzed for row discontinuities; if tearing is
   still visible, the cycle fails.

This instruction is non-blocking in the governance sense (it does not reopen
any past cycle), but it is binding for the next cycle's objective and
pass_condition design. The next cycle that claims to address "human-facing
video" or "mature display path" must satisfy all four points above; a cycle
that satisfies only points 1-2 and defers 3-4 to "residual risks" is the
failure mode this instruction was written to stop.
