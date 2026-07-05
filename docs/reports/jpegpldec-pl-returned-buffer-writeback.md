# jpegpldec PL-Returned Buffer Writeback

Date: 2026-07-05

Result: PASSED

## Objective

Keep the external RTP/JPEG GStreamer chain unchanged while proving that
`jpegpldec` can replace the downstream raw-video frame with bytes returned
from the PS-to-PL-to-PS DMA path.

The external chain remained:

```text
udpsrc -> rtpjitterbuffer -> rtpjpegdepay -> jpegpldec
-> videoconvert -> videoscale -> fbdevsink
```

## Implementation

- Added `probe-mode=dma-writeback`.
- In writeback mode, `jpegpldec` makes the decoded GstBuffer writable, copies
  the original I420 frame into a staging buffer, stamps a deterministic
  top-left I420 luma checker into that staging copy, submits the staging copy
  through `/dev/jpegpl_dma_probe`, then copies the coherent RX result back into
  the downstream GstBuffer.
- The original GstBuffer is not stamped before DMA. The HDMI-visible marker is
  therefore evidence that downstream GStreamer consumed the DMA-returned bytes,
  not the pre-DMA original buffer.
- The existing 14-bit BTT endpoint remains unchanged; the kernel driver still
  splits each 115200-byte logical frame into eight DMA transactions.
- The connected-board runner now serves artifacts with a PowerShell/.NET
  `TcpListener` file server and resets the PL DMA-probe core before the
  standalone precheck.

## Verification

Static/build checks:

```text
python -m py_compile tools/validate_jpegpldec_buffer_marker.py
PS_PARSE_OK for tools/run_jpegpldec_pl_probe.ps1
JPEGPLDEC_PLUGIN_BUILD_OK
```

Standalone connected-board precheck:

```text
JPEGPL_DMA_PROBE_TEST_OK length=115200 checksum=0xb753e545
```

Continuous real-video writeback run:

```text
probe-mode=dma-writeback
logical decoded frames: 60
bytes per frame: 115200
DMA transactions per frame: 8
reported DMA failures: 0
JPEGPLDEC_PROFILE frames=60 mode=dma-writeback
PL_DMA_FRAMES=0x000001E0
PL_DMA_BYTES=0x00697800
PL_DMA_LAST_FRAME_BYTES=0x0000021C
```

The UART stop log retained 56 per-frame `JPEGPLDEC_DMA_WRITEBACK ... result=pass`
lines while the final profile marker and PL counters prove the full 60 logical
frames and 480 PL DMA transactions. No `result=fail` line was present.

HDMI dynamic validation on the passing evidence set:

```text
sample_count=300
unique_hashes=104
frames_with_ball=300
centroid_span=264.944
HDMI_BALL_MOTION_OK
```

HDMI writeback-marker validation:

```text
frames=300
pass_frames=224
JPEGPLDEC_BUFFER_MARKER_OK
```

Raw evidence is under `build/jpegpldec-dma-writeback/`, especially
`summary.json`, `uart-stop-dma-probe.log`, `hdmi-ball-motion-validation.json`,
and `dma-writeback-marker-validation.json`.

## Decision

The PL-returned GstBuffer writeback gate is closed. The next step may replace
the staging luma marker with a deterministic PL-side pixel modification, then
move toward a useful PL processing primitive.

This cycle still does not claim zero-copy or JPEG decode acceleration. The
path copies from GstBuffer to a staging buffer, through kernel coherent DMA
buffers, and back into the downstream GstBuffer.

## Board Action

Loaded `jpegpl_dma_probe.ko` and `libgstjpegpldec.so` into `/tmp`, ran the RTP
receiver and HDMI capture, then stopped the receiver. No BOOT.BIN, image.ub,
TF-card boot file, JTAG, QSPI, NAND, eMMC, or other nonvolatile image was
changed.

## Rollback

Code rollback is the parent of this cycle commit. Runtime rollback is a board
reboot, because the module and plugin were loaded from `/tmp` only.
