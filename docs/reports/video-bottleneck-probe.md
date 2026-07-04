# Video Bottleneck Probe Report

Date: 2026-07-04

Result: PASSED for bottleneck measurement.

## Objective

Measure the current video path before deciding whether PL-side decode is the
right next implementation target.

The probe compares:

- RTP/JPEG decode + convert + scale to `fakesink`.
- RTP/JPEG decode + convert + scale + framebuffer write to `fbdevsink`.
- Raw framebuffer-native direct-copy as a live network/receiver contrast.

## Current Tested Parameters

JPEG/GStreamer cases:

```text
PC source: videotestsrc ball
Input to board: 320x240 RTP/JPEG, quality=90, UDP 5011
Board decode path: udpsrc -> rtpjitterbuffer -> rtpjpegdepay -> jpegdec
  -> videoconvert -> videoscale -> 800x600 BGR
Sinks tested: fakesink and fbdevsink /dev/fb0
Rates tested: 5, 10, 15, 30 fps
Duration per case: 6 seconds
```

Raw/direct-copy contrast:

```text
Input to board: 800x600 framebuffer-native 24bpp UDP
Receiver: fb_video_udp_receiver direct-memcpy into /dev/fb0
Requested rate: 15 fps
```

## Results

JPEG to `fakesink`:

| Requested fps | Rendered | Dropped | Board average fps | gst-launch CPU % |
| --- | ---: | ---: | ---: | ---: |
| 5 | 29 | 0 | 5.30 | 3.90 |
| 10 | 57 | 0 | 10.24 | 7.44 |
| 15 | 83 | 0 | 15.55 | 11.46 |
| 30 | 176 | 0 | 30.50 | 20.48 |

JPEG to `fbdevsink`:

| Requested fps | Rendered | Dropped | Board average fps | gst-launch CPU % |
| --- | ---: | ---: | ---: | ---: |
| 5 | 29 | 0 | 5.30 | 4.12 |
| 10 | 57 | 0 | 10.24 | 8.16 |
| 15 | 83 | 0 | 15.56 | 13.06 |
| 30 | 155 | 0 | 27.69 | 22.98 |

Raw/direct-copy live contrast:

```text
VIDEO_UDP_RECEIVER_DONE frames=42 skipped=0 packets=50400 dropped=0 elapsed_ms=22921
eth0 RX errors=0 dropped=0
```

The raw/direct-copy receiver path passed, but the HDMI/MJPEG trace validation
in this rerun failed: the return capture reported `unique_colors=1` and
`matched_frames=0`. Treat this as a return/capture validation failure, not a
raw receiver throughput failure.

## Interpretation

The current 5fps GStreamer setting is not yet proven to be a PS hard limit.
Under the current low-resolution compressed input condition, the board accepted
320x240 RTP/JPEG at 30fps through software JPEG decode, conversion, scaling,
and `fakesink`. Adding framebuffer output reduced the measured rate to about
27.7fps, still far above the configured 5fps.

The first-order bottleneck shown by this probe is therefore not simply:

```text
PS cannot decode current 320x240 JPEG above 5fps.
```

The more defensible conclusion is:

```text
Current demo is configured conservatively at 320x240@5fps.
At 320x240 input, PS software JPEG decode plus scale is not saturated at 5fps.
fbdevsink/framebuffer output starts to cost measurable throughput near 30fps.
```

This does not disprove the value of PL-side decode for higher resolutions.
It means PL decode should be justified by the next tests, such as 800x600
JPEG input, higher quality JPEG, or a real 30fps HDMI-return validation target.

## Evidence

- `build/video-bottleneck-probe/video-bottleneck-summary.json`
- `build/video-bottleneck-probe/video-bottleneck.marker.txt`
- `build/video-bottleneck-probe/uart-stop-jpeg-fakesink-*.log`
- `build/video-bottleneck-probe/uart-stop-jpeg-fbdevsink-*.log`
- `build/video-bottleneck-probe/raw-direct-copy/uart_after_direct_copy.log`
- `build/video-bottleneck-probe/raw-direct-copy/trace/trace-build-result.json`

## Board Action

- Ran temporary board-side GStreamer receiver pipelines from UART.
- Killed stale `gst-launch-1.0` processes before each case.
- Ran a live raw/direct-copy receiver probe using the existing receiver helper.
- No `BOOT.BIN`, `image.ub`, rootfs, bitstream, or board flash was changed.

## Residual Risks

- The JPEG probe measured 320x240 input scaled to 800x600. It does not measure
  800x600 JPEG decode.
- CPU percentage is derived from `/proc/stat` and `/proc/<pid>/stat` around
  each case; it is useful as a relative signal, not a lab-grade profiler.
- The raw/direct-copy HDMI return trace failed in this rerun, so the raw result
  is receiver-throughput evidence only.
- The HDMI/UVC return path may still be a separate bottleneck and needs its
  own controlled probe.
