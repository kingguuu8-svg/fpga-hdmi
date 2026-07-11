# jpegpldec 720p30 Contract

## Purpose

This document fixes the first real target for the `jpegpldec` PL decoder route.
The long-term goal may scale beyond this, but the first PL decoder step targets
720p30 rather than a 320x240-only implementation.

The contract is intentionally about the decoder boundary, not the current PIP
effect path:

```text
PC source
-> RTP/JPEG over Ethernet
-> board GStreamer rtpjpegdepay
-> jpegpldec
-> raw video buffer
-> existing display path
```

## First Target

| Field | Value |
| --- | --- |
| Resolution | 1280x720 |
| Frame rate | 30 fps |
| Compressed format | Baseline MJPEG carried as RTP/JPEG |
| First decoder entry | `jpegpldec` |
| Reference backend | internal software `jpegdec` child |
| PL backend target | compressed JPEG input to raw video output |
| First board backend raw output | See `docs/project-roadmap.md` |
| Display output | current HDMI path until a 720p HDMI mode is separately proven |

The first target is not the final ceiling. A passing 720p30 result is the base
for later 1080p30, 720p60, or 1080p60 investigations.

The first board backend publishes the native raw output specified by
`docs/project-roadmap.md`. Converting that frame to a different planar format
inside `jpegpldec` and back again at the current framebuffer sink would add ARM
work without proving more PL decode functionality. A different planar or native
DMA-buffer output remains a later throughput optimization, not a v1 gate.

## JPEG Profile

The first PL decoder may restrict JPEG support, but must not hard-code a
320x240 frame shape.

Allowed first profile:

```text
baseline sequential JPEG
8-bit samples
YCbCr 4:2:0
non-progressive
non-CMYK
single scan
fixed or parsed quantization tables
fixed or parsed Huffman tables
optional restart interval, recorded when present
```

Required rejection behavior:

```text
unsupported profile -> explicit decoder error or fallback to software backend
bad frame size -> explicit decoder error
truncated entropy stream -> explicit decoder error
unsupported sampling -> explicit decoder error or fallback
```

## Decoder Boundary

The PL decoder boundary must be defined around compressed input and raw output:

```text
input:
  compressed JPEG GstBuffer
  frame_id
  input_size
  width
  height
  jpeg_profile_flags
  optional restart_interval

output:
  raw frame buffer
  output_format
  output_stride
  output_size
  status
  error_code
```

Do not define the PL decoder as a post-`jpegdec` raw-buffer filter. That path
already exists as the `dma-probe` and `dma-writeback` gates; it proves the data
plane, not JPEG decode acceleration.

## Required Counters

The PL decoder route must expose enough counters to compare against the
software reference path:

```text
frame_id
bytes_in
bytes_out
cycles_total
cycles_parse
cycles_entropy
cycles_idct
mcu_count
restart_count
decode_errors
fallback_frames
dma_transactions
dma_bytes
```

The first implementation may leave a counter at zero only if the report says
that stage is not implemented yet.

## Gate Tiers

Tier 0 is historical evidence, not the new target:

```text
320x240 RTP/JPEG at 30 fps through software decode and 800x600 output scaling
```

Tier 1 is the next gate:

```text
1280x720 RTP/JPEG at 30 fps
-> jpegpldec software reference backend
-> fakesink measurement
```

Tier 2 adds the current display path:

```text
1280x720 RTP/JPEG at 30 fps
-> jpegpldec software reference backend
-> current fbdev/HDMI path
```

Tier 3 is a separate display-mode gate:

```text
1280x720 HDMI output mode, without relying on 800x600 downscale
```

Tier 4 is the first real PL decoder target:

```text
1280x720 RTP/JPEG at 30 fps
-> jpegpldec PL backend
-> raw output equivalent to software reference
```

## Acceptance Evidence

Each 720p30 gate report must record:

```text
input resolution and fps
average compressed frame bytes
raw output bytes
requested fps
actual rendered fps
drop count
jpegpldec avg/p50/p95/max boundary time when available
board gst-launch CPU percent
sink used: fakesink, fbdevsink, DRM/KMS, or HDMI capture
whether the output is native 720p or downscaled to the current HDMI mode
```

For this cycle, a gate is allowed to close as `BLOCKED` only if it records the
exact blocker and keeps the next implementation decision clear.
