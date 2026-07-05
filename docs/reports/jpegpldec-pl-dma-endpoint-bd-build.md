# jpegpldec PL DMA Endpoint BD Build

Cycle ID: jpegpldec-pl-dma-endpoint-bd-build

Date: 2026-07-05

## Objective

Move the larger `jpegpldec` PS-to-PL buffer objective from a simulated
AXI4-Stream probe core to a buildable board hardware endpoint.

This cycle integrates a simple-mode AXI DMA around `axis_dma_probe_core`:

```text
DDR buffer -> AXI DMA MM2S -> axis_dma_probe_core
-> AXI DMA S2MM -> DDR buffer
```

The endpoint is intended for a later Linux client that allocates or receives a
DMA-safe decoded-frame buffer, transfers it through PL, checks probe counters,
and returns the buffer to the unchanged external GStreamer pipeline.

## Changed Scope

- Added `axis_dma_probe_core.v` to the stage-1 VDMA board build source list.
- Instantiated `axi_dma_0` as Xilinx AXI DMA 7.1 in simple mode.
- Instantiated `axis_dma_probe_core_0` in the board BD.
- Connected `axi_dma_0/M_AXIS_MM2S` to `axis_dma_probe_core_0/S_AXIS`.
- Connected `axis_dma_probe_core_0/M_AXIS` to `axi_dma_0/S_AXIS_S2MM`.
- Connected `axi_dma_0/M_AXI_MM2S` and `axi_dma_0/M_AXI_S2MM` to HP0 through
  `axi_smc`.
- Connected `axi_dma_0/S_AXI_LITE` and `axis_dma_probe_core_0/S_AXI` to PS GP0
  through `ps7_0_axi_periph`.
- Added AXI-Lite address windows:
  - `axi_dma_0`: `0x43020000`, range `0x10000`.
  - `axis_dma_probe_core_0`: `0x43c10000`, range `0x10000`.
- Connected AXI DMA interrupts into the existing PS IRQ concat at inputs 3 and
  4.

## Verification

Simulation command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through
```

Observed simulation markers:

```text
AXI_FRAMEBUFFER_LINE_READER_OK checked_pixels=128 underflow_seen=1
PL_CONTROLLED_PIP_CORE_SIM_OK default_overlay=12 half_overlay=48 grayscale_overlay=12
PL_DUAL_VDMA_PIP_CORE_SIM_OK overlay_pixels=12 border_pixels=10 pip_content_pixels=2 main_pixels=180
AXIS_DMA_PROBE_CORE_SIM_OK frames=1 beats=2 bytes=8 input_checksum=bcf0235d output_checksum=bd1022b1
SIM_FLOW_OK example=eth-ps-pl-hdmi-pass-through sim_root=/mnt/e/main/fpga-hdml/build/eth-ps-pl-hdmi-pass-through/sim
SIM_OK example=eth-ps-pl-hdmi-pass-through sim_root=E:\main\fpga-hdml\build\eth-ps-pl-hdmi-pass-through\sim
```

Board build command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1
```

Observed build marker:

```text
STAGE1_VDMA_BOARD_BUILD_OK bitstream=/mnt/e/main/fpga-hdml/build/eth-ps-pl-hdmi-pass-through/vdma-board/eth_ps_vdma_hdmi_stage1_board.bit wns=0.245
```

Timing:

```text
WNS(ns)=0.245
TNS(ns)=0.000
All user specified timing constraints are met.
```

Routed DRC:

```text
Violations found: 9
REQP-1839 Warning  RAMB36 async control check 1
REQP-1840 Warning  RAMB18 async control check 1
REQP-165  Advisory writefirst 2
REQP-181  Advisory writefirst 5
```

No DRC Error or Critical Warning was reported in the routed DRC table. The
warnings/advisories are in Xilinx FIFO/VDMA/DMA BRAM implementation blocks and
are tracked as residual risk below.

Generated BD handoff includes:

```text
create_bd_cell ... xilinx.com:ip:axi_dma:7.1 axi_dma_0
create_bd_cell ... axis_dma_probe_core_0
axi_dma_0/M_AXIS_MM2S -> axis_dma_probe_core_0/S_AXIS
axis_dma_probe_core_0/M_AXIS -> axi_dma_0/S_AXIS_S2MM
axi_dma_0/M_AXI_MM2S -> axi_smc/S03_AXI
axi_dma_0/M_AXI_S2MM -> axi_smc/S04_AXI
axi_dma_0/S_AXI_LITE -> ps7_0_axi_periph/M03_AXI
axis_dma_probe_core_0/S_AXI -> ps7_0_axi_periph/M04_AXI
axi_dma_0 Reg offset 0x43020000 range 0x10000
axis_dma_probe_core_0 Reg offset 0x43C10000 range 0x10000
```

## Result

PASSED for hardware endpoint construction.

This proves:

- The PL stream probe core remains simulation-clean with existing regressions.
- The board BD can instantiate the new AXI DMA endpoint and probe core.
- The endpoint connects to DDR through HP0 and exposes AXI-Lite registers to
  the PS address map.
- The full design synthesizes, implements, writes bitstream, and meets timing.

This does not prove:

- A Linux DMA client exists.
- `jpegpldec` can allocate or receive a coherent/CMA-backed buffer.
- Real decoded video frames are transferred through this AXI DMA endpoint.
- Cache flush/invalidate correctness.
- PL-written data is returned to downstream GStreamer.

## Board Action

None.

No BOOT.BIN, image.ub, rootfs, TF-card update, JTAG programming, or board flash
write was performed. The bitstream was built but not deployed.

## Evidence

- `examples/eth-ps-pl-hdmi-pass-through/tcl/build_stage1_vdma_board.tcl`
- `examples/eth-ps-pl-hdmi-pass-through/tcl/create_ps_emio_vdma_hdmi_bd.tcl`
- `build/eth-ps-pl-hdmi-pass-through/sim/tb_axis_dma_probe_core-xsim-run.log`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/eth_ps_vdma_hdmi_stage1_board.bit`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/stage1_vdma_board_stdout.log`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/timing_summary.rpt`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/post_route_drc.rpt`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/eth_ps_vdma_hdmi_stage1_board.srcs/sources_1/bd/ZYNQ_CORE/hw_handoff/ZYNQ_CORE_bd.tcl`

## Decision

Proceed to the Linux side only after keeping this endpoint boundary explicit:

1. Add a minimal board-side DMA client that programs `axi_dma_0` and reads
   `axis_dma_probe_core_0` counters.
2. Use a DMA-safe allocation strategy before claiming cache correctness.
3. Integrate `jpegpldec` only after the standalone DMA client proves a known
   buffer can loop through PL and return with matching checksum or expected
   marker.

## Rollback

Revert the two Tcl changes that add `axi_dma_0` and `axis_dma_probe_core_0` to
the board BD. The previous known-good PL PIP bitstream path remains documented
in `docs/reports/pl-controlled-pip-effect-pipeline.md`.

## Third-Party Review

None.

## Residual Risks

- The routed design reports two BRAM async-control warnings inside Xilinx
  generated FIFO/datamover blocks. They are not DRC errors, but should be
  watched if the DMA endpoint shows reset-time instability.
- The AXI DMA endpoint is not represented in the running board image until a
  BOOT.BIN is packaged and deployed.
- The current PetaLinux image may still lack a user-space DMA buffer interface;
  a small kernel driver, UIO mapping plus reserved memory, or equivalent
  coherent-buffer path may be needed before `jpegpldec` can use this endpoint
  safely.
