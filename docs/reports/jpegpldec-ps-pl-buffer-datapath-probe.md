# jpegpldec PS-to-PL Buffer Data-Path Probe

Date: 2026-07-05

Result: PASSED

## Objective

Keep the external RTP/JPEG GStreamer chain unchanged while sending every real
decoded raw frame through a PL-accessible coherent buffer path inside
`jpegpldec`. Verify continuous byte identity, cache safety, PL counters, and
dynamic HDMI output, then decide whether PL writeback should proceed.

## Implementation

- Added `probe-mode=dma-probe` to `jpegpldec`.
- The plugin maps each decoded raw buffer read-only, submits it through
  `/dev/jpegpl_dma_probe`, compares host/input/output FNV-1a checksums and all
  returned bytes, and leaves the original GstBuffer on the existing downstream
  path.
- The kernel client uses coherent TX/RX buffers and DMAengine MM2S/S2MM.
- The existing 14-bit AXI DMA BTT endpoint accepts at most 16383 bytes. The
  driver therefore keeps one logical ioctl per frame while issuing aligned
  16380-byte transactions internally.
- The connected-board helper now builds/deploys the module and plugin, runs a
  full-frame precheck, sends a deterministic moving-ball RTP/JPEG stream,
  checks PL counters, and validates dynamic HDMI capture.

The external chain remained:

```text
udpsrc -> rtpjitterbuffer -> rtpjpegdepay -> jpegpldec
-> videoconvert -> videoscale -> fbdevsink
```

## Verification

Simulation regression passed:

```text
AXI_FRAMEBUFFER_LINE_READER_OK
PL_CONTROLLED_PIP_CORE_SIM_OK
PL_DUAL_VDMA_PIP_CORE_SIM_OK
AXIS_DMA_PROBE_CORE_SIM_OK
SIM_OK
```

A trial 17-bit DMA BTT build was rejected because timing failed with WNS
`-0.101 ns`. It was not deployed. The checked-in hardware configuration remains
the previously timed 14-bit endpoint; driver-internal chunking avoids changing
that known-good bitstream.

Standalone connected-board precheck:

```text
JPEGPL_DMA_PROBE_TEST_OK length=115200 checksum=0xb753e545
```

Continuous real-video run:

```text
logical decoded frames: 60
bytes per frame: 115200
DMA transactions per frame: 8
reported DMA failures: 0
JPEGPLDEC_PROFILE frames=60 mode=dma-probe
PL_DMA_FRAMES=0x000001E0
PL_DMA_BYTES=0x00697800
PL_DMA_LAST_FRAME_BYTES=0x0000021C
```

The PL counters correspond to 480 transactions, 6,912,000 total bytes, and a
540-byte final transaction. Every inspected frame marker reported equal host,
DMA-input, and DMA-output checksums with `result=pass`. The UART evidence file
retained 59 per-frame lines while the plugin profile and PL counters both prove
all 60 logical frames; no `result=fail` line was present.

Dynamic HDMI return validation:

```text
sample_count=300
unique_hashes=121
frames_with_ball=300
centroid_span=270.141
HDMI_BALL_MOTION_OK
JPEGPLDEC_PL_PROBE_OK
```

Raw evidence is under `build/jpegpldec-dma-buffer-probe/`, especially
`summary.json`, `uart-stop-dma-probe.log`, and
`hdmi-ball-motion-validation.json`.

## Decision

Proceed to PL writeback and GStreamer reconnection in the next cycle. The
coherent PS-to-PL-to-PS data plane is now proven with complete real frames and
continuous video. The next implementation should copy or wrap the verified PL
return buffer into the downstream GstBuffer and prove a deterministic PL
marker/effect at HDMI.

This cycle does not claim zero-copy or writeback completion. It still performs
userspace-to-coherent and coherent-to-userspace copies, and downstream display
uses the original decoded GstBuffer.

## Board Action

Loaded `jpegpl_dma_probe.ko` and `libgstjpegpldec.so` into `/tmp`, ran the RTP
receiver and HDMI capture, then stopped the receiver. No BOOT.BIN, image.ub,
TF-card boot file, JTAG, QSPI, NAND, eMMC, or other nonvolatile image was
changed.

## Rollback

Code rollback is the parent of this cycle commit. Runtime rollback is a board
reboot, because the module and plugin were loaded from `/tmp` only.
