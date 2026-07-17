# Native 720p Display Checkpoint

Date: 2026-07-15

Status: paused at checkpoint; target not complete.

## Target

Use native 1280x720 HDMI timing for the existing 720p30 `jpegpldec`
PL-decoder path. The decoded RGB stream should enter the PL PIP stage and
then the HDMI output path without PS-side geometry scaling. PIP input must be
duplicated from the same AXI4-Stream frame boundary and use frame-level
double buffering.

## Completed Before Pause

- Set the BD video timing to the Vivado 2018.3 `720p` preset.
- Set the HDMI clock targets to 74.25 MHz pixel and 371.25 MHz serial domains.
- Updated the Linux timing overlay and PC dashboard receiver to 1280x720 RGB.
- Connected VDMA MM2S through an AXIS input broadcaster into the PL PIP core.
- Replaced the PIP frame arrays with explicit clocked dual-port RAM modules.
- Added the broadcaster simulation and included the frame RAM in PIP simulation.

## Evidence

The complete RTL simulation flow passed with these markers:

```text
AXI_FRAMEBUFFER_LINE_READER_OK
PL_CONTROLLED_PIP_CORE_SIM_OK
AXIS_PIP_INPUT_BROADCAST_SIM_OK
AXIS_DMA_PROBE_CORE_SIM_OK
SIM_FLOW_OK
SIM_OK
```

The generated BD validated with 1280 active pixels, 720 active lines, a
1650-pixel horizontal frame, and a 750-line vertical frame.

The first native build exposed a real resource issue: the inferred PIP frame
arrays were reported as `RAM64M`/LUT resources despite `ram_style=block`.
That build was stopped. The explicit-RAM rebuild reached the PIP OOC launch,
but after the 30-minute build limit there was still no `.vivado.end.rst` or
`.vivado.error.rst` and no utilization report. The build was stopped without
producing a bitstream.

## Not Proven

- full system synthesis and implementation;
- post-route timing and DRC;
- native 1280x720 bitstream programming;
- board HDMI output or HDMI capture;
- stable PIP frame-boundary behavior on hardware;
- removal or justification of the still-instantiated `axi_vdma_1`.

## Next Resume Point

Run an isolated OOC synthesis of `axis_pip_frame_ram`/`axis_pip_overlay_core`
with the same XC7Z020 target and obtain a resource report. Only after that
report completes should the full board build be resumed.
