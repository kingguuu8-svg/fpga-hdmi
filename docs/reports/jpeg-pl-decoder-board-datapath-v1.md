# JPEG PL Decoder Board Datapath v1

Date: 2026-07-11

Result: PASSED for one complete connected-board JPEG decode through the PL
data plane. Linux supplied one compressed frame through coherent DMA, the PL
decoder produced a complete RGB888 frame, DataMover wrote it back to coherent
DDR, and Linux returned bytes that matched the fixed software reference.

This closes the board-live single-frame datapath boundary. It does not claim
the sustained frame-rate target, a GStreamer `jpegpldec` PL backend, arbitrary
JPEG compatibility, native HDMI presentation, or end-to-end video effects.
Those targets remain owned by `docs/project-roadmap.md` and
`docs/protocols/jpegpldec-720p30-contract.md`.

## Proven Route

```text
Linux userspace JPEG
-> coherent kernel input buffer
-> AXI DMA MM2S
-> ultraembedded jpeg_core in PL
-> coordinate-aware RGB tile writer
-> AXI DataMover S2MM
-> coherent kernel output buffer
-> Linux userspace RGB888
```

The test uses the pinned decoder and fixed JPEG vector qualified in
`docs/reports/jpeg-pl-decoder-core-qualification.md`.

## Implemented Scope

- Added `jpeg_pl_decoder_axis`, which binds AXI DMA compressed input to the
  decoder and exposes AXI-Lite control/status.
- Added a coordinate-aware RGB tile writer. It converts decoder coordinates
  into 48-byte DataMover Full S2MM row commands and preserves RGB888 byte
  order in DDR.
- Corrected the DataMover Full command and status contracts: DRR, EOF, DSA,
  TYPE, BTT, OKAY, hardware error bits, and tag handling now match the Vivado
  2018.3 generated IP interface.
- Made AXI-Lite AW and W handshakes independent and added readable control,
  configuration, counters, and a fixed version register.
- Moved the decoder, AXI DMA, DataMover, control slave, and associated
  interconnect onto the proven PS FCLK0/reset domain. This removed the board
  hang on the first decoder register write.
- Added input-sink and count-only diagnostic modes, plus sequential restart
  coverage that proves counters reset between modes.
- Replaced the old dual-channel loopback client with one MM2S compressed-input
  DMA channel and PL-originated coherent RGB output.
- Made the decode timeout one absolute deadline, synchronously terminates DMA
  before callback storage can leave scope, and disables runtime sysfs unbind.
- Added register, counter, output FNV, and host pixel-reference gates.
- Added guarded boot-only packaging and made the normal board build marker
  reject post-route DRC errors.

## Failure Chain Resolved

The cycle did not treat the first displayed or returned image as success. It
isolated and fixed four independent hardware-facing faults:

1. The initial DataMover command/status mock did not model the Full interface
   contract, so malformed fields passed xsim but failed on hardware.
2. The original AXI-Lite slave required AWVALID and WVALID in the same cycle;
   the Linux register write could therefore hold the shared AXI path forever.
3. A generated decoder clock/reset island allowed BD validation and routing
   but hung at the first live MMIO access. Moving the whole subgraph to FCLK0
   removed that failure.
4. Starting count-only immediately after input-sink exposed a stale cycle
   counter because a same-edge busy update overrode the clear. A red xsim
   regression reproduced it before the start-priority fix passed.

## Verification

### RTL and Reference

Final command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\sim-jpeg-board-datapath-wsl.ps1 -OutDir build\jpeg-pl-decoder-board-datapath-v1\sim-final-v6
```

Final markers and measurements:

```text
JPEG_INPUT_SINK_SUBTEST_OK
JPEG_BOARD_DATAPATH_SIM_OK pixels=921600 commands=57600 responses=57600
  bytes=2764800 input_bytes=30054 cycles=2959414 stalls=985400
JPEG_PL_RTL_COMPARE_OK psnr_db=39.002 rtl_fnv=0x7127882c
JPEG_BOARD_DATAPATH_SIM_GATE_OK
```

The sequential restart regression first failed with
`restart_cycle_counter_not_reset cycles=52`, then passed after start was given
priority over the old busy-state counter logic.

### Combined XC7Z020 Implementation

| Gate | Result |
| --- | --- |
| Part | `xc7z020clg484-1` |
| Post-route WNS | `+0.151 ns` |
| DRC errors | `0` |
| DRC critical warnings | `0` |
| Bitstream SHA-256 | `f3612f28abbc46cd96c432f04d1948c96b2c8c87c4b097fd0ad16cc59b49cb3c` |

The DRC report is not warning-free: it lists 77 warning/advisory violations,
primarily DSP/BRAM pipelining guidance plus one no-routable-load warning. None
is an Error or Critical Warning, so they do not violate the project hard gate;
they remain optimization evidence rather than being hidden.

The final BOOT-only package reused the already matched Linux image after
explicit hash confirmation:

| Artifact | SHA-256 |
| --- | --- |
| `BOOT.BIN` | `c56a4b986a62819f034d1455319253889d071e70606d5b5030bdab6ce357c0ff` |
| `image.ub` | `14cf602b94e160f6fe9c6cbfed46404a73603f6d2e0c277cecead8285a1f7e88` |
| TF recovery BOOT | `ae6b2ca206cc55756956e262426b8a0d9e466544db434b2e7900f5111b9b3d2c` |

### Connected-Board Strict Gates

The final client hashes were:

```text
jpegpl_dma_probe.ko
  288471be4d09bd91268d11e950852a69f0751b24f97544c1097e94d6cc6cd6ec
jpegpl_dma_probe_test
  a5ee6e5cb77a5b1d6223352633a648283a0280bc7e4ecc76fa939ab51016e67a
```

The strict run executed the modes in order on the same boot:

| Gate | Key result | Elapsed |
| --- | --- | ---: |
| Register smoke | exact config readback and version `0x4a504c31` | n/a |
| Input sink | input `30054`, chunks `2`, all output/decode counters zero, cycles `1143128` | `13.993674 ms` |
| Count only | pixels `921600`, output/commands/responses/errors zero, cycles `2417462` | `44.773927 ms` |
| Full writeback | output `2764800`, pixels `921600`, commands/responses `57600/57600`, errors zero, cycles `3634625`, FNV `0x7127882c` | `68.394928 ms` |

The cycle counter gate has a physical lower and upper bound. Input-sink must
take at least one cycle per accepted four bytes; decode must take at least one
cycle per output pixel; all modes must fit beneath the elapsed-time bound for
a maximum 200 MHz counter clock. Every final mode passed both bounds.

The retrieved frame was 2,764,800 bytes with SHA-256
`01623472a5f3033e536d4691e3fde1ffc88e702c3b58c876743f5beb4c6d40c9`.
The host comparison required both PSNR at or above 35 dB and the exact expected
FNV. It passed at PSNR `39.00235660912144 dB`, MAE `2.59886`, maximum channel
error `41`, and FNV `0x7127882c`.

After the strict run, UART remained interactive, the module remained loaded,
the kernel log had no Oops/BUG/panic/hung marker, Ethernet had no RX/TX errors,
and the PC received `4/4` ping replies.

### Timeout Recovery

Before the final build, a connected-board fault injection sent a 4 MiB
input-sink request with a 1 ms total deadline. The driver aborted after 14 DMA
chunks, synchronously terminated the channel, returned `ETIMEDOUT`, retained
UART and Ethernet health, and accepted a subsequent normal DMA request. This
is the recovery evidence for the timeout/UAF fix; it is not a throughput test.

## Evidence

- `build/jpeg-pl-decoder-board-datapath-v1/sim-restart-counter-red/xsim.log`
- `build/jpeg-pl-decoder-board-datapath-v1/sim-final-v6/xsim.log`
- `build/jpeg-pl-decoder-board-datapath-v1/sim-final-v6/pixel-comparison.json`
- `build/jpeg-pl-decoder-board-datapath-v1/vivado-final-v5/reports/resume-v5.log`
- `build/jpeg-pl-decoder-board-datapath-v1/vivado-final-v5/reports/timing_summary.rpt`
- `build/jpeg-pl-decoder-board-datapath-v1/vivado-final-v5/reports/post_route_drc.rpt`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v5-boot-backup-uart.log`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v5-boot-write-verify-uart.log`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-runtime-deploy-uart.log`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-register-smoke-uart.log`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-input-sink-uart.log`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-count-only-uart.log`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-full-decode-uart.log`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-strict-cycle-gate.json`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6.rgb`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-pixel-comparison.json`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-final-health-uart.log`
- `build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-final-ping.log`
- `build/jpeg-pl-decoder-board-datapath-v1/timeout-fix-injected-timeout.log`
- `build/jpeg-pl-decoder-board-datapath-v1/timeout-fix-health.log`
- `build/jpeg-pl-decoder-board-datapath-v1/timeout-fix-normal-recovery.log`

## Board Action

The board booted the new `BOOT.BIN` from the TF FAT partition. The previous
BOOT was retained as `BOOT.pre-final-v5.BIN`, and `image.ub` was not changed.
After boot, the final module, test utility, and JPEG vector were downloaded to
`/tmp`; no rootfs package, QSPI, NAND, or eMMC was modified. The final strict
client rerun did not reboot or rewrite the TF card.

## Rollback Point

- Git: `65c2549`, the standalone decoder qualification before board
  integration.
- Board: `/run/media/mmcblk0p1/BOOT.pre-final-v5.BIN` with the recovery hash
  recorded above, plus the unchanged accepted `image.ub`.

## Third-Party Review

A final read-only review identified false-pass and lifecycle risks. This cycle
fixed the actionable issues without changing the already verified bitstream:

- Disabled runtime sysfs bind/unbind for the misc-device driver, preventing a
  platform unbind from racing an open ioctl.
- Added physical cycle lower bounds in addition to the existing elapsed-time
  upper bound, then repeated all board gates with the rebuilt client.
- Required the expected FNV in both the board full-writeback command and the
  host raw-RGB comparison.
- Made BOOT-only packaging require explicit bitstream/image hashes and an
  explicit declaration that the existing Linux image is being reused.
- Made the standard Vivado board build marker reject post-route DRC errors.

## Residual Risks

- The measured full ioctl took about 68.4 ms, an unsustained single-frame rate
  of roughly 14.6 fps. This cycle therefore does not satisfy the sustained
  target in `docs/protocols/jpegpldec-720p30-contract.md`.
- The board-live decoder runs on the 50 MHz FCLK0 domain selected to remove the
  unreliable generated clock/reset island. Restoring a faster domain requires
  a separately verified clock/reset design and another combined timing/board
  gate.
- The reused Linux device-tree metadata still describes the prior decoder
  data-clock rate. The fixed-clock enable path is a no-op in the current
  driver, but the metadata must be synchronized before frequency-dependent
  software is introduced.
- The DataMover instance retains an unused MM2S side. It is not active in this
  route but remains a resource-cleanup item.
- Only the fixed qualified baseline JPEG profile has board evidence. A
  truncated or unsupported frame currently reaches the total timeout rather
  than a classified PL decoder error/fallback.
- AXI-Lite configuration writes are verified with full-word `writel`; partial
  byte-strobe configuration writes are not supported or tested.
- Linux reports that the TF FAT volume was not cleanly unmounted during an
  earlier boot. The final write used `sync` and hash readback, but the card
  should receive an offline filesystem check at a safe maintenance point.
- The decoded frame is returned to a standalone Linux test utility. Binding it
  into `jpegpldec`, publishing a downstream `GstBuffer`, sustained video,
  HDMI presentation, and PL effects remain later cycles.
