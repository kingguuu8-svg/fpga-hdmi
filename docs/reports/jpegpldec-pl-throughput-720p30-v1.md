# jpegpldec PL Throughput 720p30 v1

## Objective

Optimize the real `jpegpldec backend=pl-decoder` path and verify a sustained
720p30 RTP/JPEG-to-GStreamer boundary on the connected Zynq-7020 board.

## Changes

- Changed the DataMover S2MM path from 32-bit to 64-bit and inserted a
  32-to-64 AXIS width converter.
- Kept decoder AXI-Lite control in the PS FCLK0 domain through an AXI-Lite
  clock converter; the decoder and writeback data plane run at the generated
  65 MHz clock.
- Added a reproducible Vivado 2018.3 SmartConnect OOC clock-file fallback for
  the generated 64-bit design.
- Added DMA output mmap to the kernel probe and plugin, disabling the repeated
  kernel-to-userspace output copy for the synchronous gate.
- Cached stable decoder configuration and repeated control verification in the
  kernel path.
- Made the 330-frame gate wait for the board login prompt after reboot and
  avoid PowerShell quote corruption in the remote GStreamer command.

## Verification

Build and timing:

- v4cc8b bitstream SHA-256:
  `5de6eef793c13bd70d4009b34a45c6e92a4363b2f63c51329ebce97addbdc312`
- Post-route WNS `+0.170 ns`, WHS `+0.021 ns`, zero DRC errors.
- Measured JPEG clock: `64.997 MHz`.
- BOOT.BIN SHA-256:
  `35be3620960337e3b743ac8e549787fd3cc59038203a93111c885cc5d32aeb95`
- Reused image.ub SHA-256:
  `afc8b5658ac868592b7770d42911bc011e8e4319762af62f86bf96c481e87570`

RTL and single-frame board path:

- RTL randomized backpressure simulation: `921600` pixels, `1974075`
  cycles, PSNR `39.002 dB`, FNV `0x7127882c`.
- Board register smoke passed.
- Board full writeback passed with `2764800` RGB bytes, FNV `0x7127882c`,
  output SHA-256
  `01623472a5f3033e536d4691e3fde1ffc88e702c3b58c876743f5beb4c6d40c9`.
- Board full-writeback measurement: approximately `35.916 ms`, `2559119`
  cycles, `57600` commands, `57600` responses, and `115200` stalls.

Real GStreamer gate:

- Pipeline: PC GStreamer RTP/JPEG -> board `rtpjpegdepay` ->
  `jpegpldec backend=pl-decoder` -> `fakesink`.
- Requested/decoded frames: `330/330`; failures: `0`.
- Kernel health: OK; Ethernet RX errors/dropped: `0/0`.
- Steady average: `36.340 ms`; gate-script p95: `37.019 ms`.
- First frame: approximately `70.694 ms`.
- Output mmap was active and output copy was disabled.

## Result

Functional correctness and stability passed, but the throughput acceptance
threshold did not: p95 is about `3.7 ms` above the `33.333 ms` 30fps budget.
This cycle is therefore recorded as an active performance checkpoint, not a
completed 720p30 claim.

## Remaining risks

- The current 65 MHz data plane has only `+0.170 ns` WNS; increasing the clock
  requires a new timing-qualified build.
- The plugin wraps one coherent DMA output buffer and relies on synchronous
  consumption in this gate. A production asynchronous buffer pool needs a
  lifetime/fencing design before this mmap approach is generalized.
- The v4cc8b generated-clock reset still contains the diagnostic constant-high
  reset isolation used to make the DataMover path board-live. It is evidence
  for the path, not yet a final reset architecture.

## Evidence

- `build/jpegpldec-pl-throughput-720p30-v1/vivado-control-fclk0-v4cc8b/`
- `build/jpegpldec-pl-throughput-720p30-v1/sim-v4cc8b/`
- `build/jpegpldec-pl-throughput-720p30-v1/uart-smoke-v4cc8b.log`
- `build/jpegpldec-pl-throughput-720p30-v1/uart-datapath-v4cc8b.log`
- `build/jpegpldec-pl-throughput-720p30-v1/runtime-v4cc8b-gate-rerun/uart-stop.log`
