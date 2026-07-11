# jpegpldec Real PL Backend v1

Date: 2026-07-11

## Result

PASSED for the functional low-rate backend boundary. `jpegpldec
backend=pl-decoder` replaced the system `jpegdec` child with a project-owned
`GstVideoDecoder`, sent the qualified input owned by `docs/project-roadmap.md`
through `JPEGPL_DMA_PROBE_IOC_DECODE`, and published the roadmap-owned raw
format as downstream
GstBuffers. The existing GStreamer conversion, framebuffer, VDMA, and HDMI path
displayed the dynamic result.

This cycle does not claim sustained 720p30.

## Implementation

- Added a real `pl-decoder` backend while preserving `software-reference` and
  the historical probe modes.
- Kept the outer `jpegpldec` bin and selected either the system `jpegdec` or an
  internal PL `GstVideoDecoder` child while the element is in `NULL`.
- Mapped compressed input and an allocated RGB output buffer directly into the
  existing synchronous decoder ioctl request.
- Preserved GstVideoDecoder frame timestamps and emitted per-frame hardware
  counters, wall time, optional output FNV, and progress summaries.
- Added `verify-output-hash`, disabled by default so diagnostic hashing is not
  included in normal production work.
- Extended the cross-build with GStreamer video headers and `libgstvideo-1.0`.
- Added `tools/run_jpegpldec_real_backend.ps1` as the reproducible gate.

## Verification

The final source was built and exercised by:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_real_backend.ps1 -OutDir build\jpegpldec-real-pl-backend-v1-release
```

The script printed `JPEGPLDEC_REAL_BACKEND_OK`.

Fixed-vector evidence:

- Input: qualified 30,054-byte GStreamer JPEG vector.
- Output: 2,764,800-byte raw frame in the roadmap-owned format.
- Output FNV: `0x7127882c`.
- Output SHA-256:
  `01623472a5f3033e536d4691e3fde1ffc88e702c3b58c876743f5beb4c6d40c9`.
- Both values exactly match the preceding board-datapath qualification.
- Runtime DOT files contained the PL hardware child and zero
  `software-reference-decoder` matches.

Software recovery evidence:

- The same fixed JPEG completed through `backend=software-reference`.
- The software profile emitted one 1,382,400-byte I420 output buffer.

Dynamic evidence:

- PC requested 65 paced RTP/JPEG frames matching `docs/project-roadmap.md`.
- The UART evidence retained at least 61 complete PL decode pass markers and
  zero fail markers; the board log reached frame 63 before shutdown.
- At least 62 unique PL output hashes were observed.
- At least 61 retained PTS values were present and strictly increasing.
- Every retained frame reported 921,600 pixels, 2,764,800 output bytes,
  57,600 commands, matching responses, and zero PL errors.
- The runtime DOT graph reported three PL-child matches and zero software-child
  matches.
- Ethernet ended with RX/TX errors and drops at zero.
- Kernel log contained no Oops, BUG, panic, or hung-task marker.

HDMI evidence:

- 240 capture samples were readable.
- 110 unique capture hashes were observed.
- The ball was detected in 240/240 samples.
- Motion spans were `x=202.955` and `y=265.818` pixels.
- `HDMI_BALL_MOTION_OK` passed.

## Timing

From 61 complete retained dynamic-frame markers:

| Boundary | Average | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Driver hardware window (`req.elapsed_ns`) | 68.657 ms | 68.465 ms | 69.487 ms | not separately retained |
| Synchronous userspace ioctl wall time | 104.956 ms | 104.608 ms | 105.836 ms | 107.444 ms |

The roughly 36 ms difference includes the current userspace/kernel compressed
input copy, coherent output clearing and RGB `copy_to_user`; it is not PL decode
time. The outer GStreamer profile with verification hashing and downstream
handoff was roughly 130 ms per frame in the passing run.

## Board Action

- Built and temporarily deployed the plugin and kernel module under `/tmp`.
- Reloaded `jpegpl_dma_probe.ko`.
- Ran fixed and dynamic pipelines and captured HDMI through the connected UVC
  adapter.
- No RTL, bitstream, BOOT.BIN, image.ub, TF-card content, JTAG state, or flash
  content changed.

## Evidence

- `build/jpegpldec-real-pl-backend-v1-release/summary.json`
- `build/jpegpldec-real-pl-backend-v1-release/uart-fixed-and-software.log`
- `build/jpegpldec-real-pl-backend-v1-release/uart-stop-stream.log`
- `build/jpegpldec-real-pl-backend-v1-release/hdmi-ball-motion-validation.json`
- `build/jpegpldec-real-pl-backend-v1-release/hdmi-motion-capture/`

## Residual Risks

- The synchronous copy-based path is not capable of 720p30 in its current form.
- The 50 MHz decoder domain and writer stalls remain unchanged from the prior
  board-datapath cycle.
- RTP/JPEG depay advertises `framerate=0/1` on this old GStreamer stack. The
  verified paced display gate therefore uses `fbdevsink sync=false qos=false`;
  a later production clocking policy must define timestamps explicitly.
- `verify-output-hash=true` is diagnostic ARM work and must remain disabled for
  throughput measurements.
- The first backend intentionally accepts only the profile owned by the roadmap
  and decoder contract, and fails explicitly for unsupported input.
