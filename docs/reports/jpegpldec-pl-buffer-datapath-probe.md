# jpegpldec PL Buffer Datapath Probe

Cycle ID: jpegpldec-pl-buffer-datapath-probe

Date: 2026-07-04

## Objective

Move from pure `jpegpldec` control/status probing toward a real video data
probe. The external GStreamer pipeline remains unchanged:

```text
rtpjpegdepay ! jpegpldec ! videoconvert ! videoscale ! fbdevsink
```

This cycle proves that `jpegpldec` can access and modify the decoded raw video
buffer, and that the modification reaches the existing framebuffer -> VDMA ->
PL PIP -> HDMI data path. It does not yet prove an independent private
DMA-safe buffer, PL writeback, or a GStreamer buffer returned from PL.

## Changed Scope

- Added `probe-mode=buffer-probe` and `probe-mode=pl-buffer-probe` to
  `jpegpldec`.
- In buffer probe mode, `jpegpldec` maps the decoded `I420` output buffer,
  computes checksums, stamps a 24x24 top-left luma checker marker, and emits
  `JPEGPLDEC_BUFFER_PROBE` markers.
- `probe-mode=pl-buffer-probe` also keeps the existing PL PIP AXI-Lite status
  sampling from `probe-mode=pl-probe`.
- Extended `tools/run_jpegpldec_pl_probe.ps1` with `-ProbeMode`.
- Added `tools/validate_jpegpldec_buffer_marker.py` to validate the marker in
  saved HDMI-return MJPEG frames.
- Updated `software/gstreamer/jpegpldec/README.md`.

## Verification

Integrated probe:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode pl-buffer-probe -HttpPort 8095 -OutDir build\jpegpldec-pl-buffer-datapath-probe
```

Observed:

```text
JPEGPLDEC_PLUGIN_BUILD_OK
JPEGPLDEC_DEPLOY_INSPECT_DONE
JPEGPLDEC_PROFILE_RECEIVER_STARTED pid=5718 log=/tmp/gst_jpegpldec_profile.log
MJPEG_STREAM_PROBE_OK frames=60 unique=40
JPEGPLDEC_BUFFER_MARKER_OK frames=60 pass_frames=60
JPEGPLDEC_PL_PROBE_OK
```

Artifact:

```text
libgstjpegpldec.so: ELF 32-bit LSB shared object, ARM, EABI5
sha256=e70c99131ae07753afb79241571f8174fcc82454fd99dc086661c009380bdd36
```

Board pipeline:

```text
udpsrc port=5011 caps=application/x-rtp,...
! rtpjitterbuffer latency=100 drop-on-latency=true
! rtpjpegdepay
! jpegpldec probe-mode=pl-buffer-probe summary-interval=30
! videoconvert
! videoscale
! video/x-raw,format=BGR,width=800,height=600
! fbdevsink device=/dev/fb0 sync=false
```

Representative decoded-buffer markers:

```text
JPEGPLDEC_BUFFER_PROBE frame=60 mode=pl-buffer-probe format=I420 width=320 height=240 bytes=115200 checksum_before=0x09f74098 checksum_after=0xacab2538 stamp=top-left-i420-luma-checker result=pass elapsed_ms=2.075 avg_ms=2.282 max_ms=3.056
JPEGPLDEC_BUFFER_PROBE frame=90 mode=pl-buffer-probe format=I420 width=320 height=240 bytes=115200 checksum_before=0x2b5561a7 checksum_after=0x0c2fd107 stamp=top-left-i420-luma-checker result=pass elapsed_ms=2.110 avg_ms=2.289 max_ms=3.059
JPEGPLDEC_BUFFER_PROBE frame=120 mode=pl-buffer-probe format=I420 width=320 height=240 bytes=115200 checksum_before=0xbccef774 checksum_after=0xb73e61f4 stamp=top-left-i420-luma-checker result=pass elapsed_ms=2.072 avg_ms=2.286 max_ms=3.059
```

Representative PL status markers:

```text
JPEGPLDEC_PL_PROBE frame=60 control=0x00000007 enable=1 scale=4 effect=0 x=560 y=420 active_w=200 active_h=150 main_frames=3249345 pip_frames=7160869 overlay_pixels=3337223783
JPEGPLDEC_PL_PROBE frame=90 control=0x00000007 enable=1 scale=4 effect=0 x=560 y=420 active_w=200 active_h=150 main_frames=3249435 pip_frames=7161337 overlay_pixels=3339923783
JPEGPLDEC_PL_PROBE frame=120 control=0x00000007 enable=1 scale=4 effect=0 x=560 y=420 active_w=200 active_h=150 main_frames=3249526 pip_frames=7161806 overlay_pixels=3342653783
```

HDMI-return marker validation:

```text
JPEGPLDEC_BUFFER_MARKER_OK frames=60 pass_frames=60
```

The validator checks the top-left HDMI-return crop for the high-contrast luma
checker that `jpegpldec` stamped into the decoded I420 buffer.

## Board Action

- Deployed `/tmp/gst-plugins/libgstjpegpldec.so` over Ethernet using board
  `wget`.
- Moved the existing PL PIP window to bottom-right with `/tmp/pip_effect_ctl`
  so it would not cover the top-left buffer marker.
- Restarted the board `gst-launch-1.0` receiver with
  `jpegpldec probe-mode=pl-buffer-probe`.
- Reused the already-running PC GStreamer sender and dashboard HDMI/UVC return.
- No BOOT.BIN, image.ub, rootfs, FPGA bitstream, TF-card image, JTAG
  programming, or board flash write was performed.

## Result

PARTIAL PASS toward the larger PS-to-PL buffer objective.

Proved:

- `jpegpldec` can map real decoded `I420` video buffers.
- The decoded buffer checksum changes after the probe marker is stamped.
- The marked buffer continues through downstream GStreamer elements.
- The marker is visible in physical HDMI-return MJPEG frames.
- The existing PL PIP/VDMA status counters continue advancing while the marked
  buffer stream is active.

Not proved:

- A private DMA-safe buffer allocated inside `jpegpldec`.
- PL reading a `jpegpldec`-owned buffer directly.
- PL writing a result back to `jpegpldec`.
- Cache flush/invalidate correctness for a PS-owned buffer shared directly with
  PL.
- Returning a PL-modified buffer to downstream GStreamer.

## Decision

Do not proceed directly to PL JPEG decode yet.

The current bitstream already contains a mature data path from framebuffer DDR
through VDMA into the PL PIP/HDMI pipeline, but it does not expose a generic
`jpegpldec` private buffer -> PL -> `jpegpldec` return path. The next real
hardening step requires adding or exposing one of these:

- AXI DMA or VDMA S2MM/MM2S path for `jpegpldec`-owned buffers;
- a Linux DMA-safe allocation path such as CMA/dma-buf/udmabuf or a small
  kernel driver;
- PL checksum/passthrough registers or stream endpoints that report exact data
  received from the buffer path.

Until that exists, PL JPEG decode would be a black-box integration risk.

## Evidence

- `tools/run_jpegpldec_pl_probe.ps1`
- `tools/validate_jpegpldec_buffer_marker.py`
- `build/jpegpldec-pl-buffer-datapath-probe/summary.json`
- `build/jpegpldec-pl-buffer-datapath-probe/plugin/libgstjpegpldec.file.txt`
- `build/jpegpldec-pl-buffer-datapath-probe/plugin/libgstjpegpldec.sha256.txt`
- `build/jpegpldec-pl-buffer-datapath-probe/uart-deploy-inspect.log`
- `build/jpegpldec-pl-buffer-datapath-probe/uart-start-profile.log`
- `build/jpegpldec-pl-buffer-datapath-probe/dashboard-output-mjpeg-probe/mjpeg-stream-probe.json`
- `build/jpegpldec-pl-buffer-datapath-probe/buffer-marker-validation.json`

## Rollback

Stop the temporary receiver with:

```sh
killall gst-launch-1.0
```

Then restart the dashboard stream action to return to the dashboard-managed
receiver path. No persistent board image changed.

## Third-Party Review

None.

## Residual Risks

- This is not a DMA-safe PS-to-PL buffer loopback.
- The HDMI marker proves end-to-end visual propagation through the existing
  framebuffer/VDMA/PL display path, not direct PL access to `GstBuffer` memory.
- The marker adds roughly 2.3 ms average overhead at 320x240 because it maps
  and hashes the full decoded buffer in userspace.
- A true PL accelerator still needs a coherent buffer strategy and a PL
  data-return mechanism.
