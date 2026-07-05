# JPEG PL Decoder Core Qualification

Date: 2026-07-05

Result: PASSED for a real baseline JPEG RTL decoder qualification against the
current 720p30 contract. A pinned open-source hardware decoder consumed a JPEG
produced by the same GStreamer source profile used by the project, emitted a
complete RGB frame, matched a software reference above the declared image
quality threshold, and met timing plus the frame-cycle budget on the target
XC7Z020.

This is not yet the board-live `jpegpldec` PL backend. Linux buffer handoff,
compressed-input DMA integration, coordinate-aware RGB writeback, GStreamer
raw-buffer publication, and HDMI verification remain the next implementation
boundary.

## Selected Core

- Upstream: `ultraembedded/core_jpeg`
- Pinned commit: `f9e269a6687ed341b122cdd1412d101ee163e199`
- License: Apache-2.0
- Imported RTL: 23 Verilog files with whitespace-only normalization
- Core mode: fixed standard Huffman tables

The current GStreamer JPEG vector carries DHT markers, but its tables are
compatible with the core's fixed standard-table path. That compatibility is
not assumed from marker count: the full RTL output is compared against the
software decode.

The standalone `jpeg_core` was selected instead of the upstream
`core_jpeg_decoder` AXI wrapper. The core emits 24-bit RGB with pixel
coordinates, while the wrapper reduces output to RGB565 and performs
single-word AXI writes. Keeping the core preserves the project's 24-bit video
path and leaves DMA/writeback policy under project control.

## Implemented Scope

- Added the pinned RTL and its license under
  `third_party/ultraembedded-core-jpeg/`.
- Added a deterministic JPEG generated with the same `videotestsrc -> I420 ->
  jpegenc quality=90` profile used by the current sender.
- Added vector preparation, xsim testbench, coordinate-based frame
  reconstruction, Pillow reference decode, and pixel comparison.
- Added standalone XC7Z020 out-of-context synthesis, placement, routing,
  timing, DRC, and utilization reporting.
- Added a single PowerShell entry point that runs the complete qualification.
- `git diff -w --ignore-blank-lines --no-index` confirmed the vendored RTL
  differs from the pinned checkout only by whitespace normalization.

## Verification

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\jpeg-pl-decoder-qualification\run-qualification.ps1
```

Final marker:

```text
JPEG_PL_DECODER_QUALIFICATION_OK cycles=1973637 decode_ms=29.605 fps=33.779 psnr_db=39.002 wns_ns=0.185
```

JPEG vector:

```text
bytes=30054
sha256=f8b799472f6c5eb4e1c798dea47f6db15a47d03115932938f0b3ed76a454dbde
profile=baseline 4:2:0, standard Huffman tables, no restart interval
```

RTL decode:

```text
JPEG_PL_RTL_SIM_OK width=1280 height=720 pixels=921600 cycles=1973637 duplicates=0
```

Software/RTL comparison:

```text
JPEG_PL_RTL_COMPARE_OK pixels=921600 psnr_db=39.002 mae=2.599 max_error=41
minimum accepted PSNR=35 dB
```

The comparison allows integer IDCT and YCbCr-to-RGB rounding differences. It
does not use visual inspection as acceptance evidence.

XC7Z020 implementation:

```text
part=xc7z020clg484-1
clock=66.667 MHz
post-route WNS=+0.185 ns
DRC errors=0
decode time=29.605 ms/frame
theoretical maximum=33.779 fps
```

The 100 MHz qualification attempt was rejected with WNS `-4.251 ns`. The
accepted clock is the lowest tested implementation point that both closes
timing and retains a measurable 30 fps cycle margin. The out-of-context timing
report warns that final clock delay/skew depends on the parent design, so the
combined design must repeat timing closure.

Core post-route resources:

| Resource | Used | XC7Z020 available | Percent |
| --- | ---: | ---: | ---: |
| Slice LUTs | 5,220 | 53,200 | 9.81% |
| Slice registers | 3,288 | 106,400 | 3.09% |
| BRAM tiles | 6 | 140 | 4.29% |
| DSPs | 31 | 220 | 14.09% |

Capacity-only estimate when added to the current VDMA/HDMI/PIP implementation
report:

| Resource | Estimated combined use | Percent |
| --- | ---: | ---: |
| Slice LUTs | 16,659 | 31.31% |
| Slice registers | 18,772 | 17.64% |
| BRAM tiles | 111.5 | 79.64% |
| DSPs | 31 | 14.09% |

This arithmetic does not include the next coordinate-aware writeback adapter
and is not a combined implementation result. BRAM is the tightest resource.

## Integration Boundary

The next board-live backend should be:

```text
jpegpldec compressed GstBuffer
-> existing coherent input buffer / AXI DMA MM2S
-> jpeg_core
-> coordinate-aware RGB888 burst writer or reorder stage
-> coherent raw-frame buffer
-> jpegpldec publishes video/x-raw
-> existing display/effect path
```

The decoder output includes `(x,y)` for each RGB pixel and is not a proven
linear raster AXI stream. It must not be connected directly to sequential AXI
DMA S2MM without a reorder or address-aware writeback stage.

## Evidence

- `build/jpeg-pl-decoder-qualification/summary.json`
- `build/jpeg-pl-decoder-qualification/sim/xsim.log`
- `build/jpeg-pl-decoder-qualification/sim/pixel-comparison.json`
- `build/jpeg-pl-decoder-qualification/impl/reports/qualification_summary.txt`
- `build/jpeg-pl-decoder-qualification/impl/reports/post_route_timing_summary.rpt`
- `build/jpeg-pl-decoder-qualification/impl/reports/post_route_utilization.rpt`
- `build/jpeg-pl-decoder-qualification/impl/reports/post_route_drc.rpt`

## Board Action

None. This cycle used xsim and standalone XC7Z020 implementation only. It did
not build or program a combined bitstream and did not change BOOT.BIN,
image.ub, rootfs, TF-card contents, JTAG state, or board flash. Board
programming was intentionally omitted because this qualification has no
board-level DMA/control top and therefore produces no observable board test;
that integration is the next cycle rather than evidence this cycle can claim.

## Residual Risks

- Only the exact current GStreamer JPEG profile and one deterministic frame
  were qualified; arbitrary optimized Huffman tables, restart markers,
  progressive JPEG, and 4:2:2 remain outside the accepted profile.
- The measured decoder had no output backpressure and no shared-memory traffic.
- The 33.779 fps theoretical result has limited margin; DMA stalls must be
  absorbed or prevented by buffering.
- The combined VDMA/HDMI/PIP/JPEG design has not been placed or routed.
- Output writeback must preserve coordinate ordering without consuming the
  remaining BRAM margin carelessly.

## Rollback Point

Parent of this cycle commit. No persistent board state changed.

## Third-Party Review

None.
