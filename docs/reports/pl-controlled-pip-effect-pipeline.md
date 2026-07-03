# PL Controlled PIP Effect Pipeline Report

Date: 2026-07-04

Result: PASSED

## Objective

Complete the controllable PL-side PIP effect MVP on the current GStreamer
closed loop:

- PIP enable/bypass.
- PIP x/y position presets.
- PIP scale presets: 1/2 and 1/4.
- Border enable.
- Small-window effect presets: normal, invert, grayscale.
- Linux userspace control through `/dev/mem` AXI-Lite register writes.
- Dashboard buttons trigger the presets through UART.

## Implemented Route

```text
PC GStreamer moving-ball source
-> RTP/JPEG over Ethernet
-> board GStreamer receiver
-> fbdevsink /dev/fb0
-> VDMA0 MM2S main stream
-> VDMA1 MM2S same-framebuffer PIP stream
-> axis_pip_overlay_core with AXI-Lite control
-> v_axi4s_vid_out + HDMI
-> PC HDMI capture adapter
-> dashboard right-panel MJPEG return
```

## Changed Scope

- Added an AXI4-Lite `S_AXI` control interface to `axis_pip_overlay_core`.
- Added registers for enable, border, scale, effect, x/y position, geometry,
  frame counters, and overlay pixel counters.
- Added runtime PIP scale selection for 1/2 and 1/4.
- Added PIP small-window effects: normal, invert, and grayscale.
- Added `pip_effect_ctl`, a Linux `/dev/mem` control utility for presets and
  status readback.
- Connected the PIP control interface in the Vivado block design at
  `0x43c00000`.
- Added dashboard PIP preset buttons and UART action binding.
- Increased dashboard PIP preset UART timeout from 8 seconds to 20 seconds
  after the live board action timed out despite the same serial path working
  directly.

## Verification

Simulation:

```text
AXI_FRAMEBUFFER_LINE_READER_OK
PL_CONTROLLED_PIP_CORE_SIM_OK default_overlay=12 half_overlay=48 grayscale_overlay=12
PL_DUAL_VDMA_PIP_CORE_SIM_OK overlay_pixels=12 border_pixels=10 pip_content_pixels=2 main_pixels=180
SIM_OK
```

Vivado build:

```text
STAGE1_VDMA_BOARD_BUILD_OK
WNS=0.197
TNS=0.000
failing_endpoints=0
post-route DRC errors=0
```

Linux helper build:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
VIDEO_CONTROL_TEST_OK
VIDEO_EFFECT_TEST_OK
VDMA_MM2S_CONFIG_BUILD_OK
PIP_EFFECT_CTL_BUILD_OK
```

BOOT.BIN packaging and board update:

```text
BOOT.BIN SHA256=8981abbdb2a1c823c2397cf0eb9a69cb066e8e21f7a969287d8940a5d77c5924
PL_CONTROLLED_PIP_BOOTBIN_UPDATE_OK
```

Board post-reboot probe:

```text
/dev/fb0 exists
/dev/dri/card0 exists
xilinx-vdma 43000000.dma probed
xlnx-pl-disp probed
xlnx-fixed-hdmi bound with mode 800x600
PL_CONTROLLED_PIP_POST_REBOOT_PROBE_DONE
```

VDMA1 and PIP control status:

```text
VDMA_MM2S_CONFIGURED base=0x43010000 frame_addr=0x0e100000 hsize=2400 stride=2400 vsize=600 frame_count=3
VDMA_MM2S_STATUS tag=after-config cr=0x00010003 sr=0x00011000 halted=0 idle=0 errors=0x000
PIP_EFFECT_STATUS tag=status-only control=0x00000007 enable=1 border=1 scale=4 effect=0 x=560 y=420 active_w=200 active_h=150
```

Dashboard button actions through UART:

```text
pip-top-left:     ok=True enable=1 scale=4 effect=0 x=16  y=16
pip-bottom-right: ok=True enable=1 scale=4 effect=0 x=560 y=420
pip-large:        ok=True enable=1 scale=2 effect=0 x=360 y=260 active_w=400 active_h=300
pip-invert:       ok=True enable=1 scale=4 effect=1 x=560 y=420
pip-grayscale:    ok=True enable=1 scale=4 effect=2 x=560 y=420
pip-bypass:       ok=True enable=0 scale=4 effect=0 x=560 y=420
```

GStreamer dashboard stream:

```text
ACTION_OK action=start-stream
pipeline.mode=gstreamer
pipeline.transport=rtp/jpeg
pipeline.sink=fbdevsink
stream_state=running
HDMI_RETURN_STREAM_READY endpoint=/api/output-stream.mjpeg
```

Direct HDMI physical-output validation:

```text
pip-bypass capture: HDMI_CAPTURE_FAIL under pip-overlay profile,
  pip_white_border pixels=0. This is the expected negative check.

pip-bottom-right restored capture: HDMI_CAPTURE_OK under pip-overlay profile,
  pip_white_border pixels=1400,
  yellow_pixels=4278,
  interior_stddev=67.
```

Dashboard right-panel MJPEG return:

```text
MJPEG_STREAM_PROBE_OK frames=24 unique=21
PIP_OVERLAY_FRAMES_OK frames_checked=24 frames_passed=24
```

## Evidence

- `build/eth-ps-pl-hdmi-pass-through/sim/tb_axis_pip_overlay_core-xsim-run.log`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/timing_summary.rpt`
- `build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/post_route_drc.rpt`
- `build/pl-controlled-pip-effect-pipeline/boot/BOOT.BIN`
- `build/pl-controlled-pip-effect-pipeline/uart_update_bootbin.log`
- `build/pl-controlled-pip-effect-pipeline/uart_post_reboot_probe.log`
- `build/pl-controlled-pip-effect-pipeline/uart_deploy_config_tools.log`
- `build/pl-controlled-pip-effect-pipeline/dashboard_action_pip_*.json`
- `build/pl-controlled-pip-effect-pipeline/dashboard_start_stream.json`
- `build/pl-controlled-pip-effect-pipeline/hdmi-pip-bypass-capture/latest-validation.json`
- `build/pl-controlled-pip-effect-pipeline/hdmi-pip-restored-capture/latest-validation.json`
- `build/pl-controlled-pip-effect-pipeline/dashboard-mjpeg-pip/mjpeg-stream-probe.json`
- `build/pl-controlled-pip-effect-pipeline/dashboard-mjpeg-pip/pip-overlay-validation.json`

## Board Action

The board was updated by replacing the TF-card `BOOT.BIN` only. The new
BOOT.BIN was served from the PC, downloaded by the already-running board Linux
system, SHA-256 verified, copied to `/run/media/mmcblk0p1/BOOT.BIN`, synced,
and rebooted.

The previous boot image remains on the board as:

```text
/run/media/mmcblk0p1/BOOT.BIN.prev-controlled-pip-20260704
```

No `image.ub` or rootfs rebuild was deployed in this cycle. No QSPI, NAND,
eMMC, board flash, or JTAG programming action was used for the final update.

## Rollback

- Restore `/run/media/mmcblk0p1/BOOT.BIN.prev-controlled-pip-20260704` to
  `/run/media/mmcblk0p1/BOOT.BIN` and reboot.
- The previous fixed-PIP route remains documented in
  `docs/reports/pl-dual-vdma-pip-mvp.md`.

## Residual Risks

- PIP control is exposed through a userspace `/dev/mem` helper, not a Linux
  kernel driver.
- Grayscale is implemented as a green-channel luma approximation to keep timing
  closed on this device.
- Position and scale are preset-based for this MVP; arbitrary continuous UI
  sliders and rotation are future work.
- The transport remains RTP/JPEG at 5fps; this cycle does not claim high-fps
  transport quality.
