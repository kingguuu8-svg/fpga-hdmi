# Native 720p Display v2: v9 Build Evidence

Date: 2026-07-16

## Scope

This cycle isolates the JPEG DMAengine completion failure while retaining the
native 1280x720 HDMI display topology. The v9 experiment restores the prior
board-tested constant-high release on the JPEG data path and keeps the PS-side
AXI DMA and control path on synchronized PS reset domains. It does not change
the external GStreamer pipeline.

## Source Change

`examples/eth-ps-pl-hdmi-pass-through/tcl/create_ps_emio_vdma_hdmi_bd.tcl`
restores the `jpeg_reset_one` constant-high signal for the JPEG AXI DataMover,
writeback width converter, decoder data path, and decoder control
clock-converter master. The JPEG clock wizard and PS control reset topology are
unchanged from v8.

## Build Evidence

- Build directory: `build/720p-native-vdma-board-v9`
- Bitstream: `eth_ps_vdma_hdmi_stage1_board.bit`
- Bitstream SHA-256:
  `01d5aa9b921ae92970c7f8ea68d1655d33494ecb0d100e5fe308919c973b342a`
- HDF: `reports/eth_ps_vdma_hdmi_stage1_board.hdf`
- Vivado implementation completed successfully, including route and bitstream
  generation.
- Timing: WNS `+0.262 ns`, WHS `+0.021 ns`, zero failing timing endpoints,
  zero unrouted nets.
- Post-route DRC: zero Error-severity violations. The report still contains
  Warning/Advisory entries from the existing JPEG DSP/RAMB18 implementation;
  these are recorded rather than suppressed.
- The generated hierarchy includes `ZYNQ_CORE_jpeg_reset_one_0`.

The raw reports are under `build/720p-native-vdma-board-v9/reports/`.

## Hardware Boundary

The v9 bitstream has not yet been qualified on the board. The board was left in
an unhealthy state by the earlier v8 `input-sink` experiment: the UART shell
stopped responding and the JTAG probe still reports
`AP transaction error, DAP status 30000021`. PL-only rollback and software/JTAG
reset attempts did not recover the PS. A physical POR or board power cycle is
required before programming v9 and repeating the A/B test.

Therefore this report proves a reproducible v9 build, not a working v9 decode,
DMA interrupt, or HDMI video result. No TF-card files were changed during the
v8/v9 reset experiment.

The current HDF address/interrupt mapping is important for the next test:

- `axi_vdma_0` at `0x43000000` is the HDMI display VDMA; its MM2S/S2MM
  channels use GIC61/GIC62.
- `axi_dma_0` at `0x43020000` is the JPEG input MM2S DMA; its interrupt is
  GIC63.

An earlier diagnostic invoked the generic `vdma_mm2s_config` helper with
`0x43020000` and attempted to unbind `43020000.dma` through the `xilinx-vdma`
driver. Those actions targeted the JPEG AXI DMA, not the display VDMA, so their
status/Oops results are invalid for isolating display contention and must not be
repeated. The native display VDMA base for any direct register probe is
`0x43000000`.

To prevent a repeat, `vdma_mm2s_config` now rejects `0x43020000` before mapping
`/dev/mem`. The guarded ARM build passed with the existing Linux application
test suite; the host guard test also returned the expected refusal. The updated
binary and hashes are under
`build/native-720p-linux-image-v7/linux-tools-vdma-guard/`.

## Next Test

After physical POR/power-cycle:

1. Boot the existing TF-card native-720p Linux image and configure the static
   board address if DHCP does not provide one.
2. Program v9 and verify the JTAG target and UART remain healthy.
3. Load `jpegpl_dma_probe.ko` and run register-smoke.
4. Run one short `input-sink` test with an external UART timeout.
5. Record the pre/post GIC63 interrupt counter and kernel log. Record GIC61 and
   GIC62 only as display-VDMA context.

If v9 behaves like v7, the synchronized-reset hypothesis is rejected and the
remaining fault is in the native route's AXIS/DMA datapath. If v9 blocks the
board again, stop further hardware experiments and inspect the driver
termination path instead of increasing the timeout or changing the HDMI
presentation path.

## Rollback

Use the v7 bitstream under `build/720p-native-vdma-board-v7` and the existing
TF-card image as the known-good native display baseline. The v8 and v9 build
outputs are retained for comparison.
