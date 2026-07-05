# jpegpldec PL Decode 720p30 v0

Date: 2026-07-05

Result: PASSED for the first PL decoder-backend boundary. Real 1280x720
baseline 4:2:0 JPEG input entered the PL DMA data plane from inside
`jpegpldec`, returned byte-identical, and then continued through the software
reference decoder to the existing HDMI path.

This is not a complete PL JPEG decoder. Huffman entropy decode, dequant, IDCT,
color conversion, raw frame generation, and software/PL equivalence comparison
remain future work.

## Objective

Advance `jpegpldec` from a pure software-reference wrapper toward the 720p30
PL decode route without pretending the whole decoder is implemented.

The implemented v0 boundary is:

```text
RTP/JPEG over Ethernet
-> rtpjpegdepay
-> jpegpldec sink pad receives compressed image/jpeg GstBuffer
-> JPEG header metadata parse
-> /dev/jpegpl_dma_probe coherent DMA
-> AXI DMA MM2S -> PL probe core -> AXI DMA S2MM
-> byte-identical compressed buffer returned
-> existing software jpegdec child performs reference decode
-> videoconvert/videoscale/fbdevsink
-> existing VDMA/HDMI path
```

## Changed Scope

- Added `backend=software-reference|pl-compressed-probe` to `jpegpldec`.
- Added `probe-mode=compressed-dma-probe` and
  `probe-mode=pl-compressed-dma-probe`.
- Added a minimal JPEG marker parser for SOF0/SOF2, DQT, DHT, SOS, restart
  interval, resolution, component count, and 4:2:0 sampling detection.
- Added compressed JPEG DMA logging before the internal software `jpegdec`
  child.
- Extended `tools/run_jpegpldec_pl_probe.ps1` to run the 720p compressed
  ingress probe and record actual PL DMA counters for variable-size JPEG
  frames.
- Documented the new backend/probe modes in
  `software/gstreamer/jpegpldec/README.md`.

## Verification Performed

Static/build checks:

```text
POWERSHELL_PARSE_OK
git diff --check: no whitespace errors
JPEGPLDEC_PLUGIN_BUILD_OK
libgstjpegpldec.so hash:
6b102b5d6f194b9e69386fa99511e0313b1e41fb54f2f9dac3469477544c7b5d
```

Connected-board command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode compressed-dma-probe -InputWidth 1280 -InputHeight 720 -OutputWidth 800 -OutputHeight 600 -Fps 30 -Frames 5 -SummaryInterval 5 -CompressedMinPassFrames 4 -OutDir build\jpegpldec-pl-decode-720p30-v0-pass3
```

Board-side prerequisites passed:

```text
JPEGPL_DMA_PROBE_CLIENT_BUILD_OK
JPEGPL_DMA_PROBE_READY dev=/dev/jpegpl_dma_probe buffer_size=2097152 max_transfer_size=16380
JPEGPL_DMA_PROBE_TEST_OK length=115200
JPEGPLDEC_DEPLOY_INSPECT_DONE
```

`gst-inspect-1.0 jpegpldec` confirmed the new properties:

```text
backend
probe-mode
Children:
  software-reference-decoder
```

The live board pipeline used:

```text
rtpjpegdepay
! jpegpldec backend=pl-compressed-probe probe-mode=compressed-dma-probe
! videoconvert
! videoscale
! video/x-raw,format=BGR,width=800,height=600
! fbdevsink device=/dev/fb0 sync=true
```

## Measured Evidence

The board log confirmed real 720p compressed JPEG caps:

```text
image/jpeg width=1280 height=720
video/x-raw format=I420 width=1280 height=720
video/x-raw format=BGR width=800 height=600
```

Four compressed JPEG frames passed the PL DMA data plane with no failure:

| Frame | JPEG bytes | Chunks | DMA status | JPEG profile | Result |
| --- | ---: | ---: | --- | --- | --- |
| 1 | 30195 | 2 | 0x00000003 | 1280x720 baseline 4:2:0 | pass |
| 2 | 30244 | 2 | 0x00000003 | 1280x720 baseline 4:2:0 | pass |
| 3 | 30152 | 2 | 0x00000003 | 1280x720 baseline 4:2:0 | pass |
| 4 | 29817 | 2 | 0x00000003 | 1280x720 baseline 4:2:0 | pass |

For all four frames:

```text
jpeg_valid=1
jpeg_width=1280
jpeg_height=720
baseline=1
progressive=0
sampling=4:2:0
components=3
dqt=2
dht=4
sos=1
restart_interval=0
checksum_host == checksum_dma_in == checksum_dma_out
ioctl_result=0
errno=0
```

PL counters after the run:

```text
PL_DMA_FRAMES=0x00000008
PL_DMA_BYTES=0x0001D658
PL_DMA_LAST_FRAME_BYTES=0x0000347D
```

Final summary:

```json
{
  "cycle": "jpegpldec-pl-decode-720p30-v0",
  "probe_mode": "compressed-dma-probe",
  "logical_frames": 5,
  "dma_logged_pass_frames": 4,
  "dma_fail_frames": 0,
  "pl_dma_transactions": 8,
  "pl_dma_bytes": 120408,
  "result": "pass"
}
```

HDMI remained dynamic after the compressed ingress probe:

```text
HDMI_BALL_MOTION_OK samples=300 unique_hashes=5 frames_with_ball=300 x_span=80.134 y_span=133.253
```

## Why Four Frames Is Accepted

The previous `720p30-jpeg-chain-contract` cycle measured the current 720p30
software-reference path at about 5.4 fps, not 30 fps. This v0 cycle is not a
throughput claim; it is the first PL backend boundary claim. Requiring all
requested 30 fps source frames to survive the software reference path would
retest the known blocker and prevent progress on the PL decoder boundary.

The acceptance used here is therefore:

```text
real 1280x720 compressed JPEG caps
at least four compressed JPEG buffers passed through PL DMA
zero compressed DMA failures
PL DMA counters advanced
HDMI output remained dynamic
```

## Board Action

Loaded `/tmp/gst-plugins/libgstjpegpldec.so` and
`/tmp/jpegpl_dma_probe.ko`, ran the temporary GStreamer receiver, sent
1280x720 RTP/JPEG from the PC, and captured HDMI through the PC adapter.

No BOOT.BIN, image.ub, rootfs, bitstream, TF-card image, JTAG programming, or
board flash changed.

## Evidence

- `build/jpegpldec-pl-decode-720p30-v0-pass3/summary.json`
- `build/jpegpldec-pl-decode-720p30-v0-pass3/uart-deploy-inspect.log`
- `build/jpegpldec-pl-decode-720p30-v0-pass3/uart-stop-dma-probe.log`
- `build/jpegpldec-pl-decode-720p30-v0-pass3/hdmi-ball-motion-validation.json`
- `build/jpegpldec-pl-decode-720p30-v0-pass3/plugin/libgstjpegpldec.so`

## Rollback Point

Parent of this cycle commit. Board state is runtime-only; rebooting the board
or removing `/tmp/gst-plugins/libgstjpegpldec.so` and unloading
`jpegpl_dma_probe` returns to the previous runtime state.

## Residual Risks

- Actual JPEG decode is still done by the internal software `jpegdec` child.
- The current v0 PL path proves compressed ingress and byte-identical loopback,
  not Huffman/dequant/IDCT/color conversion in PL.
- The source sends 1280x720@30, but the software-reference path still cannot
  consume and display at 30 fps.
- Native 720p HDMI output is not claimed; output is downscaled to the current
  800x600 HDMI path.
- The next step must define the decoder micro-boundary to replace first:
  parser/table extraction, entropy decode, IDCT, or a hardware reference block.
