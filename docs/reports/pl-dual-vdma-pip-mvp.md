# PL Dual-VDMA PIP MVP Report

Date: 2026-07-03

Result: PASSED

## Objective

Implement the first PL-side video effect on the current 5fps GStreamer closed
loop. Linux remains responsible for receiving the PC video stream and writing
the DDR framebuffer. PL reads the same framebuffer twice, scales the second
read path into a picture-in-picture window, overlays it on the main stream,
and outputs the result over HDMI.

## Implemented Route

```text
PC GStreamer moving-ball source
-> RTP/JPEG over Ethernet
-> board GStreamer receiver
-> fbdevsink /dev/fb0
-> VDMA0 MM2S main stream
-> VDMA1 MM2S same-framebuffer PIP stream
-> axis_pip_overlay_core
-> v_axi4s_vid_out + HDMI
-> PC HDMI capture adapter
-> dashboard right-panel MJPEG return
```

The PIP window is fixed for this MVP: 200x150 pixels at the lower-right of the
800x600 output, with an integer 4x downsample and a visible white border.
Runtime movement, rotation, arbitrary scaling ratios, and button/UART control
of the effect are outside this cycle.

## Changed Scope

- Added `axis_pip_overlay_core`, an AXI4-Stream same-source PIP overlay block.
- Added `tb_axis_pip_overlay_core` and connected it to the normal simulation
  script.
- Added a second MM2S-only AXI VDMA instance at AXI-Lite base `0x43010000`.
- Routed VDMA0 as the main stream and VDMA1 as the PIP stream into the overlay
  core before HDMI output.
- Added `vdma_mm2s_config`, a Linux userspace helper that reads `/dev/fb0`
  geometry and programs VDMA1 to the same framebuffer address/stride/hsize.
- Added a PIP validation profile to the HDMI capture tool.
- Added a frame-folder validator for dashboard-returned PIP MJPEG samples.

No software GStreamer/compositor effect is used as completion evidence. The
effect is implemented between VDMA and HDMI in PL.

## Verification

Simulation:

```text
AXI_FRAMEBUFFER_LINE_READER_OK checked_pixels=128 underflow_seen=1
PL_DUAL_VDMA_PIP_CORE_SIM_OK overlay_pixels=12 border_pixels=10 pip_content_pixels=2 main_pixels=180
SIM_FLOW_OK
SIM_OK
```

Vivado build:

```text
STAGE1_VDMA_BOARD_BUILD_OK bitstream=/mnt/e/main/fpga-hdml/build/eth-ps-pl-hdmi-pass-through/vdma-board/eth_ps_vdma_hdmi_stage1_board.bit wns=0.066
WNS=0.066
TNS=0.000
failing_endpoints=0
DRC errors=0
```

The PIP core out-of-context synthesis used `RAMB36E1=24` and no DSP48 blocks.
The routed DRC report still contains known Xilinx AXI VDMA RAMB async-control
warnings and write-first advisories, but no DRC errors.

Linux helper build:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
VIDEO_CONTROL_TEST_OK
VIDEO_EFFECT_TEST_OK
VDMA_MM2S_CONFIG_BUILD_OK
```

New BOOT.BIN packaging:

```text
BOOT.BIN SHA256=69696a2d6e624bc689751eb5a83bfb10d7d9387009c3c4a471571515d44a999d
```

Board update and reboot:

```text
PL_PIP_BOOTBIN_UPDATE_OK
/dev/fb0 exists
/dev/dri/card0 exists
xilinx-vdma 43000000.dma probed
xlnx-pl-disp probed
xlnx-fixed-hdmi bound with mode 800x600
```

VDMA1 configuration:

```text
FB_INFO path=/dev/fb0 xres=800 yres=600 bpp=24 line_length=2400 smem_start=0x0e100000 smem_len=2880000 hsize=2400 vsize=600
VDMA_MM2S_CONFIGURED base=0x43010000 frame_addr=0x0e100000 hsize=2400 stride=2400 vsize=600 frame_count=3
VDMA_MM2S_STATUS tag=after-config cr=0x00010003 sr=0x00011000 halted=0 idle=0 errors=0x000
```

GStreamer dashboard stream:

```text
pipeline.mode=gstreamer
pipeline.transport=rtp/jpeg
pipeline.sink=fbdevsink
stream_state=running
HDMI_RETURN_STREAM_READY endpoint=/api/output-stream.mjpeg
```

Direct HDMI capture:

```text
HDMI_CAPTURE_OK
validation_profile=pip-overlay
roi=[560,420,760,570]
border_white_pixels=1400
interior_yellow_pixels=4146
interior_stddev=67
```

Dashboard right-panel MJPEG return:

```text
MJPEG_STREAM_PROBE_OK frames=24 unique=23
PIP_OVERLAY_FRAMES_OK frames_checked=24 frames_passed=24
```

## Evidence

- `build/eth-ps-pl-hdmi-pass-through/sim/tb_axis_pip_overlay_core-xsim-run.log`
- `build/eth-ps-pl-hdmi-pass-through/sim/tb_axi_framebuffer_line_reader-xsim-run.log`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/vivado.log`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/eth_ps_vdma_hdmi_stage1_board.bit`
- `build/pl-dual-vdma-pip-mvp/linux-tools/vdma_mm2s_config`
- `build/pl-dual-vdma-pip-mvp/uart_post_reboot_probe2.log`
- `build/pl-dual-vdma-pip-mvp/uart_deploy_config_vdma1.log`
- `build/pl-dual-vdma-pip-mvp/uart_vdma1_status_after_stream.log`
- `build/pl-dual-vdma-pip-mvp/hdmi-pip-overlay-capture/latest.png`
- `build/pl-dual-vdma-pip-mvp/hdmi-pip-overlay-capture/validation.json`
- `build/pl-dual-vdma-pip-mvp/dashboard_start_stream.json`
- `build/pl-dual-vdma-pip-mvp/dashboard-mjpeg-pip/mjpeg-stream-probe.json`
- `build/pl-dual-vdma-pip-mvp/dashboard-mjpeg-pip/pip-overlay-validation.json`

## Board Action

The board was updated by replacing the TF-card `BOOT.BIN` only. The new
BOOT.BIN was served from the PC, downloaded by the already-running board Linux
system, SHA-256 verified, copied to `/run/media/mmcblk0p1/BOOT.BIN`, synced,
and rebooted.

The previous boot image remains on the board as:

```text
/run/media/mmcblk0p1/BOOT.BIN.prev-pl-pip-20260703
```

No `image.ub` or rootfs rebuild was deployed in this cycle. No QSPI, NAND,
eMMC, board flash, or JTAG programming action was used for the final update.

## Rollback

- Restore `/run/media/mmcblk0p1/BOOT.BIN.prev-pl-pip-20260703` to
  `/run/media/mmcblk0p1/BOOT.BIN` and reboot.
- The previous completed software route remains documented in
  `docs/reports/dashboard-gstreamer-chinese-control.md`.

## Residual Risks

- PIP geometry is fixed at build time.
- VDMA1 is configured by a `/dev/mem` userspace helper, not a formal Linux
  driver or device-tree-managed runtime control.
- The two VDMA readers are configured to the same framebuffer, but exact
  per-frame phase alignment is not measured.
- The source transport remains RTP/JPEG at 5fps; this cycle does not claim
  high-fps or high-quality compressed-video performance.
- Runtime PIP movement, rotation, scaling controls, and physical button/UART
  control are future work.

