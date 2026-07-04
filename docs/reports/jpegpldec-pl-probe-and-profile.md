# jpegpldec PL Probe and Profile

Cycle ID: jpegpldec-pl-probe-and-profile

Date: 2026-07-04

## Objective

Upgrade the project-owned `jpegpldec` GStreamer element from a bare software
wrapper into a measurable hardware-acceleration entry point. The external
pipeline remains:

```text
rtpjpegdepay ! jpegpldec ! videoconvert ! videoscale ! fbdevsink
```

This cycle intentionally does not implement PL JPEG decode. It establishes the
profiling and PL probe hooks needed to decide the next hardening step with
measured data.

## Changed Scope

- Added pad-level profiling inside `jpegpldec`.
- Added `probe-mode`, `summary-interval`, `pl-base`, and `pl-map-size`
  properties.
- Added `probe-mode=pl-probe`, which reads the existing PL PIP AXI-Lite status
  registers through `/dev/mem` while the live video pipeline is running.
- Added `tools/run_jpegpldec_pl_probe.ps1` as the repeatable cycle probe.
- Updated `software/gstreamer/jpegpldec/README.md`.

## Verification

Integrated probe:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -HttpPort 8093 -OutDir build\jpegpldec-pl-probe-and-profile
```

Observed:

```text
JPEGPLDEC_PLUGIN_BUILD_OK
JPEGPLDEC_PL_PROBE_HTTP_SERVER pid=32172 port=8093
JPEGPLDEC_DEPLOY_INSPECT_DONE
JPEGPLDEC_PROFILE_RECEIVER_STARTED pid=5176 log=/tmp/gst_jpegpldec_profile.log
MJPEG_STREAM_PROBE_OK frames=60 unique=46
JPEGPLDEC_PL_PROBE_OK
```

Artifact:

```text
libgstjpegpldec.so: ELF 32-bit LSB shared object, ARM, EABI5
sha256=1a5072ab049f460ecb5c9a733831ec60798d5111f9fb8ea4e31bf0226883d42c
```

Board `gst-inspect-1.0 jpegpldec` showed the new properties:

```text
probe-mode
summary-interval
pl-base
pl-map-size
Children: software-reference-decoder
```

Live receiver pipeline:

```text
udpsrc port=5011 caps=application/x-rtp,...
! rtpjitterbuffer latency=100 drop-on-latency=true
! rtpjpegdepay
! jpegpldec probe-mode=pl-probe summary-interval=30
! videoconvert
! videoscale
! video/x-raw,format=BGR,width=800,height=600
! fbdevsink device=/dev/fb0 sync=false
```

Representative profile markers:

```text
JPEGPLDEC_PROFILE frames=120 mode=pl-probe last_ms=1.705 avg_ms=1.927 p50_ms=1.716 p95_ms=1.935 max_ms=21.732 avg_in_bytes=6119.0 avg_out_bytes=115200.0 pending=0
JPEGPLDEC_PROFILE frames=180 mode=pl-probe last_ms=1.691 avg_ms=1.873 p50_ms=1.715 p95_ms=1.939 max_ms=21.732 avg_in_bytes=6107.7 avg_out_bytes=115200.0 pending=0
JPEGPLDEC_PROFILE frames=210 mode=pl-probe last_ms=1.715 avg_ms=1.856 p50_ms=1.716 p95_ms=1.935 max_ms=21.732 avg_in_bytes=6106.7 avg_out_bytes=115200.0 pending=0
```

Representative PL probe markers:

```text
JPEGPLDEC_PL_PROBE_READY base=0x43c00000 map_size=0x00010000
JPEGPLDEC_PL_PROBE frame=120 control=0x00000007 enable=1 scale=4 effect=0 x=16 y=16 active_w=200 active_h=150 main_frames=2828305 pip_frames=4979877 overlay_pixels=3590925671
JPEGPLDEC_PL_PROBE frame=180 control=0x00000007 enable=1 scale=4 effect=0 x=16 y=16 active_w=200 active_h=150 main_frames=2828462 pip_frames=4980689 overlay_pixels=3595635671
JPEGPLDEC_PL_PROBE frame=210 control=0x00000007 enable=1 scale=4 effect=0 x=16 y=16 active_w=200 active_h=150 main_frames=2828539 pip_frames=4981084 overlay_pixels=3597915671
```

Dashboard HDMI-return stream:

```text
MJPEG_STREAM_PROBE_OK frames=60 unique=46 colors=not-checked
```

## Board Action

- Deployed `/tmp/gst-plugins/libgstjpegpldec.so` over Ethernet using board
  `wget`.
- Loaded the plugin through `GST_PLUGIN_PATH=/tmp/gst-plugins`.
- Killed the previous temporary `gst-launch-1.0` receiver and started a new
  `jpegpldec probe-mode=pl-probe` receiver.
- Reused the already-running PC GStreamer sender and dashboard HDMI/UVC return.
- No BOOT.BIN, image.ub, rootfs, FPGA bitstream, TF-card image, JTAG
  programming, or board flash write was performed.

## Decision

The current 320x240 MJPEG decode wrapper timing is not the dominant bottleneck
at the observed live setting. The steady-state `jpegpldec` wrapper interval was
about:

```text
avg_ms ~= 1.86 ms
p50_ms ~= 1.72 ms
p95_ms ~= 1.94 ms
```

There was one startup/outlier value captured in `max_ms=21.725`; steady-state
markers after frame 120 remained close to 2 ms.

The next PL-hardening step should not start with a full JPEG decoder. The
measured result supports this order:

1. Add higher-resolution profiling before claiming JPEG decode as the main
   bottleneck.
2. Keep `jpegpldec` as the stable GStreamer entry point.
3. Add a real PS-to-PL buffer/data probe behind `jpegpldec` before replacing
   `software-reference-decoder`.
4. Only after the buffer path is measured, decide whether to harden JPEG
   decode, colorspace conversion, scaling, or framebuffer/display write.

## Result

PASSED.

The project now has a repeatable `jpegpldec` profiling and PL status-probe
cycle. It proves:

- the plugin can measure per-frame software reference decode boundary timing;
- the plugin can access live PL PIP status registers during video streaming;
- the external RTP/JPEG-to-HDMI pipeline remains operational;
- the HDMI-return MJPEG stream remains dynamic.

It does not prove:

- compressed JPEG data movement through PL;
- PL JPEG decode;
- latency improvement;
- higher-resolution performance.

## Evidence

- `tools/run_jpegpldec_pl_probe.ps1`
- `build/jpegpldec-pl-probe-and-profile/summary.json`
- `build/jpegpldec-pl-probe-and-profile/plugin/libgstjpegpldec.file.txt`
- `build/jpegpldec-pl-probe-and-profile/plugin/libgstjpegpldec.sha256.txt`
- `build/jpegpldec-pl-probe-and-profile/uart-deploy-inspect.log`
- `build/jpegpldec-pl-probe-and-profile/uart-start-profile.log`
- `build/jpegpldec-pl-probe-and-profile/dashboard-output-mjpeg-probe/mjpeg-stream-probe.json`

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

- The PL probe is a control/status-plane probe through the existing PIP
  AXI-Lite registers. It is not a PS-to-PL JPEG buffer data path.
- The profiling value currently covers `jpegpldec` input-to-output timing
  around the internal `jpegdec` child, not downstream `videoconvert`,
  `videoscale`, or `fbdevsink`.
- The measurement used the current 320x240 RTP/JPEG sender. It should be
  repeated at higher source resolution before choosing a PL JPEG decode
  implementation strategy.
