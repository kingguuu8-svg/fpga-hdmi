# jpegpldec PL DMA Probe Core Simulation

Cycle ID: jpegpldec-pl-dma-probe-core-sim

Date: 2026-07-04

## Objective

Move the larger `jpegpldec` PS-to-PL buffer objective one step closer by adding
a real PL-side AXI4-Stream data probe core that can sit between an AXI DMA
MM2S stream and an AXI DMA S2MM stream.

This cycle does not claim the final `jpegpldec` DMA/cache loopback is complete.
It creates and verifies the PL data-plane component needed by that later board
path.

## Changed Scope

- Added `examples/eth-ps-pl-hdmi-pass-through/rtl/axis_dma_probe_core.v`.
- Added `examples/eth-ps-pl-hdmi-pass-through/sim/tb_axis_dma_probe_core.v`.
- Added the new testbench to
  `skills/zynq7020-vivado/scripts/sim.tcl` for the
  `eth-ps-pl-hdmi-pass-through` simulation flow.

## Probe Core Behavior

The core exposes:

- 32-bit AXI4-Stream sink/source.
- AXI-Lite control/status registers.
- Pass-through mode by default.
- Optional 32-bit XOR marker mode to prove PL can modify stream payload.
- Frame, beat, byte, input-checksum, and output-checksum counters.

The intended later board connection is:

```text
AXI DMA MM2S -> axis_dma_probe_core -> AXI DMA S2MM
```

## Verification

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through
```

Observed markers:

```text
AXI_FRAMEBUFFER_LINE_READER_OK checked_pixels=128 underflow_seen=1
PL_CONTROLLED_PIP_CORE_SIM_OK default_overlay=12 half_overlay=48 grayscale_overlay=12
PL_DUAL_VDMA_PIP_CORE_SIM_OK overlay_pixels=12 border_pixels=10 pip_content_pixels=2 main_pixels=180
AXIS_DMA_PROBE_CORE_SIM_OK frames=1 beats=2 bytes=8 input_checksum=bcf0235d output_checksum=bd1022b1
SIM_FLOW_OK example=eth-ps-pl-hdmi-pass-through sim_root=E:\main\fpga-hdml\build\eth-ps-pl-hdmi-pass-through\sim
SIM_OK example=eth-ps-pl-hdmi-pass-through sim_root=E:\main\fpga-hdml\build\eth-ps-pl-hdmi-pass-through\sim
```

## Result

PASSED for PL data-plane core simulation.

This verifies:

- The new probe core accepts and emits AXI4-Stream beats.
- Default pass-through preserves payload and packet boundaries.
- Marker mode changes payload and produces different output checksum.
- Existing eth-ps-pl-hdmi pass-through simulations still pass.

## Board Action

None.

No BOOT.BIN, image.ub, rootfs, FPGA bitstream, TF-card image, JTAG programming,
or board flash write was performed.

## Remaining Gap

The larger active goal remains incomplete.

Still required:

- BD integration of an AXI DMA MM2S/S2MM loop around `axis_dma_probe_core`.
- A Linux DMA client interface that allocates coherent/CMA-backed buffers.
- `jpegpldec` integration that copies or maps decoded frame data into that
  DMA-safe path without changing the external GStreamer pipeline.
- Board verification that PL-read/PL-write data returns to GStreamer and that
  cache maintenance is correct.

Do not treat this simulation as proof that normal `GstBuffer` memory is safe
for PL access.

## Rollback

Remove the new RTL/testbench and the `sim.tcl` test entry.

## Third-Party Review

None.
