# jpegpldec PL Throughput 720p30 v1

## Objective

Verify that the real `jpegpldec backend=pl-decoder` path sustains a 1280x720
30fps RTP/JPEG input at the decoder-to-GStreamer boundary on the connected
Zynq-7020 board.

This cycle does not claim HDMI presentation throughput or an asynchronous
production buffer pool.

## Implementation

- Kept the v4cc8b 64-bit DataMover S2MM writeback path and AXIS 32-to-64 width
  converter.
- Retained AXI-Lite control clock conversion, cached stable register setup,
  and the synchronous DMA output mmap path.
- Added opt-in per-phase kernel timing through `trace_timing=1` without
  changing the driver UAPI.
- Changed normal per-frame DMA submit/completion messages from `dev_info` to
  `dev_dbg`, removing 115200-baud UART logging from the normal datapath.
- Made the gate parser tolerate UART line wrapping when extracting
  `total_ms` and `result=pass` from frame records.

The PL bitstream and boot image were not changed in this optimization
checkpoint. The verified v4cc8b hardware remains the active board design.

## Static Verification

- v4cc8b bitstream SHA-256:
  `5de6eef793c13bd70d4009b34a45c6e92a4363b2f63c51329ebce97addbdc312`
- Post-route WNS `+0.170 ns`, WHS `+0.021 ns`, and zero DRC errors.
- Measured JPEG clock: `64.997 MHz`.
- RTL randomized backpressure simulation: `921600` pixels,
  `1974075` cycles, PSNR `39.002 dB`, FNV `0x7127882c`.
- Board fixed-vector RGB writeback: `2764800` bytes, FNV `0x7127882c`,
  qualified output SHA-256
  `01623472a5f3033e536d4691e3fde1ffc88e702c3b58c876743f5beb4c6d40c9`.

## Final Board Gate

Pipeline:

```text
PC GStreamer RTP/JPEG -> board rtpjpegdepay ->
jpegpldec backend=pl-decoder -> fakesink sync=false
```

Final gate command used 330 requested frames, 30fps target, and 300 minimum
accepted frames. The generated summary reports:

- decoded pass frames: `330`
- decoded fail frames: `0`
- gate total-time p95: `31.455 ms`
- plugin profile: p50 `30.975 ms`, p95 `31.929 ms`, max `65.439 ms`
- plugin backend selection: `backend=pl-decoder`,
  `software_jpegdec=absent`, `output_mmap=1`
- kernel health: `KERNEL_HEALTH_OK`
- Ethernet: RX `errors=0`, `dropped=0`

The final profile also reported `frames=330`, `failures=0`, and
`avg_out_bytes=2764800.0`. The first frame is a warm-up outlier of roughly
65ms; the steady profile remains below the 33.333ms 30fps frame budget.

Evidence:

- `build/jpegpldec-pl-throughput-720p30-v1/runtime-logging-fix-gate-final/summary.json`
- `build/jpegpldec-pl-throughput-720p30-v1/runtime-logging-fix-gate-final/uart-stop.log`

## Bottleneck Finding

The earlier v4cc8b gate measured p95 `37.019 ms`. The phase timing sweep
showed that this number was materially contaminated by per-frame kernel
`dev_info` messages sent over the 115200-baud UART. With diagnostic console
noise suppressed:

- input-sink DMA was roughly `0.2 ms` per frame;
- count-only full driver time was roughly `30.6 ms`;
- PL completion polling was roughly `1.0 ms`;
- copying the 2.7648MB RGB result to userspace added roughly `15 ms`.

The normal plugin path uses output mmap, so it avoids that repeated RGB copy.
The phase trace is retained as an opt-in diagnostic mode; the normal gate
prints no per-frame timing dump.

Timing evidence is under
`build/jpegpldec-pl-throughput-720p30-v1/uart-timing-v4cc8b-lines.log`.

## Result

**PASSED for the 720p30 decoder-to-GStreamer boundary.** The board sustained
330 ordered PL-decoded frames with zero decode failures, p95 below the 30fps
budget, healthy kernel state, and no Ethernet RX errors or drops.

This does not yet prove:

- HDMI presentation at 30fps;
- an asynchronous multi-buffer production design;
- a higher PL clock or 1080p throughput target.

The profile's legacy `mode=software` text is not used as backend evidence. The
backend selection line explicitly reports `backend=pl-decoder` and
`software_jpegdec=absent`.

## Residual Risks and Rollback

- The first-frame warm-up remains roughly 65ms.
- The 65MHz PL data plane has only `+0.170ns` WNS; a clock increase requires a
  new routed timing-qualified build.
- The current mmap contract is synchronous and reuses one coherent output
  buffer; an asynchronous production buffer pool needs explicit lifetime and
  fencing rules.
- The generated-clock reset still contains the diagnostic constant-high
  isolation used to make the v4cc8b DataMover path board-live.
- Rollback source point: commit `e0e0ea5`; rollback board state is the verified
  v4cc8b BOOT.BIN/image.ub package.

## Artifacts

- Plugin SHA-256: `cd1b1178f6e389c67d9b876778a3afcdbe1c09c678330c85db3d5d4939ead2e0`
- Kernel module SHA-256: `fa8e85c8aeea568dadeaacd9a34aba4a8a0b7c46c762d7e530ed8b0ed6ad40c3`
- Final gate directory:
  `build/jpegpldec-pl-throughput-720p30-v1/runtime-logging-fix-gate-final/`
