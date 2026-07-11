# Current Cycle

Status: no active work note is open. The most recently closed cycle is
`jpeg-pl-decoder-board-datapath-v1`; its final evidence is in
`docs/reports/jpeg-pl-decoder-board-datapath-v1.md`.

## Rule

Use this file as a lightweight current-work note when the work is large enough
that intent, evidence, rollback point, or third-party review context would help
a future reader. It is not a permission gate and does not need to be opened for
small, obvious changes.

## Work Note Template

```text
Cycle ID:
Intent:
Changed scope:
Verification performed:
Board action:
Evidence:
Rollback point:
Third-party review:
Residual risk:
```

`Verification performed` records what actually ran and what it showed. It may
include thresholds and measured values when that is useful, but future work no
longer requires frozen `pass_condition` or `validator` fields.

`Rollback point` should name the commit, artifact backup, or board image state
that lets a future agent return to the previous known-good point.

`Third-party review` is the review inlet. If no review was performed, write
`none` or omit the line in the completed report.


## Active Cycle

```text
None.
```

## Most Recently Closed Cycle

```text
Cycle ID: jpegpldec-real-pl-backend-v1
Result: PASSED. `jpegpldec backend=pl-decoder` bypassed system `jpegdec`,
  published PL-decoded GstBuffers in the roadmap-owned raw format, matched the
  qualified fixed-vector output exactly, and completed the dynamic low-rate
  RTP/JPEG-to-HDMI gate defined by `docs/project-roadmap.md`.
Evidence: docs/reports/jpegpldec-real-pl-backend-v1.md and
  build/jpegpldec-real-pl-backend-v1-release/.
Rollback point: commit 6d282f2 and the existing TF-card recovery image recorded
  by the preceding board-datapath cycle.
Residual risk: this is a synchronous copy-based low-rate closure, not sustained
  720p30.
```

## Frozen Progress Note

```text
Cycle ID: jpeg-pl-decoder-board-datapath-v1
Frozen on: 2026-07-07
Reason: The cycle reached a board-live failure that needs diagnosis before
  more feature implementation. The failure is not a GStreamer/dashboard/HDMI
  presentation issue; it occurs below that layer during the single-frame
  hardware decode test.

Facts established:
  - The standalone jpeg_core qualification remains the prior known-good
    decoder evidence.
  - The integrated board design built and routed with non-negative timing.
  - Latest BOOT.BIN/image.ub were deployed to the TF-card boot partition and
    the board booted the new image.
  - Runtime device tree exposes jpegpl-decoder@43c10000 with a tx DMA binding.
  - jpegpl_dma_probe.ko inserted and created /dev/jpegpl_dma_probe.
  - The test utility and 1280x720 JPEG vector were deployed with matching
    hashes.
  - Expected RTL output hash for the current simulation output was computed as
    FNV32 0x7127882c for 921600 pixels / 2764800 RGB bytes.

Observed failure:
  - Starting the one-frame hardware decode did not produce the expected RGB
    output file, status code, or final decode marker.
  - A follow-up UART inspection captured only the host tool command markers,
    with no useful board shell echo or command output.
  - This is recorded as a suspected board-side non-interactive state after
    decode start, not as a proven kernel panic.

Current inference:
  - The most likely fault region is PL decoded-RGB writeback to DDR:
    jpeg_rgb_tile_writer -> AXI DataMover S2MM -> HP/DDR.
  - The standalone JPEG decoder and software/GStreamer route are not the
    primary suspects for this failure.
  - The xsim DataMover mock was sufficient for functional intent but too weak
    to prove exact Xilinx AXI DataMover command/status behavior in hardware.
  - The BD still contains an unused AXI DMA S2MM half fed by an idle stream
    while the Linux driver only requests the tx/MM2S channel; this is not
    required for the current decode route and increases the possible AXI lock
    surface.

Shortest next diagnostic path:
  1. Add a count-only/no-writeback hardware mode: JPEG bytes still enter PL and
     jpeg_core still decodes, but RGB pixels are counted rather than written to
     DDR.
  2. If count-only passes on the board, treat decoder/MM2S as cleared and focus
     on DataMover S2MM/writeback.
  3. If count-only also fails, move the fault boundary upstream to MM2S,
     jpeg_core integration, or stream backpressure.
  4. Remove the unused AXI DMA S2MM half/idle stream from the BD unless a later
     design needs it.
  5. Reintroduce output writeback first as the simplest observable path before
     restoring coordinate-aware tiled writeback.

Evidence paths:
  - build/jpeg-pl-decoder-board-datapath-v1/deploy-latest-image.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/boot-after-latest-image.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/post-latest-image-health.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/deploy-current-kernel-client.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/run-current-one-frame-decode-watchdog.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/check-current-decode.uart.log
```

## 2026-07-07 Follow-Up

```text
Work performed:
  - Corrected the AXI DataMover S2MM command fields in
    jpeg_rgb_tile_writer.v: DSIZE is now 3'b010 for 32-bit stream width and
    RSS is cleared.
  - Added board-datapath testbench checks for Type, DSIZE, RSS, and reserved
    command bits so the previous malformed command cannot pass the mock again.
  - Re-ran the full JPEG board-datapath simulation and reference comparison:
    JPEG_BOARD_DATAPATH_SIM_OK and JPEG_PL_RTL_COMPARE_OK psnr_db=39.002.
  - Built the corrected bitstream. Initial routed WNS was +0.078 ns.
  - Packaged and deployed BOOT.BIN hash
    54bfd0e8cecf1e386e83fcc6f6d2bb414af5677ae822eb75d69c63ffaa584709.
  - Re-ran the one-frame board decode. It still did not return, and a
    follow-up UART probe again produced no useful board echo.
  - Added a diagnostic count-only mode controlled by REG_CONTROL[1]. In this
    mode JPEG input still enters PL and jpeg_core still decodes, but RGB pixels
    are counted and no DataMover S2MM writeback commands are issued.
  - Re-ran simulation after the count-only addition; the default RGB writeback
    simulation still passed with JPEG_BOARD_DATAPATH_SIM_OK and
    JPEG_PL_RTL_COMPARE_OK psnr_db=39.002.
  - Rebuilt the kernel client with --count-only support:
    jpegpl_dma_probe.ko hash
    a9cf9b18556453436c93d17e6491de8d04479cb8407e321182b4fa474b58b2a6;
    jpegpl_dma_probe_test hash
    f83b1ff6cb5640b8ff40e02f41018b114d237846e57458e523bd0c14eaa222ad.
  - Built the count-only bitstream. The first route failed timing with
    WNS=-0.129 ns on an unrelated existing PIP-overlay clk_fpga_1 path.
    Post-route phys_opt recovered timing to WNS=+0.121 ns with DRC 0 errors.
  - Packaged and deployed BOOT.BIN hash
    01c6188a28c84abadfbc238ca404ebfe5e60cd0a0b0dd524c2aad86cc4d6efaa.
  - Re-ran the board count-only decode. It also did not return, and a
    follow-up UART probe again produced no useful board echo.

Updated inference:
  - The original DataMover command-word bug was real and has been fixed, but
    it was not sufficient to close the board-live decode path.
  - Because count-only disables decoded-RGB DataMover S2MM writeback and still
    triggers the same non-interactive board state, the fault boundary moves
    upstream of RGB writeback.
  - Current leading suspects are now AXI DMA MM2S interaction with the
    jpeg_core ingress/backpressure path, jpeg_core board integration under
    real DMA timing, or an AXI interconnect/bus lock triggered before PL
    writeback starts.
  - The next diagnostic should add a stream-sink mode that consumes AXI DMA
    MM2S input without invoking jpeg_core, so the path can be split into:
    Linux coherent input buffer -> AXI DMA MM2S -> PL sink versus
    AXI DMA MM2S -> jpeg_core.

Additional evidence paths:
  - build/jpeg-pl-decoder-board-datapath-v1/run-dsize-one-frame-decode.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/dsize-decode-followup.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/run-count-only-decode.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/count-only-followup.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/image/latest-hashes-count-only.txt
```

## 2026-07-07 Input-Sink Follow-Up

```text
Work performed:
  - Added input-sink diagnostic mode controlled by REG_CONTROL[2].
  - In input-sink mode, jpeg_pl_decoder_axis asserts S_JPEG tready without
    feeding jpeg_core, counts input bytes, and issues no RGB DataMover
    writeback.
  - The Linux test tool added --input-sink. In this mode the driver only waits
    for AXI DMA MM2S send completion and snapshots counters; it does not wait
    for PL decode done and does not copy RGB output.
  - Re-ran default board-datapath simulation; RGB writeback path still passed
    with JPEG_BOARD_DATAPATH_SIM_OK and JPEG_PL_RTL_COMPARE_OK psnr_db=39.002.
  - Rebuilt kernel client:
    jpegpl_dma_probe.ko hash
    c33e0ac524f841a779328f81c7c6083bf6282eeef66ba8ff9deec0b7893bdae7;
    jpegpl_dma_probe_test hash
    d9843beb951d6439e72321cdfde139078940df48e397c52184a73166793b74e6.
  - Rebuilt bitstream with WNS=+0.093 ns and routed DRC generated with no
    hard error.
  - Packaged and deployed BOOT.BIN hash
    0658f066f834d9b7d0e7e71a6a3859aa161bae68b431bf87690f5b769994296a.
  - Re-ran the board input-sink test. It also did not return, and the
    follow-up UART probe again produced no useful board echo.

Updated inference:
  - input-sink removes jpeg_core and RGB/DataMover writeback from the active
    data path, so those are no longer sufficient explanations for the observed
    board non-interactive state.
  - The failure now localizes to the AXI DMA MM2S / BD / Linux DMAengine
    interaction around axi_dma_0. The strongest remaining structural suspect is
    that axi_dma_0 is still built with an unused S2MM half and an idle-stream
    workaround while the current driver requests only tx/MM2S.
  - The next shortest aligned change is to remove axi_dma_0 S2MM and
    axis_idle_source from the BD, rebuild, and re-run input-sink before
    returning to count-only or full RGB writeback.

Additional evidence paths:
  - build/jpeg-pl-decoder-board-datapath-v1/run-input-sink-decode.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/input-sink-followup.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/image/latest-hashes-input-sink.txt
```

## 2026-07-10 Freeze Note

```text
Cycle ID: jpeg-pl-decoder-board-datapath-v1
Frozen on: 2026-07-10
Reason: User requested implementation pause. The cycle is still open and the
  full objective is not complete: there is no connected-board proof of
  Linux JPEG -> coherent DDR -> AXI DMA MM2S -> PL JPEG decode -> RGB888 DDR
  writeback -> Linux userspace output.

Work performed since the input-sink follow-up:
  - Removed the unused axi_dma_0 S2MM half and axis_idle_source from the BD.
  - Rebuilt the MM2S-only bitstream successfully before the AXI-Lite fix:
    STAGE1_VDMA_BOARD_BUILD_OK, WNS=+0.181 ns.
  - Packaged and deployed a BOOT.BIN containing the MM2S-only bitstream:
    sha256=9901a8aff3352ea9357b6797234ae40ce8a4ed42b6cf86a872735089fc7ffdef.
  - Re-ran input-sink with only BOOT.BIN changed. It still hung after the
    background PID was printed; a follow-up UART probe produced no command echo.
  - Inspected live /proc/device-tree and found that image.ub still described
    axi_dma_0 as two channels:
      dma-channel@43020000
      dma-channel@43020030
    while the deployed PL was already MM2S-only. This proved a PL/DT mismatch.
  - Rebuilt the PetaLinux image from the current HDF and overlays so the device
    tree matched the MM2S-only BD.
  - Deployed matching artifacts to the TF-card FAT partition:
      BOOT.BIN sha256=a6b84c57bc34dc0a23788c6d8efe7abc8de984023699341541e49897a5eaf02e
      image.ub sha256=14cf602b94e160f6fe9c6cbfed46404a73603f6d2e0c277cecead8285a1f7e88
  - Rebooted and confirmed live /proc/device-tree now exposes only:
      /proc/device-tree/amba_pl/dma@43020000/dma-channel@43020000
    with no dma-channel@43020030.
  - Loaded jpegpl_dma_probe.ko successfully on the matched image and confirmed
    /dev/jpegpl_dma_probe exists.
  - Re-ran input-sink on the matched PL/DT image. It still hung immediately
    after the background PID print; no input-sink result marker was produced.
  - Identified a new strong RTL suspect in jpeg_rgb_tile_writer.v: its AXI-Lite
    write path only completed writes when AWVALID and WVALID arrived in the same
    cycle. Real AXI-Lite masters may deliver address and data independently,
    and a stuck write response can explain the board shell losing interaction
    before any DMA result is printed.
  - Changed jpeg_rgb_tile_writer.v to latch AW and W independently, then fire
    the register write when both halves are present.
  - Changed tb_jpeg_pl_decoder_axis.v so selected configuration writes use a
    split AW/W sequence instead of always presenting address and data in the
    same cycle.
  - Re-ran the full JPEG board-datapath simulation after the AXI-Lite fix:
      JPEG_BOARD_DATAPATH_SIM_OK pixels=921600 lines=57600
      commands=57600 responses=57600 bytes=2764800 input_bytes=30054
      JPEG_PL_RTL_COMPARE_OK pixels=921600 psnr_db=39.002 mae=2.599 max_error=41
      JPEG_BOARD_DATAPATH_SIM_GATE_OK
  - Started a post-fix Vivado board build, but it did not complete to a usable
    bitstream before this freeze. The command returned exit code 1073807364
    with no final success marker in the terminal. The latest impl_1 runme.log
    tail stops during routing at "Phase 4.3 Global Iteration 2"; no timing/DRC
    gate is claimed for the AXI-Lite-fixed bitstream.

Current inference:
  - The original DataMover DSIZE/RSS issue was real but not sufficient.
  - The unused axi_dma_0 S2MM half was removed, and the matching image.ub now
    proves Linux sees the same MM2S-only DMA topology as PL, but input-sink
    still hangs.
  - The latest strongest suspect is the custom AXI-Lite slave implementation in
    jpeg_rgb_tile_writer.v, because a CPU writel/readl stuck on the PL register
    bank can freeze the shell before DMA or JPEG evidence appears.
  - The AXI-Lite fix is simulation-verified only. It has not been routed,
    packaged, deployed, or tested on the connected board.

Next resume point:
  1. Re-run the board build after the AXI-Lite fix and require
     STAGE1_VDMA_BOARD_BUILD_OK, non-negative WNS, and routed DRC with no hard
     error.
  2. Rebuild/package BOOT.BIN with the new bitstream. If the HDF did not change
     further, image.ub does not need another rebuild; if BD topology changed,
     rebuild image.ub again.
  3. Deploy the new BOOT.BIN, boot the board, verify live DT still has only the
     MM2S DMA channel, load jpegpl_dma_probe.ko, then run --input-sink first.
  4. Only if input-sink returns JPEGPL_DECODE_OK mode=input-sink should the
     cycle proceed to --count-only and then full RGB888 writeback.

Evidence paths:
  - build/jpeg-pl-decoder-board-datapath-v1/deploy-mm2s-only-boot.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/mm2s-only-postboot-login.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/deploy-mm2s-only-kernel-client.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/run-mm2s-only-input-sink.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/mm2s-only-input-sink-followup.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/inspect-live-dt-after-mm2s-hang.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/mm2s-only-image/BOOT.BIN.sha256.txt
  - build/jpeg-pl-decoder-board-datapath-v1/mm2s-only-image/image.ub.sha256.txt
  - build/jpeg-pl-decoder-board-datapath-v1/deploy-mm2s-only-imageub.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/mm2s-image-postboot-dt.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/deploy-mm2s-image-kernel-client.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/run-mm2s-image-input-sink.uart.log
  - build/jpeg-pl-decoder-board-datapath-v1/sim/xsim.log
  - build/eth-ps-pl-hdmi-pass-through/vdma-board/eth_ps_vdma_hdmi_stage1_board.runs/impl_1/runme.log
```

## 2026-07-10 Resume and Contract Correction

```text
Work resumed after the user-approved freeze.

Contract correction:
  - The 2026-07-07 third-party review misidentified AXI DataMover Full
    command fields. Vivado 2018.3 generated DataMover v5.1 HDL defines bit 31
    as DRR, bit 30 as EOF, bits 29:24 as DSA, bit 23 as TYPE, and bits 22:0 as
    BTT. There is no DSIZE field in bits 26:24 and bit 30 is not RSS.
  - The current DataMover instance is Full S2MM with DRE disabled and
    Indeterminate BTT disabled. A 48-byte command whose final beat asserts
    TLAST must therefore use DRR=0, EOF=1, DSA=0, TYPE=INCR, BTT=48.
  - DataMover status bits 7:4 are OKAY/SLVERR/DECERR/INTERR and bits 3:0 are
    TAG. The prior mock status value 0x00 and low-nibble error check did not
    model a successful real status response.

Current implementation direction:
  - Correct the Full command word and status interpretation.
  - Make AXI-Lite writes use actual independent AW/W handshakes and expose
    readable CONTROL/configuration plus a fixed VERSION register.
  - Require register readback before DMA so input-sink/count-only modes are
    proven active rather than inferred from a requested flag.
  - Re-run simulation, then build a fresh bitstream and validate in order:
    register-smoke, input-sink, count-only, full RGB888 writeback.

No post-correction bitstream or board result is claimed yet.
```

## 2026-07-10 Board Register-Smoke Diagnosis

```text
Verification completed before the board retry:
  - Full 1280x720 RTL simulation passed with input_bytes=30054,
    pixels=921600, commands=responses=57600, output_bytes=2764800, and
    rtl_fnv=0x7127882c.
  - The first clean implementation failed timing at WNS=-0.417 ns with DRC
    0 errors. Performance_Explore improved a second clean implementation to
    WNS=-0.024 ns. A reusable post-route AggressiveExplore pass closed timing
    at WNS=+0.002 ns with DRC 0 errors and 0 critical warnings.
  - The resulting BOOT.BIN hash was
    12d49ff0782a63e338f2ed6272e9d2148dd3705daca74c4596dea3728ccdd2ad;
    the existing image.ub hash remained
    14cf602b94e160f6fe9c6cbfed46404a73603f6d2e0c277cecead8285a1f7e88.
  - The connected board booted that pair, accepted root login, restored eth0,
    and answered PC ping 4/4 before the register test.

Observed register-smoke failure:
  - Loading jpegpl_dma_probe.ko succeeded and printed JPEGPL_DECODER_READY.
  - The first register-smoke attempt returned neither a success marker nor a
    shell prompt; UART and Ethernet both stopped responding.
  - A trace-only driver rebuild printed a marker before and after every MMIO
    operation. The repeat attempt printed only
    "JPEGPL_REGISTER_STEP write-dst begin" and then hung the system.
  - After JTAG recovery, a control read from the existing stable-domain PIP
    slave at 0x43c00000 returned 0x00000007 immediately on the same Linux
    image and PS AXI interconnect.
  - Therefore the first writel to REG_DST_BASE never received an AXI write
    response. No register read, DMA submission, JPEG decode, or DataMover S2MM
    command occurred in this failure.

Current correction:
  - Remove the new jpeg_clk_wiz/jpeg_reset chain from the board design.
  - Clock and reset the JPEG AXI DMA, decoder, DataMover, SmartConnect port,
    and AXI-Lite slave from the official design's already-proven FCLK0 and
    rst_ps7_0_50M domain.
  - This deliberately trades decoder frequency for a deterministic first
    board closure. Higher-frequency decoder clocking remains a post-closure
    optimization rather than part of this diagnostic.
  - Full RTL simulation after the clock/reset BD change still passed with the
    same counters, PSNR=39.002 dB, and rtl_fnv=0x7127882c.

No v4 bitstream or post-fix board result is claimed yet.
```

## 2026-07-10 v4 Board Closure and Counter Follow-Up

```text
v4 clock/reset result:
  - A clean build passed with WNS=+0.061 ns, DRC 0 errors and 0 critical
    warnings. Bitstream SHA256 was
    041ac6128ea23911f0f408dbe8a12edc806e237a4ede53cf92bdfbaa4a1d0c2c.
  - A fresh BD-only source rebuild also passed validate_bd_design and asserted
    that jpeg_pl_decoder_axis_0, AXI DMA MM2S, DataMover S2MM, SmartConnect
    aclk1, and M04 use FCLK0/rst_ps7_0_50M with no jpeg_clk_wiz/jpeg_reset.
  - BOOT.BIN SHA256
    ae6b2ca206cc55756956e262426b8a0d9e466544db434b2e7900f5111b9b3d2c
    was deployed while image.ub remained at the accepted baseline hash.

Connected-board gates on v4:
  - register-smoke PASSED with VERSION=0x4a504c31 and exact readback of
    dst_base=0x0e800000, stride=3840, dimensions=0x02d00500, and
    expected_pixels=921600.
  - input-sink PASSED: input_bytes=30054, chunks=2, output_bytes=0, pixels=0,
    commands=0, responses=0, errors=0, elapsed_ns=13708299.
  - count-only PASSED its functional gates: input_bytes=30054, pixels=921600,
    output_bytes=0, commands=0, responses=0, errors=0,
    elapsed_ns=44811577.
  - full RGB writeback PASSED: input_bytes=30054, output_bytes=2764800,
    pixels=921600, commands=responses=57600, stalls=1216590, errors=0,
    cycles=3636029, elapsed_ns=68408080, output_fnv=0x7127882c.
  - The retrieved 2764800-byte board RGB output passed the software-reference
    comparison at PSNR=39.002 dB, MAE=2.599, max_error=41, and the same
    FNV-1a value 0x7127882c.

Counter issue found by honest sequential execution:
  - input-sink intentionally returns after DMA completion while PL busy stays
    set. A following start cleared status_cycles in the control branch, but a
    later old-busy assignment in the same clock edge overwrote that clear.
  - A new sequential-mode test reproduced the issue in xsim with
    restart_cycle_counter_not_reset cycles=52.
  - Giving axi_start_fire priority over busy counters and completion logic made
    the same test pass while preserving the full 720p simulation, PSNR, and
    output FNV.
  - The userspace gate now rejects zero cycles or cycles greater than the
    ioctl elapsed nanoseconds. This catches stale cross-run counts without
    hard-coding the temporary decoder clock frequency.

Final v5 clean implementation and connected-board rerun remain pending.
```

## 2026-07-11 Final Review Follow-Up

```text
Review findings accepted and fixed:
  - DMA timeout is now one absolute jiffies deadline shared by all compressed
    input chunks and the subsequent PL-done wait.
  - A chunk timeout calls dmaengine_terminate_sync while the callback's stack
    completion is still alive; the abort path also uses synchronous terminate.
  - The userspace cycle sanity gate now assumes at most 200 MHz for this
    datapath and reports its computed max_cycles bound.
  - Full writeback accepts --expect-fnv so the fixed vector's expected RGB
    hash is a board-side pass condition, not only a printed diagnostic.

Timeout fault injection on connected v4 hardware:
  - A 4194304-byte input-sink request with timeout_ms=1 stopped after 14 DMA
    chunks, returned ETIMEDOUT, and printed JPEGPL_DECODE_ABORT.
  - UART remained interactive and PC ping remained 4/4 after the abort.
  - A subsequent normal input-sink request entered and completed DMA. Its
    output marker was correctly withheld by the strengthened cycle gate
    because v4 intentionally lacks the pending restart-counter RTL fix.

Review findings not treated as current blockers:
  - Starting while an old pixel/command/data/status transaction is active is
    unreachable through the mutex-serialized driver: full/count-only return
    only after PL done and all status responses; input-sink generates no
    output transactions. Direct /dev/mem writes outside this client remain
    unsupported.
  - The external board RGB was already retrieved and compared pixel-by-pixel;
    --expect-fnv additionally moves the known-vector byte identity into the
    board utility itself.

Final v5 clean implementation and strict final board rerun remain pending.
```

## 2026-07-11 Final Closure

```text
Final result:
  - Final simulation passed the input-sink/restart regression, complete frame
    counters, software-reference PSNR gate, and fixed-vector FNV gate.
  - The combined v5 implementation closed at WNS=+0.151 ns with post-route
    DRC 0 errors and 0 critical warnings.
  - Hash-checked BOOT.BIN was deployed with a recovery copy; image.ub remained
    unchanged.
  - The strict-v6 client passed register-smoke, input-sink, count-only, and
    full RGB writeback in order on the connected board.
  - Full writeback returned 2764800 bytes, 921600 pixels, 57600 matched
    commands/responses, zero hardware errors, and FNV=0x7127882c.
  - Retrieved RGB passed the host reference at PSNR=39.002 dB and exact FNV.
  - UART, kernel health scan, and PC ping 4/4 remained healthy after the run.

Closure evidence:
  - docs/reports/jpeg-pl-decoder-board-datapath-v1.md
  - build/jpeg-pl-decoder-board-datapath-v1/sim-final-v6/
  - build/jpeg-pl-decoder-board-datapath-v1/vivado-final-v5/reports/
  - build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-strict-cycle-gate.json
  - build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-pixel-comparison.json
  - build/jpeg-pl-decoder-board-datapath-v1/board-final-v6-final-health-uart.log

Boundary:
  The single-frame board data path is closed. Sustained target-rate video and
  GStreamer jpegpldec backend integration remain separate future cycles.
```

## Third-Party Review (2026-07-07)

Reviewer: opencode agent review pass on the frozen
`jpeg-pl-decoder-board-datapath-v1` cycle.

### Evidence re-interpretation

The frozen note describes the failure as "one-frame hardware decode did not
produce usable status/output evidence" and a "suspected board-side
non-interactive state." The raw UART logs support a stronger reading: the board
did not merely time out, it hung at decode start.

- `run-current-one-frame-decode-watchdog.uart.log` shows the shell echo stops
  immediately after `[1] 1305` (the backgrounded decode PID). None of the
  subsequent host-injected commands (`sleep 25`, `kill -0`, `dmesg | tail`,
  `ls -l`, `sha256sum`) produce any board echo.
- `rebind-dma-after-jtag.log` shows later `unbind`/`bind` writes to
  `/sys/bus/platform/drivers/xilinx-vdma` also produce no echo, i.e. the kernel
  shell is dead, not just the userspace test process.

This is consistent with a kernel-level or AXI-bus-level hang triggered by the
decode ioctl, not a userspace timeout. The frozen note's residual risk
("current evidence does not yet distinguish AXI bus hang, DataMover command
issue, driver wait path, or PL writer state-machine deadlock") remains
accurate, but the bus-hang branch should be treated as the leading hypothesis
because a pure driver-wait timeout would not kill the shell.

### Primary suspected root cause: DataMover S2MM command-word fields

`examples/eth-ps-pl-hdmi-pass-through/rtl/jpeg_rgb_tile_writer.v:156-158`
assembles the 72-bit S2MM command word as:

```verilog
{4'b0000, command_tag, flush_address, 1'b0, 1'b1, 6'b000000,
 1'b1, BLOCK_ROW_BYTES}
```

Mapped against the Xilinx AXI DataMover v5.1 S2MM command bit layout
(PG022), the fields decode as:

- BTT [22:0] = 48 (correct)
- Type [23] = 1 (correct for S2MM)
- DSIZE [26:24] = 3'b000 (8-bit stream) — the BD configures
  `c_s_axis_s2mm_tdata_width {32}` in
  `examples/eth-ps-pl-hdmi-pass-through/tcl/create_ps_emio_vdma_hdmi_bd.tcl`,
  so DSIZE should be 3'b010. This mismatch is the strongest candidate for the
  hang: a real DataMover strict on DSIZE would expect 48 beats at 8-bit while
  the writer emits 12 beats at 32-bit, never see tlast, hold the S2MM write
  command open, and lock the AXI write channel until the CPU stalls on the same
  interconnect.
- RSS [30] = 1 on every command, which resets the status stream per transfer;
  unusual and a secondary suspect.
- SADDR [63:32] = flush_address (correct for the 32-bit address width default).
- TAG [67:64] = command_tag (correct).

The reason this passed xsim but fails on hardware is that the board-datapath
testbench `examples/eth-ps-pl-hdmi-pass-through/sim/tb_jpeg_pl_decoder_axis.v`
is a mock, not the real DataMover IP. It checks only `cmd_tdata[22:0] == 48`
and reads `cmd_tdata[63:32]` as the address, then unconditionally returns
`sts_tdata = 8'd0` after a fixed 3-cycle delay
(`tb_jpeg_pl_decoder_axis.v:142-219`). It never decodes DSIZE, RSS, Type, or
TAG, so a malformed command word cannot fail simulation. The frozen note's
claim that "the xsim DataMover mock was sufficient for functional intent but
too weak to prove exact Xilinx AXI DataMover command/status behavior in
hardware" is correct; this review localizes the weakness to the command-word
field decoding.

### Secondary suspects

- The unused `axi_dma_0` S2MM half fed by `axis_idle_source_0` increases the
  AXI lock surface and is not required for the decode route, as the frozen
  note already flags.
- Driver ordering in `software/kernel/jpegpl_dma_probe/src/jpegpl_dma_probe.c`
  writes `REG_CONTROL` (pulse `decode_start`, set `busy`) before writing
  `REG_DST_BASE`/`REG_STRIDE`/`REG_DIMENSIONS`/`REG_EXPECTED_PIXELS`. The RTL
  tolerates this because config is read at flush time, not at CONTROL time,
  so this is not the bug, but it is worth reordering for clarity in a later
  cleanup.

### Opinion on the proposed diagnostic path

The frozen note's shortest-next-diagnostic-path (count-only/no-writeback mode
to bisect decoder/MM2S from DataMover S2MM writeback) is endorsed. This review
adds one mandatory complement:

- A count-only run can localize the fault layer but cannot prevent regression
  of the command-word fields. The mock testbench must be replaced with the
  real `axi_datamover` IP in the board-datapath simulation so that DSIZE, RSS,
  Type, and TAG are validated against the actual IP in xsim. Without this,
  any future command-word edit will again pass a mock and hang on hardware.

### Recommended next steps, cheapest first

1. Correct the command word in `jpeg_rgb_tile_writer.v`: set DSIZE to
   `3'b010` and RSS to `1'b0`; rebuild the bitstream and retry the one-frame
   decode. This is the cheapest single experiment and, if DSIZE is the bug,
   closes the cycle directly.
2. In parallel, add the count-only/no-writeback mode to bisect the design, as
   the frozen note proposes.
3. Replace the mock DataMover in `tb_jpeg_pl_decoder_axis.v` with the real
   `axi_datamover` IP so command-word regressions are caught in xsim before
   any board run.
4. Remove the unused `axi_dma_0` S2MM half and `axis_idle_source` from the BD
   unless a later design needs them.

If step 1 passes, steps 1 and 4 close the cycle. If step 1 fails, step 2
isolates the fault boundary, and step 3 ensures the next fix is verifiable in
simulation.

## Recently Closed Cycle

```text
Cycle ID: jpeg-pl-decoder-core-qualification
Result: PASSED. Pinned `ultraembedded/core_jpeg` performed complete baseline
  JPEG RTL decode for the current GStreamer profile. xsim emitted 921600
  unique RGB pixels in 1973637 cycles; software comparison reached 39.002 dB
  PSNR. XC7Z020 standalone implementation closed at 66.667 MHz with WNS
  +0.185 ns and zero DRC errors, corresponding to 29.605 ms/frame and 33.779
  theoretical fps. This is not yet a board-live jpegpldec backend.
Evidence: docs/reports/jpeg-pl-decoder-core-qualification.md,
  build/jpeg-pl-decoder-qualification/summary.json,
  build/jpeg-pl-decoder-qualification/sim/xsim.log,
  build/jpeg-pl-decoder-qualification/impl/reports/post_route_timing_summary.rpt
Board action: none. No combined bitstream or persistent board state changed.

Cycle ID: jpegpldec-pl-decode-720p30-v0
Result: PASSED for the first PL decoder-backend boundary. `jpegpldec` now has
  `backend=pl-compressed-probe` and `probe-mode=compressed-dma-probe`, which
  taps compressed 1280x720 JPEG buffers before the internal software `jpegdec`
  child, parses JPEG metadata, sends the compressed bytes through
  `/dev/jpegpl_dma_probe`, and verifies byte-identical return. The passing
  connected run logged four 1280x720 baseline 4:2:0 JPEG frames, zero DMA
  failures, PL counters of 8 DMA transactions / 120408 bytes, and dynamic HDMI
  return. This does not claim PL JPEG entropy decode, IDCT, raw-frame
  generation, 30 fps throughput, or native 720p HDMI output.
Evidence: docs/reports/jpegpldec-pl-decode-720p30-v0.md,
  build/jpegpldec-pl-decode-720p30-v0-pass3/summary.json,
  build/jpegpldec-pl-decode-720p30-v0-pass3/uart-stop-dma-probe.log,
  build/jpegpldec-pl-decode-720p30-v0-pass3/hdmi-ball-motion-validation.json
Board action: loaded temporary plugin/module from /tmp, ran a temporary
  GStreamer receiver, sent 1280x720 RTP/JPEG from the PC, and captured HDMI.
  No BOOT.BIN, image.ub, rootfs, bitstream, TF-card image, JTAG programming,
  or board flash changed.

Cycle ID: 720p30-jpeg-chain-contract
Result: PASSED for contract and gate creation. The connected-board software
  reference gate accepted real 1280x720 RTP/JPEG input and downscaled to the
  current 800x600 output path, but it did not meet the 30 fps target:
  fakesink averaged 5.47 fps and fbdevsink averaged 5.37 fps. This is recorded
  as `720P30_JPEG_CHAIN_GATE_BLOCKED status=blocked-software-baseline`, and it
  supports opening `jpegpldec-pl-decode-720p30-v0` rather than repeating generic
  profiling.
Evidence: docs/protocols/jpegpldec-720p30-contract.md,
  docs/reports/720p30-jpeg-chain-contract.md,
  tools/run_720p30_jpeg_chain_gate.ps1,
  build/720p30-jpeg-chain-contract/video-bottleneck-summary.json,
  build/720p30-jpeg-chain-contract/720p30-gate-summary.json
Board action: ran temporary GStreamer benchmark receivers over UART and sent
  1280x720 RTP/JPEG over Ethernet. No BOOT.BIN, image.ub, rootfs, bitstream,
  TF-card image, JTAG programming, or board flash changed.

Cycle ID: jpegpldec-pl-returned-buffer-writeback
Result: PASSED. `jpegpldec probe-mode=dma-writeback` copied decoded I420
  frames into a staging buffer, stamped a deterministic luma marker before
  DMA, sent the staging data through coherent AXI DMA MM2S -> PL -> S2MM, and
  wrote the returned bytes into the downstream GstBuffer. Sixty logical frames
  completed; PL counters recorded 480 transactions and 6,912,000 bytes. HDMI
  dynamic validation passed with 300 samples and 104 unique hashes, and the
  writeback marker validator passed 224/300 frames. This closes copy-back
  writeback, not zero-copy or PL JPEG decode.
Evidence: docs/reports/jpegpldec-pl-returned-buffer-writeback.md,
  build/jpegpldec-dma-writeback/summary.json,
  build/jpegpldec-dma-writeback/uart-stop-dma-probe.log,
  build/jpegpldec-dma-writeback/hdmi-ball-motion-validation.json,
  build/jpegpldec-dma-writeback/dma-writeback-marker-validation.json
Board action: loaded module/plugin from /tmp and ran the connected writeback
  video probe; no boot image or nonvolatile storage changed.

Cycle ID: jpegpldec-ps-pl-buffer-datapath-probe
Result: PASSED. `jpegpldec probe-mode=dma-probe` sent 60 real 115200-byte
  decoded I420 frames through coherent AXI DMA MM2S -> PL -> S2MM buffers.
  Driver-internal splitting contained the timed 14-bit BTT limit as eight DMA
  transactions per logical frame. PL counters recorded 480 transactions and
  6,912,000 bytes; no DMA mismatch was reported. Dynamic HDMI validation saw
  300 samples, 121 unique hashes, and 270.141 pixels of motion. The gate to PL
  writeback is cleared, but PL-returned GstBuffer replacement and zero-copy are
  not claimed.
Evidence: docs/reports/jpegpldec-ps-pl-buffer-datapath-probe.md,
  build/jpegpldec-dma-buffer-probe/summary.json,
  build/jpegpldec-dma-buffer-probe/uart-stop-dma-probe.log,
  build/jpegpldec-dma-buffer-probe/hdmi-ball-motion-validation.json
Board action: loaded module/plugin from /tmp and ran the connected video probe;
  no boot image or nonvolatile storage changed.

Cycle ID: jpegpl-dma-probe-kernel-client-build
Result: PASSED for source/build feasibility. Added jpegpl_dma_probe.ko, a
  misc-device DMAengine client that allocates coherent TX/RX buffers with
  dmam_alloc_coherent, exposes JPEGPL_DMA_PROBE_IOC_RUN through
  /dev/jpegpl_dma_probe, and is intended to loop a later jpegpldec decoded
  buffer through AXI DMA MM2S -> axis_dma_probe_core -> AXI DMA S2MM. Added an
  ARM userspace loopback probe and a device-tree client-node fragment. The
  existing PetaLinux 2018.3 kernel build tree compiled the module and ARM test
  tool, and the host self-test passed. This still does not complete the active
  goal because the module has not loaded on the board, the DT is not rebuilt
  with axi_dma_0, no real jpegpldec frame used the ioctl, and cache coherency
  plus GStreamer writeback remain unverified.
Evidence: docs/reports/jpegpl-dma-probe-kernel-client-build.md,
  build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe.ko,
  build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe_test,
  build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe_test_host.log
Board action: none. No module insertion, BOOT.BIN/image.ub update, TF-card
  image, JTAG programming, or board flash was changed.

Cycle ID: jpegpldec-pl-dma-endpoint-bd-build
Result: PASSED for hardware endpoint construction. Added a simple-mode AXI DMA
  loop around axis_dma_probe_core in the stage-1 VDMA board BD. The endpoint
  exposes axi_dma_0 at 0x43020000 and axis_dma_probe_core_0 at 0x43c10000,
  connects DMA MM2S/S2MM streams through the PL probe core, reaches DDR through
  HP0, and routes DMA interrupts to the PS IRQ concat. xsim still passes
  AXI_FRAMEBUFFER_LINE_READER_OK, PL_CONTROLLED_PIP_CORE_SIM_OK,
  PL_DUAL_VDMA_PIP_CORE_SIM_OK, and AXIS_DMA_PROBE_CORE_SIM_OK. The board
  bitstream build passed with STAGE1_VDMA_BOARD_BUILD_OK and WNS=0.245.
  This still does not complete the larger jpegpldec PS-to-PL buffer goal
  because there is no Linux DMA client, coherent/CMA buffer allocation,
  jpegpldec handoff, cache-coherency board proof, or GStreamer writeback path.
Evidence: docs/reports/jpegpldec-pl-dma-endpoint-bd-build.md,
  build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/stage1_vdma_board_stdout.log,
  build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/timing_summary.rpt,
  build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/post_route_drc.rpt
Board action: none. Bitstream was built but no BOOT.BIN, image.ub, rootfs,
  TF-card image, JTAG programming, or board flash was changed.

Cycle ID: jpegpldec-pl-dma-probe-core-sim
Result: PASSED for PL data-plane core simulation. Added a 32-bit AXI4-Stream
  pass-through/marker/checksum core intended to sit between AXI DMA MM2S and
  AXI DMA S2MM, plus a testbench in the eth-ps-pl-hdmi-pass-through xsim flow.
  Existing framebuffer/PIP simulations still pass, and the new test reports
  AXIS_DMA_PROBE_CORE_SIM_OK. This does not complete the larger jpegpldec
  PS-to-PL buffer goal because there is still no AXI DMA BD endpoint, Linux
  coherent/CMA buffer client, cache-coherency board proof, or GStreamer
  writeback path.
Evidence: docs/reports/jpegpldec-pl-dma-probe-core-sim.md,
  build/eth-ps-pl-hdmi-pass-through/sim/tb_axis_dma_probe_core-xsim-run.log
Board action: none. Simulation-only cycle; no BOOT.BIN, image.ub, rootfs,
  bitstream, TF-card image, JTAG, or board flash was changed.

Cycle ID: jpegpldec-dma-capability-route-gate
Result: PASSED as a negative route gate. Board probe confirmed the running
  image has CMA, DMA shared buffer, Xilinx DMA, and VDMA support, but exposes
  no /dev/dma_heap, udmabuf, ion, or /dev/uio* user-space DMA buffer interface
  that jpegpldec can use for a private PS-to-PL buffer loopback.
Evidence: docs/reports/jpegpldec-dma-capability-route-gate.md,
  build/jpegpldec-dma-capability-route-gate/summary.json,
  build/jpegpldec-dma-capability-route-gate/uart-dma-capability.log
Board action: UART read-only capability probe. No BOOT.BIN, image.ub, rootfs,
  bitstream, TF-card image, JTAG, or board flash was changed.

Cycle ID: jpegpldec-pl-buffer-datapath-probe
Result: PARTIAL PASS toward the larger PS-to-PL buffer objective. Added
  `probe-mode=pl-buffer-probe`, which maps decoded I420 buffers inside
  jpegpldec, stamps a top-left luma checker, logs checksum before/after, and
  verifies the marker in HDMI-return frames. This proves data produced inside
  jpegpldec reaches the existing framebuffer -> VDMA -> PL PIP -> HDMI path,
  but does not prove a private DMA-safe buffer or PL writeback to GStreamer.
Evidence: docs/reports/jpegpldec-pl-buffer-datapath-probe.md,
  build/jpegpldec-pl-buffer-datapath-probe/summary.json,
  build/jpegpldec-pl-buffer-datapath-probe/uart-start-profile.log,
  build/jpegpldec-pl-buffer-datapath-probe/buffer-marker-validation.json
Board action: deployed /tmp/gst-plugins/libgstjpegpldec.so over Ethernet,
  moved PIP to bottom-right, restarted the board GStreamer receiver with
  `jpegpldec probe-mode=pl-buffer-probe`, and verified dynamic HDMI return plus
  visible buffer marker. No BOOT.BIN, image.ub, rootfs, bitstream, TF-card
  image, JTAG, or board flash was changed.

Cycle ID: jpegpldec-pl-probe-and-profile
Result: PASSED. Upgraded the project-owned GStreamer `jpegpldec` element with
  pad-level profiling and a `probe-mode=pl-probe` hardware status probe. The
  plugin now emits `JPEGPLDEC_PROFILE` timing markers and reads the existing PL
  PIP AXI-Lite status registers while the live RTP/JPEG-to-HDMI path runs.
Evidence: docs/reports/jpegpldec-pl-probe-and-profile.md,
  build/jpegpldec-pl-probe-and-profile/summary.json,
  build/jpegpldec-pl-probe-and-profile/uart-deploy-inspect.log,
  build/jpegpldec-pl-probe-and-profile/uart-start-profile.log,
  build/jpegpldec-pl-probe-and-profile/dashboard-output-mjpeg-probe/mjpeg-stream-probe.json
Board action: deployed /tmp/gst-plugins/libgstjpegpldec.so over Ethernet,
  loaded it with GST_PLUGIN_PATH, restarted the board GStreamer receiver with
  `jpegpldec probe-mode=pl-probe`, and verified dynamic HDMI return. No
  BOOT.BIN, image.ub, rootfs, bitstream, TF-card image, JTAG, or board flash
  was changed.

Cycle ID: jpegpldec-plugin-skeleton
Result: PASSED. Added a project-owned GStreamer `jpegpldec` plugin skeleton
  and verified it on the board as a drop-in replacement for `jpegdec` in the
  RTP/JPEG receiver path. The first implementation wraps the system `jpegdec`
  as a software reference child named `software-reference-decoder`; it is not
  a PL acceleration claim yet.
Evidence: docs/reports/jpegpldec-plugin-skeleton.md,
  build/jpegpldec-plugin-skeleton/uart_deploy_inspect.log,
  build/jpegpldec-plugin-skeleton/uart_start_jpegpldec_pipeline.log,
  build/jpegpldec-plugin-skeleton/mjpeg-probe/mjpeg-stream-probe.json
Board action: deployed /tmp/gst-plugins/libgstjpegpldec.so over Ethernet,
  loaded it with GST_PLUGIN_PATH, restarted the board GStreamer receiver with
  jpegpldec, and verified dynamic HDMI return. No BOOT.BIN, image.ub, rootfs,
  bitstream, TF-card image, JTAG, or board flash was changed.

Cycle ID: dashboard-console-copy-trim
Result: PASSED. Removed redundant explanatory text from the visible dashboard
  panels while keeping machine-readable status/debug fields in /api/state and
  logs. Dashboard self-test and generated HTML absence check passed.
Evidence: docs/reports/dashboard-console-copy-trim.md,
  build/dashboard-console-copy-trim/index.html,
  build/dashboard-console-copy-trim/state.json
Board action: none. PC-side dashboard rendering change only.

Cycle ID: video-bottleneck-probe
Result: PASSED for measurement. The bottleneck probe measured the current
  320x240 RTP/JPEG input path at 5/10/15/30fps into both fakesink and fbdevsink.
  At 320x240 input, board software JPEG decode plus convert/scale reached
  about 30.50fps into fakesink and about 27.69fps into fbdevsink, with no
  fpsdisplaysink drops. A live raw 800x600 framebuffer-native direct-copy run
  also received 42 frames / 50400 packets with dropped=0, but its HDMI/MJPEG
  return trace failed in this rerun, so it is receiver-throughput evidence only.
Evidence: docs/reports/video-bottleneck-probe.md,
  build/video-bottleneck-probe/video-bottleneck-summary.json,
  build/video-bottleneck-probe/raw-direct-copy/uart_after_direct_copy.log
Board action: ran temporary GStreamer benchmark receivers and one raw
  direct-copy receiver from UART. No BOOT.BIN, image.ub, rootfs, bitstream, or
  board flash was changed.

Cycle ID: pip-tcp-control-service
Result: PASSED. Runtime PIP preset control now has a low-latency TCP path.
  The board runs /tmp/pip_effect_server as a resident POSIX TCP daemon on
  port 5012, maps the PL PIP AXI-Lite register block once through /dev/mem,
  and accepts short preset/status commands. The dashboard prefers TCP for PIP
  buttons and keeps UART as fallback. The dashboard action response and state
  now expose transport, latency, and parsed PIP register readback.
Evidence: docs/reports/pip-tcp-control-service.md,
  build/pip-tcp-control-service/uart_deploy_start_pip_server.log,
  build/pip-tcp-control-service/dashboard-probe/pip-control-latency-report.json
Board action: deployed /tmp/pip_effect_server over Ethernet with board wget,
  started it from UART, and verified direct PC TCP plus dashboard API control.
  No BOOT.BIN, image.ub, rootfs, FPGA bitstream, or board flash was changed.

Cycle ID: pl-controlled-pip-effect-pipeline
Result: PASSED. The same-source PL PIP effect is now runtime-controllable from
  the dashboard through UART and a board-side /dev/mem helper. The PIP core has
  AXI-Lite registers for enable/bypass, x/y position, 1/2 vs 1/4 scale, border,
  and normal/invert/grayscale small-window effect. The updated bitstream met
  timing with WNS=0.197 and DRC errors=0, was packaged into BOOT.BIN, deployed
  to the TF-card boot partition after SHA-256 verification, and booted on the
  board. Dashboard buttons changed real PL registers, GStreamer video ran,
  HDMI capture failed the PIP validator after bypass as expected, and passed
  again after restoring bottom-right PIP. The dashboard MJPEG return passed
  PIP validation for 24/24 frames.
Evidence: docs/reports/pl-controlled-pip-effect-pipeline.md,
  build/pl-controlled-pip-effect-pipeline/hdmi-pip-bypass-capture/,
  build/pl-controlled-pip-effect-pipeline/hdmi-pip-restored-capture/,
  build/pl-controlled-pip-effect-pipeline/dashboard-mjpeg-pip/,
  build/pl-controlled-pip-effect-pipeline/uart_deploy_config_tools.log
Board action: replaced TF-card BOOT.BIN only via running board Linux wget over
  Ethernet after SHA-256 verification, retained a BOOT.BIN backup, rebooted,
  deployed vdma_mm2s_config and pip_effect_ctl to /tmp, configured VDMA1, ran
  the GStreamer dashboard stream, and verified HDMI through the PC capture
  adapter. image.ub/rootfs and board flash were not rewritten.

Cycle ID: pl-dual-vdma-pip-mvp
Result: PASSED. The first PL-side effect is now demonstrated on top of the
  known-good 5fps GStreamer closed loop. Linux/GStreamer receives PC RTP/JPEG
  video and writes the DDR framebuffer through fbdevsink. PL reads that same
  framebuffer through two MM2S VDMA streams, overlays a fixed same-source PIP
  window in AXI4-Stream logic, and drives HDMI. The PC dashboard right-panel
  MJPEG endpoint returned dynamic HDMI frames with the PIP present.
Evidence: docs/reports/pl-dual-vdma-pip-mvp.md,
  build/pl-dual-vdma-pip-mvp/hdmi-pip-overlay-capture/,
  build/pl-dual-vdma-pip-mvp/dashboard-mjpeg-pip/,
  build/pl-dual-vdma-pip-mvp/uart_deploy_config_vdma1.log
Board action: replaced TF-card BOOT.BIN only via running board Linux wget over
  Ethernet after SHA-256 verification, retained the previous BOOT.BIN backup,
  rebooted, configured axi_vdma_1 from userspace, and validated HDMI through
  the PC capture adapter. image.ub/rootfs and board flash were not rewritten.

Cycle ID: dashboard-gstreamer-chinese-control
Result: PASSED. The visual dashboard now defaults to the standard GStreamer
  route instead of the retired custom UDP/fbdev route. The browser-visible UI
  is Chinese-localized and shows `链路=GStreamer 传输=RTP/raw`. `start-stream`
  starts the board GStreamer receiver over UART, starts the PC GStreamer
  RTP/raw sender, and exposes HDMI return through `/api/output-stream.mjpeg`.
  Connected-board validation passed with HDMI_BALL_MOTION_OK samples=12
  unique_hashes=12 frames_with_ball=12 x_span=144.354 y_span=266.92, and the
  dashboard MJPEG endpoint passed with MJPEG_STREAM_PROBE_OK frames=24
  unique=11.
Evidence: docs/reports/dashboard-gstreamer-chinese-control.md,
  build/dashboard-gstreamer-chinese-control/,
  build/dashboard-gstreamer-live/hdmi-motion-check2/, and
  build/dashboard-gstreamer-live/mjpeg-probe2/
Board action: ran userspace GStreamer pipelines on the already-booted
  PetaLinux rootfs, sent RTP/raw over Ethernet, controlled through UART, and
  captured HDMI through the PC adapter. No Vivado/PetaLinux rebuild, JTAG
  programming, TF-card image write, or board flash write was performed.

Cycle ID: gstreamer-rtp-raw-kmssink-closed-loop
Result: PASSED. PC GStreamer 1.28.4 from the local conda environment generated
  a moving-ball RTP/raw RGB stream, sent it over Ethernet, and the board
  GStreamer 1.12.2 pipeline received it with udpsrc, rtpjitterbuffer,
  rtpvrawdepay, videoconvert, videoscale, and kmssink. The passing route uses
  320x240 RTP/raw input scaled on the board to 800x600 BGR for HDMI output.
  kmssink required force-modesetting=true; without it, both local and network
  tests displayed a valid first frame but stayed static. Final HDMI return
  validation passed with HDMI_BALL_MOTION_OK samples=24 unique_hashes=23
  frames_with_ball=24 x_span=110.605 y_span=200.274. A diagnostic fakesink
  route counted 59 complete depay buffers from a 60-frame PC send.
Evidence: docs/reports/gstreamer-rtp-raw-kmssink-closed-loop.md and
  build/gstreamer-rtp-kmssink-route/
Board action: ran userspace GStreamer pipelines on the already-booted
  PetaLinux rootfs, sent RTP/raw over Ethernet, controlled through UART, and
  captured HDMI through the PC adapter. No Vivado/PetaLinux rebuild, JTAG
  programming, TF-card image write, or board flash write was performed.

Cycle ID: petalinux-gstreamer-rootfs-integration
Result: PASSED for dependency/image integration. The project PetaLinux image
  now boots on the connected board with GStreamer 1.12.2, gst-launch,
  gst-inspect, base/good/bad plugins, kmssink, DRM/KMS userspace tools, and
  V4L utilities present in the rootfs. The board downloaded the new image.ub
  over Ethernet, verified SHA-256
  3c8f131a1e8424e08a73c356bdc3e808ec6d42c79dfe5cc063642d046830d6b4,
  backed up the previous TF-card image, rebooted, and exposed /dev/dri/card0
  plus /dev/fb0. A GStreamer fakesink smoke pipeline passed; kmssink is present
  and negotiated 800x600 KMS caps in a background smoke run. This does not
  claim the final RTP/raw-video-to-kmssink route is complete.
Evidence: docs/reports/petalinux-gstreamer-rootfs-integration.md and
  build/petalinux-gstreamer-rootfs-integration/
Board action: replaced TF-card image.ub via running board Linux wget over
  Ethernet after SHA-256 verification, retained the previous image.ub backup,
  rebooted from TF card, and verified the runtime through UART. No Vivado
  rebuild, JTAG programming, QSPI, NAND, eMMC, or other non-TF-card board
  nonvolatile write was performed.

Cycle ID: gstreamer-hot-install-first
Result: FAILED. The hot-install-first assumption was falsified before any
  video route gate ran. PC-side GStreamer installation through winget found
  gstreamerproject.gstreamer 1.28.4 but failed because the downloaded official
  installer did not match the winget manifest hash; `gst-launch-1.0` and
  `gst-inspect-1.0` remained missing. More importantly, the connected board
  has no apt, apt-get, dpkg, opkg, rpm, dnf, yum, or pacman command; it also
  has no default route or DNS and uses a small in-memory rootfs plus a mounted
  FAT boot partition, not a package-managed ext4 rootfs. `/dev/dri/card0`
  exists, but board-side GStreamer hot install is not possible on this image.
  pass_condition=(pc_gst_launch_present == 1 and pc_gst_inspect_present == 1
  and pc_required_gst_elements_missing == 0 and board_apt_probe_completed == 1
  and board_install_method == apt-hot-install and
  board_apt_update_status == pass and board_apt_install_status == pass and
  board_gst_launch_present == 1 and board_gst_inspect_present == 1 and
  board_required_gst_elements_missing == 0 and board_drm_card0_present == 1
  and board_rootfs_free_mb_after >= 200 and petalinux_image_built == 0 and
  tf_card_image_written == 0),
  measured=(pc_gst_launch_present=0, pc_gst_inspect_present=0,
  pc_required_gst_elements_missing=4, pc_winget_package_found=1,
  pc_winget_install_status=failed_hash_mismatch,
  board_apt_probe_completed=1, board_install_method=none,
  board_apt_update_status=not_run_no_apt,
  board_apt_install_status=not_run_no_apt, board_gst_launch_present=0,
  board_gst_inspect_present=0, board_required_gst_elements_missing=5,
  board_drm_card0_present=1, board_package_managers_present=0,
  board_default_route_present=0, board_dns_present=0,
  board_rootfs_type=rootfs_ram, board_rootfs_size_mb=237,
  tf_boot_partition_mounted_mb=1020, petalinux_image_built=0,
  tf_card_image_written=0).
Evidence: docs/reports/gstreamer-hot-install-first.md and
  build/gstreamer-hot-install-first/
Board action: UART read-only probes only. No apt install, package install,
  Vivado/PetaLinux build, JTAG programming, TF-card image write, board flash
  write, RTP pipeline, or HDMI capture was performed.

Cycle ID: gstreamer-rtp-kmssink-route-gate
Result: FAILED before verification. The GStreamer direction is correct, but
  the independent audit in docs/reports/eth-ps-pl-hdmi-pass-through.md found
  that the frozen pass_condition removed required rulers:
  frame_duration_stddev_ms<=4.0, frame-drop accountability, and frame-id
  correspondence. Per Rule 1, the frozen bar is not edited in place; the next
  cycle must reopen with corrected thresholds before running verification.
  pass_condition=(pc_gst_launch_present == 1 and board_gst_launch_present == 1
  and board_required_gst_elements_present == 5 and
  board_required_gst_elements_missing == 0 and board_sink == kmssink and
  board_display_device == /dev/dri/card0 and transport == rtp-raw-udp and
  self_written_udp_receiver_used == 0 and fbdev_live_write_used == 0 and
  pc_sender_frames >= 120 and hdmi_captured_frames >= 120 and
  captured_motion_frames >= 120 and tearing_frames == 0 and
  validator_status == pass),
  measured=(not_run, audit_status=fail,
  missing_required_gate_fields=frame_duration_stddev_ms<=4.0,
  drop_rate<=0.05_or_sent_equals_received, frame_id_correspondence).
Evidence: docs/reports/gstreamer-rtp-kmssink-route-gate.md and
  docs/reports/eth-ps-pl-hdmi-pass-through.md
Board action: none. No UART command, Ethernet test, HDMI capture,
  Vivado/PetaLinux build, TF-card write, JTAG programming, or board flash
  write was performed.

Cycle ID: gstreamer-rtp-kmssink-corrected-route-gate
Result: FAILED. The corrected pass gate restored smoothness, drop-rate, and
  frame-id correspondence rulers, then failed at the cheapest dependency
  check: PC `gst-launch-1.0` and `gst-inspect-1.0` are missing, and board
  `gst-launch-1.0` and `gst-inspect-1.0` are also missing. `/dev/dri/card0`
  exists, but the current image cannot run `kmssink` or required GStreamer
  elements. No RTP sender, receive pipeline, HDMI capture, trace validator, or
  tearing validator was run.
  pass_condition=(pc_gst_launch_present == 1 and board_gst_launch_present == 1
  and pc_required_gst_elements_missing == 0 and
  board_required_gst_elements_missing == 0 and board_sink == kmssink and
  board_display_device == /dev/dri/card0 and transport == rtp-raw-udp and
  jitter_buffer == rtpjitterbuffer and self_written_udp_receiver_used == 0
  and fbdev_live_write_used == 0 and trace_sent_frames >= 120 and
  trace_captured_frames >= 114 and trace_matched_frames >= 114 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0 and
  trace_image_path_failures == 0 and hdmi_captured_frames >= 120 and
  frame_duration_stddev_ms <= 4.0 and tearing_frames == 0 and
  unified_validator_status == pass and tearing_validator_status == pass),
  measured=(pc_gst_launch_present=0, board_gst_launch_present=0,
  pc_required_gst_elements_missing=5, board_required_gst_elements_missing=5,
  board_sink=missing, board_display_device=/dev/dri/card0, transport=not-run,
  jitter_buffer=missing, self_written_udp_receiver_used=0,
  fbdev_live_write_used=0, trace_sent_frames=0, trace_captured_frames=0,
  trace_matched_frames=0, trace_drop_rate=1.0,
  trace_order_violations=not-run, trace_content_mismatches=not-run,
  trace_black_frames=not-run, trace_image_path_failures=not-run,
  hdmi_captured_frames=0, frame_duration_stddev_ms=not-run,
  tearing_frames=not-run, unified_validator_status=not-run,
  tearing_validator_status=not-run).
Evidence: docs/reports/gstreamer-rtp-kmssink-corrected-route-gate.md
Board action: UART shell inspection only. No Ethernet video send, HDMI
  capture, Vivado/PetaLinux build, TF-card write, JTAG programming, or board
  flash write was performed.

Cycle ID: gstreamer-dependency-provisioning
Result: FAILED before provisioning. The cycle was opened with a pass condition
  that required PetaLinux image rebuild and TF-card update. A shorter valid
  route exists: hot-installing GStreamer into the running Linux rootfs via apt
  if apt and network access work. Because the frozen bar cannot be edited in
  place, this cycle is closed and a hot-install-first cycle must be opened.
  pass_condition=(pc_gst_launch_present == 1 and pc_gst_inspect_present == 1
  and pc_required_gst_elements_missing == 0 and board_gst_launch_present == 1
  and board_gst_inspect_present == 1 and board_required_gst_elements_missing
  == 0 and board_drm_card0_present == 1 and petalinux_image_built == 1 and
  board_booted_updated_image == 1 and tf_card_update_verified == 1),
  measured=(pc_gst_launch_present=0, pc_gst_inspect_present=0,
  board_gst_launch_present=0, board_gst_inspect_present=0,
  board_drm_card0_present=1, petalinux_image_built=0,
  board_booted_updated_image=0, tf_card_update_verified=0,
  cycle_scope_error=hot_install_path_excluded).
Evidence: docs/reports/gstreamer-dependency-provisioning.md
Board action: none.

Cycle ID: drm-kms-local-motion-pacing
Result: PASSED. Isolated the board display side by generating textured motion
  locally on the Zynq Linux userspace process, writing only DRM dumb back
  buffers, and presenting with DRM/KMS page-flip vblank events. The connected
  board run proved the current display path can meet the frozen
  smoothness/tearing gate when full-frame UDP receive is removed:
  drm_dumb_buffers=2, drm_page_flip_calls=120,
  drm_vblank_flip_events=120, generated_frames=120,
  captured_motion_frames=255, tearing_frames=0,
  frame_duration_stddev_ms=1.514, and validator_status=pass.
  pass_condition=(display_backend == drm-kms and drm_device == /dev/dri/card0
  and video_source == board-generated-textured-motion and
  fbdev_live_write_used == 0 and drm_dumb_buffers == 2 and
  drm_page_flip_calls == 120 and drm_vblank_flip_events == 120 and
  generated_frames == 120 and motion_content_type == textured-motion and
  captured_motion_frames >= 120 and tearing_frames == 0 and
  frame_duration_stddev_ms <= 4.0 and validator_status == pass),
  measured=(display_backend=drm-kms, drm_device=/dev/dri/card0,
  video_source=board-generated-textured-motion, fbdev_live_write_used=0,
  drm_dumb_buffers=2, drm_page_flip_calls=120,
  drm_vblank_flip_events=120, generated_frames=120,
  motion_content_type=textured-motion, captured_motion_frames=255,
  tearing_frames=0, frame_duration_stddev_ms=1.514,
  validator_status=pass).
Evidence: docs/reports/drm-kms-local-motion-pacing.md
Board action: deployed and ran the Linux DRM/KMS local-motion binary from
  /tmp, generated textured motion on the board, page-flipped /dev/dri/card0
  dumb buffers, captured HDMI through UVC, and used UART shell control. No
  Vivado/PetaLinux/JTAG/TF-card/flash write.

Cycle ID: drm-kms-vblank-motion-tearing
Result: FAILED. Implemented a Linux userspace DRM/KMS receiver using
  /dev/dri/card0, two dumb buffers, and legacy page-flip events. The connected
  board run proved the functional Linux network-to-DRM-to-HDMI path:
  60 textured-motion frames sent, 60 receiver writes, dropped=0,
  drm_dumb_buffers=2, drm_page_flip_calls=60, drm_vblank_flip_events=60,
  captured_motion_frames=120, tearing_validator_calibrated=1, tearing_frames=0,
  and validator_status=pass. The cycle still failed its frozen smoothness gate:
  pass_condition=(display_backend == drm-kms and drm_device == /dev/dri/card0
  and fbdev_live_write_used == 0 and drm_dumb_buffers == 2 and
  drm_page_flip_calls == 60 and drm_vblank_flip_events == 60 and
  sent_frames == 60 and receiver_written_frames == 60 and
  receiver_dropped_packets == 0 and motion_content_type == textured-motion
  and captured_motion_frames >= 60 and tearing_validator_calibrated == 1 and
  tearing_frames == 0 and frame_duration_stddev_ms <= 4.0 and
  validator_status == pass),
  measured=(display_backend=drm-kms, drm_device=/dev/dri/card0,
  fbdev_live_write_used=0, drm_dumb_buffers=2, drm_page_flip_calls=60,
  drm_vblank_flip_events=60, sent_frames=60, receiver_written_frames=60,
  receiver_dropped_packets=0, motion_content_type=textured-motion,
  captured_motion_frames=120, tearing_validator_calibrated=1,
  tearing_frames=0, frame_duration_stddev_ms=19.614,
  validator_status=pass).
Evidence: docs/reports/drm-kms-vblank-motion-tearing.md
Board action: deployed and ran the Linux DRM/KMS receiver from /tmp, sent PC
  UDP textured-motion payloads over Ethernet, page-flipped /dev/dri/card0
  dumb buffers, captured HDMI through UVC, and used UART shell control. No
  Vivado/PetaLinux/JTAG/TF-card/flash write.

Cycle ID: linux-net-to-hdmi-direct-copy
Result: PASSED. Implemented and verified the review-recommended Tier 1 Linux
  path: PC sender emits framebuffer-native 24bpp payloads, the Linux receiver
  starts with `FB_COPY_MODE mode=direct-memcpy`, writes complete UDP frames to
  /dev/fb0 with direct row memcpy, and HDMI/UVC saved-image trace validation
  matches all 30 validation frames. No Vivado, PetaLinux, device-tree,
  bitstream, TF-card, or persistent board write was performed.
  pass_condition=(receiver_fb_copy_mode == direct-memcpy and
  sender_wire_format == fb24-native and sender_fps == 15 and sent_frames == 30
  and receiver_written_frames == 30 and receiver_dropped_packets == 0 and
  receiver_effect == none and trace_require_image_paths == 1 and
  trace_image_path_failures == 0 and validator_status == pass and
  trace_sent_frames == 30 and trace_matched_frames >= 29 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0 and
  trace_max_latency_ms <= 1000),
  measured=(receiver_fb_copy_mode=direct-memcpy,
  sender_wire_format=fb24-native, sender_fps=15, sent_frames=30,
  receiver_written_frames=30, receiver_dropped_packets=0,
  receiver_effect=none, mjpeg_saved_frames=520, mjpeg_unique_hashes=42,
  mjpeg_unique_colors=8, trace_require_image_paths=1,
  trace_image_path_failures=0, validator_status=pass, trace_sent_frames=30,
  trace_matched_frames=30, trace_drop_rate=0.0, trace_order_violations=0,
  trace_content_mismatches=0, trace_black_frames=0,
  trace_mean_latency_ms=27.038, trace_max_latency_ms=62.382).
Evidence: docs/reports/linux-net-to-hdmi-direct-copy.md
Board action: deployed and ran the Linux receiver from /tmp, sent PC UDP
  fb24-native payloads over Ethernet, wrote /dev/fb0, captured HDMI through
  UVC, and used UART shell control. No Vivado/PetaLinux/JTAG/TF-card/flash
  write.

Cycle ID: dashboard-truthful-sent-received-timelines
Result: FAILED, frozen at user request. The Dashboard left preview now reports
  `latest-actual-sent-frame` instead of pairing to the HDMI frame ID, and the
  connected-board trace matched 90/90 returned HDMI frames with drop_rate=0.0.
  However the frozen pass condition required actual sender cadence between
  9.5 and 10.5 fps, and the run measured only 8.047 fps. The cycle therefore
  cannot be marked passed or rescued by changing the threshold after the run.
  pass_condition=(preview_source == latest-actual-sent-frame and
  configured_sender_fps == 10 and 9.5 <= sender_measured_fps <= 10.5 and
  receiver_present_fps == 10 and hdmi_delivery_fps == 10 and
  content_dwell_seconds == 5 and timeline_samples >= 20 and
  negative_lag_samples == 0 and positive_lag_samples >= 1 and
  distinct_sent_ids >= 3 and distinct_hdmi_ids >= 3 and max_lag_frames <= 30
  and sent_frames == 90 and receiver_written_frames == 90 and
  receiver_dropped_packets == 0 and validator_status == pass and
  trace_matched_frames >= 86 and trace_drop_rate <= 0.05 and
  trace_order_violations == 0 and trace_content_mismatches == 0 and
  trace_black_frames == 0 and trace_image_path_failures == 0 and
  trace_max_latency_ms <= 1000),
  measured=(preview_source=latest-actual-sent-frame,
  configured_sender_fps=10, sender_measured_fps=8.047,
  receiver_present_fps=10, hdmi_delivery_fps=10,
  content_dwell_seconds=5, timeline_samples=20, negative_lag_samples=0,
  positive_lag_samples=3, distinct_sent_ids=4, distinct_hdmi_ids=4,
  max_lag_frames=2, sent_frames=90, receiver_written_frames=90,
  receiver_dropped_packets=0, validator_status=pass,
  trace_matched_frames=90, trace_drop_rate=0.0, trace_order_violations=0,
  trace_content_mismatches=0, trace_black_frames=0,
  trace_image_path_failures=0, trace_max_latency_ms=135.028).
Evidence: docs/reports/dashboard-truthful-sent-received-timelines.md
Board action: deployed and ran the Linux receiver from /tmp, sent Dashboard-
  owned UDP RGB888, captured HDMI through UVC, and used UART shell control. No
  Vivado/PetaLinux/JTAG/TF-card/flash write.

Cycle ID: dashboard-unified-15fps-paired-preview
Result: FAILED. Dashboard start-stream launched the unified sender and the
  transport validator reached 90/90 matches with board dropped=0, but the
  implementation made the left panel follow the HDMI-decoded frame_id. The user
  rejected that semantic because it hides natural latency instead of showing
  the independently sent and received timelines. A supplemental measurement
  also found configured sender_fps=15 produced only 12.011 actual fps.
  pass_condition=(dashboard_sender_kind == unified and sender_fps == 15 and
  receiver_present_fps == 15 and hdmi_sample_fps == 15 and
  content_dwell_seconds == 5 and paired_preview_samples >= 20 and
  paired_preview_id_mismatches == 0 and sent_frames == 90 and
  receiver_written_frames == 90 and receiver_dropped_packets == 0 and
  validator_status == pass and trace_matched_frames >= 86 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0 and
  trace_image_path_failures == 0 and trace_max_latency_ms <= 1000),
  measured=(dashboard_sender_kind=unified, configured_sender_fps=15,
  sender_measured_fps=12.011,
  receiver_present_fps=15, hdmi_sample_fps=15, content_dwell_seconds=5,
  paired_preview_samples=20, paired_preview_id_mismatches=0, sent_frames=90,
  receiver_written_frames=90, receiver_dropped_packets=0,
  validator_status=pass, trace_matched_frames=90, trace_drop_rate=0.0,
  trace_order_violations=0, trace_content_mismatches=0,
  trace_black_frames=0, trace_image_path_failures=0,
  trace_max_latency_ms=141.088, user_acceptance=failed-paired-preview-rejected).
Evidence: docs/reports/dashboard-unified-15fps-paired-preview.md
Board action: deployed and ran the Linux receiver from /tmp, sent Dashboard-
  owned UDP RGB888, captured HDMI through UVC, and used UART shell control. No
  Vivado/PetaLinux/JTAG/TF-card/flash write.

Cycle ID: verification-standard-governance-fix
Result: PASSED. Closed the Rule 1 auditability gap exposed by the
  post-governance audit: the frozen pass_condition must now be committed in a
  cycle-open commit before verification runs, with a structural-presence
  exception for docs/governance cycles. Git management was reconciled to
  require two commits (open + close) for implementation cycles with a tunable
  pass_condition. The boundary-fix report's inaccurate "opened before
  implementation" claim was corrected. Third-party review sections with
  independently re-run validator evidence were appended to the boundary-fix
  and 15fps reports.
  pass_condition=(check1_open_commit_subrule_in_agents == present and
  check2_two_commit_in_git_mgmt == present and check3_template_crossref ==
  present and check4_false_assertion_gone == 0 and
  check4_correction_present == 1 and check5_boundaryfix_review == present and
  check6_15fps_review == present),
  measured=(check1_open_commit_subrule_in_agents=present(grep=2),
  check2_two_commit_in_git_mgmt=present(grep=1),
  check3_template_crossref=present(grep=4), check4_false_assertion_gone=0,
  check4_correction_present=1, check5_boundaryfix_review=present(grep=1),
  check6_15fps_review=present(grep=1)).
Evidence: docs/reports/unified-validator-boundary-order-fix.md (corrected
  residual risk + Third-party review),
  docs/reports/unified-15fps-image-evidence-pass-through.md (Third-party
  review), AGENTS.md, docs/current-cycle.md.
Board action: none; docs/governance cycle only. Independent validator re-runs
  were PC-side and touched no board hardware.

Cycle ID: unified-15fps-image-evidence-pass-through
Result: PASSED. The board-live loop now passes the unified validator with
  saved HDMI image evidence. PC sent 30 unique 15 fps validation frames with
  image-decodable markers; the Linux receiver wrote all 30 validation frame
  IDs with dropped=0; the HDMI MJPEG probe saved 220 frames with 47 unique
  hashes and 8 decoded colors; the trace builder decoded all 30 validation
  frame IDs from saved JPEGs with require_image_paths=true; the committed
  validator reported matched_frames=30, drop_rate=0.0, order_violations=0,
  content_mismatches=0, black_frames=0, image_path_failures=0, and max
  return-path latency=257.561 ms under the recorded 1000 ms HDMI-UVC/MJPEG
  trace requirement.
  pass_condition=(sender_fps == 15 and sent_frames == 30 and
  receiver_written_frames == 30 and receiver_dropped_packets == 0 and
  mjpeg_saved_frames >= 60 and mjpeg_unique_hashes >= 8 and
  mjpeg_unique_colors >= 8 and trace_require_image_paths == 1 and
  trace_image_path_failures == 0 and validator_status == pass and
  trace_sent_frames == 30 and trace_matched_frames >= 29 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0),
  measured=(sender_fps=15, sent_frames=30, receiver_written_frames=30,
  receiver_dropped_packets=0, mjpeg_saved_frames=220,
  mjpeg_unique_hashes=47, mjpeg_unique_colors=8,
  trace_require_image_paths=1, trace_image_path_failures=0,
  validator_status=pass, trace_sent_frames=30, trace_matched_frames=30,
  trace_drop_rate=0.0, trace_order_violations=0,
  trace_content_mismatches=0, trace_black_frames=0).
Evidence: docs/reports/unified-15fps-image-evidence-pass-through.md
Board action: ran a Linux userspace receiver from /tmp, sent generated UDP
  RGB888 frames from the PC over Ethernet, captured HDMI through the PC UVC
  adapter, and used UART only for Linux shell control. No Vivado build,
  PetaLinux build, JTAG programming, TF-card write, QSPI, NAND, eMMC, or other
  board flash write.

Cycle ID: unified-validator-boundary-order-fix
Result: PASSED. Fixed the two third-party-reviewed validator edge defects:
  exact 19/20 boundary handling now reports drop_rate=0.05 and passes the
  95% threshold, and an unmatched high frame_id capture no longer creates a
  spurious frame_order_violation before a later legitimate frame. Real
  wrong-order traces still fail with frame_order_violation.
  pass_condition=(calibration_status == pass and boundary_19_of_20_status ==
  pass and boundary_19_of_20_drop_rate == 0.05 and
  unmatched_high_then_lower_status == fail and
  unmatched_high_then_lower_has_unmatched_capture == 1 and
  unmatched_high_then_lower_has_frame_order_violation == 0 and
  wrong_order_status == fail and wrong_order_has_frame_order_violation == 1),
  measured=(calibration_status=pass, boundary_19_of_20_status=pass,
  boundary_19_of_20_drop_rate=0.05,
  unmatched_high_then_lower_status=fail,
  unmatched_high_then_lower_has_unmatched_capture=1,
  unmatched_high_then_lower_has_frame_order_violation=0,
  wrong_order_status=fail, wrong_order_has_frame_order_violation=1).
Evidence: docs/reports/unified-validator-boundary-order-fix.md
Board action: none. PC-side validator defect-fix cycle only; no Vivado,
  PetaLinux, JTAG, TF-card, UART, Ethernet, HDMI, or board flash action.

Cycle ID: unified-passthrough-validator-calibration
Result: PASSED. Added and calibrated the reusable temporal pass-through
  validator. pass_condition=(known_good_pass == 1 and known_bad_black_fail ==
  1 and known_bad_wrong_order_fail == 1 and known_bad_missing_frame_fail == 1
  and known_bad_wrong_content_fail == 1 and known_bad_latency_fail == 1),
  measured=(known_good_pass=1, known_bad_black_fail=1,
  known_bad_wrong_order_fail=1, known_bad_missing_frame_fail=1,
  known_bad_wrong_content_fail=1, known_bad_latency_fail=1).
Evidence: docs/reports/unified-passthrough-validator-calibration.md
Board action: none. PC-side validator/calibration cycle only; no Vivado,
  PetaLinux, JTAG, TF-card, UART, Ethernet, HDMI, or board flash action.

Cycle ID: verification-standard-governance
Result: PASSED. Added three structural rules to AGENTS.md (pass-condition
  preregistration/freeze, validator same-cycle prohibition, cycle-log
  threshold+measured) and updated the Cycle Template and cycle-log Entry
  Template to match. pass_condition=(three named rules present; template
  fields present), measured=(grep audit 0 missing).
Evidence: docs/cycle-log.md (2026-07-01 verification-standard-governance)
Board action: none; docs-only governance cycle.

Cycle ID: dashboard-color-block-loop-and-uart-audit
Result: PASSED. Replaced the ambiguous generated demo with full-screen
  sequential color blocks, classified the live HDMI MJPEG return stream as the
  source color set, fixed the Linux console cursor overlay, and made Dashboard
  UART pause/resume/status actions return real receiver markers. The finite
  board loop sent 12 color-block frames, the receiver wrote 12 frames with
  packets=14400 and dropped=0, and the MJPEG probe read 80 returned frames with
  8 unique colors.
Evidence: docs/reports/dashboard-color-block-loop-and-uart-audit.md
Board action: ran Linux userspace receivers from /tmp, sent generated UDP
  frames from the PC, streamed HDMI through the PC capture adapter, and sent
  UART shell commands to /tmp/video_ctl. No Vivado/PetaLinux/JTAG/TF-card/flash
  action.

Cycle ID: dashboard-live-pass-through-preview
Result: PASSED. Added a live HDMI MJPEG return endpoint for the dashboard right
  panel and changed the board-live helper to validate that same stream. The
  connected board wrote 12 no-effect generated frames, 14400 packets, dropped=0;
  the MJPEG probe read 80 returned HDMI frames from /api/output-stream.mjpeg
  with 26 unique hashes.
Evidence: docs/reports/dashboard-live-pass-through-preview.md
Board action: ran a Linux userspace receiver from /tmp, sent generated UDP
  frames from the PC through Dashboard, and streamed HDMI through the PC
  capture adapter. No Vivado/PetaLinux/JTAG/TF-card/flash action.

Cycle ID: dashboard-truthful-loop-validation
Result: PASSED. Corrected the dashboard closed-loop demo so the input preview
  is generated from the exact sender source, start-stream schedules HDMI
  capture asynchronously instead of blocking the button response, and the
  board-live helper requires dynamic HDMI sample hashes. The connected board
  wrote 12 generated frames, 14400 UDP packets, dropped=0; HDMI capture on
  DirectShow index 1 passed non-black validation and saved six samples with
  five unique hashes.
Evidence: docs/reports/dashboard-truthful-loop-validation.md
Board action: ran a Linux userspace receiver from /tmp, sent generated UDP
  frames from the PC through Dashboard, and captured HDMI. No Vivado/PetaLinux/
  JTAG/TF-card/flash action.

Cycle ID: dashboard-board-live-loop
Result: PASSED. Added a displayable board-live loop helper. It builds/deploys
  the Linux receiver to /tmp, starts it with /tmp/video_ctl, starts the
  dashboard, triggers Dashboard `start-stream`, sends five generated RGB888
  frames, verifies five VIDEO_UDP_FRAME_WRITTEN markers and
  VIDEO_UDP_RECEIVER_DONE frames=5 packets=6000 dropped=0, and validates HDMI
  capture with non-black mean_luma=136.39. The captured image shows the
  generated demo frame.
Evidence: docs/reports/dashboard-board-live-loop.md
Board action: ran a Linux userspace receiver from /tmp, sent UDP frames from
  the PC through Dashboard, and captured HDMI. No Vivado/PetaLinux/JTAG/flash
  action.

Cycle ID: dashboard-hdmi-capture-timeout-fix
Result: PASSED. Real dashboard `start-stream` initially hit
  HDMI_CAPTURE_TIMEOUT because the dashboard timeout was shorter than the
  DirectShow capture latency. The timeout is now at least 90 seconds and the
  default preview capture frame count is 8. Retest returned HDMI_CAPTURE_OK,
  capture_status=ok, and image_exists=true.
Evidence: docs/reports/dashboard-hdmi-capture-timeout-fix.md
Board action: PC-side dashboard process and HDMI capture only. No
  Vivado/PetaLinux/JTAG/flash action.

Cycle ID: dashboard-hdmi-capture-binding
Result: PASSED. Added HDMI preview capture binding to the dashboard. The
  capture tool now supports validation-profile none for preview captures.
  `start-stream` launches the sender and then attempts HDMI capture;
  `capture-output` refreshes HDMI manually. Live capture opened DirectShow
  device index 0 and wrote latest.png, but the frame was near black
  (mean_luma=0.05), so meaningful board output still depends on receiver
  readiness.
Evidence: docs/reports/dashboard-hdmi-capture-binding.md
Board action: PC-side HDMI capture only. No Vivado/PetaLinux/JTAG/flash action.

Cycle ID: dashboard-live-minimal-controls
Result: PASSED. The dashboard UI is now a plain functional view with no
  decorative background, gradients, shadows, or card styling. Start stream
  launches a real dashboard-owned demo sender subprocess; Stop stream
  terminates it. Self-test received a real localhost ZVID UDP packet from the
  sender and verified UART actions return UART_NOT_CONFIGURED when no UART port
  is provided.
Evidence: docs/reports/dashboard-live-minimal-controls.md
Board action: none. UART live binding was implemented but not exercised against
  the connected board in this automated cycle.

Cycle ID: dashboard-control-integration
Result: PASSED. The PC dashboard now exposes `/api/actions` and `/api/action`
  plus active control buttons. Self-test posted six dry-run actions covering
  sender start/stop, UART/FIFO pause/resume/status semantics, and effect launch
  semantics. Final state recorded stream_state=stopped, receiver_paused=false,
  selected_effect=invert, and no camera/custom-file input.
Evidence: docs/reports/dashboard-control-integration.md
Board action: none. PC-side dry-run dashboard action surface only.

Cycle ID: fixed-demo-video-sender
Result: PASSED. Added a fixed built-in deterministic RGB888 dynamic video
  source and UDP sender for the dashboard MVP. Self-test proved generated frame
  size, dynamic frame difference, localhost UDP packetization, 30/30 received
  packets, full payload byte count, and stable frame id. Parser inspection
  confirmed there is no camera/webcam/file input option. The result explicitly
  keeps camera/webcam input disabled and custom-file input deferred after MVP.
Evidence: docs/reports/fixed-demo-video-sender.md
Board action: none. PC-side fixed demo-video sender only.

Cycle ID: visual-dashboard-scaffold
Result: PASSED. Added a Python-stdlib PC dashboard scaffold with three visual
  regions: generated input preview, FPGA HDMI-output preview slot, and
  function-control/log panel skeleton. Self-test fetched the HTML, state JSON,
  generated input SVG, and output placeholder SVG. The state explicitly reports
  camera_enabled=false and custom_file_enabled=false.
Evidence: docs/reports/visual-dashboard-scaffold.md
Board action: none. PC dashboard scaffold only.

Cycle ID: first-board-side-effect
Result: PASSED. The Linux receiver now supports a board-side RGB invert effect.
  PC sent the deterministic non-camera rgb-stripes UDP frame; board logs showed
  VIDEO_UDP_FRAME_WRITTEN frame_id=200 effect=invert and
  VIDEO_UDP_RECEIVER_DONE frames=1 packets=1200 dropped=0. HDMI capture using
  the inverted-rgb-stripes profile returned HDMI_CAPTURE_OK.
Evidence: docs/reports/first-board-side-effect.md
Board action: ran a userspace binary from /tmp, sent one generated UDP frame
  from the PC, and captured HDMI for output verification. No camera/webcam
  video input, no Vivado rebuild, no PetaLinux rebuild, no JTAG programming,
  and no board flash writes.

Cycle ID: uart-control-endpoint
Result: PASSED. The Linux receiver now supports a FIFO control endpoint that
  can be driven from the UART shell. UART `pause` caused a complete UDP frame
  to log VIDEO_UDP_FRAME_SKIPPED_PAUSED instead of writing /dev/fb0; UART
  `resume` and `status` were accepted, the next UDP frame was written, and HDMI
  capture returned HDMI_CAPTURE_OK.
Evidence: docs/reports/uart-control-endpoint.md
Board action: ran a userspace binary from /tmp, wrote control commands through
  the UART shell to /tmp/video_ctl, sent UDP frames from the PC, and captured
  HDMI. No Vivado rebuild, no PetaLinux rebuild, no JTAG programming, and no
  board flash writes.

Cycle ID: sustained-low-fps-stream
Result: PASSED. The Linux UDP receiver handled a five-frame 800x600 RGB888
  low-FPS stream. PC sent 6000 UDP packets; board logs showed five
  VIDEO_UDP_FRAME_WRITTEN markers and VIDEO_UDP_RECEIVER_DONE frames=5
  packets=6000 dropped=0. HDMI capture after the stream returned
  HDMI_CAPTURE_OK.
Evidence: docs/reports/sustained-low-fps-stream.md
Board action: ran a userspace binary from /tmp after downloading it through a
  one-shot Ethernet file server, sent UDP frames from the PC, and captured
  HDMI. No Vivado rebuild, no PetaLinux rebuild, no JTAG programming, and no
  board flash writes.

Cycle ID: ethernet-video-userspace-receiver
Result: PASSED. A Linux userspace ARM receiver now accepts the project UDP
  RGB888 frame protocol on port 5005, assembles a complete 800x600 frame,
  maps protocol RGB into the actual /dev/fb0 channel byte order, and writes the
  frame to the proven VDMA/DRM HDMI framebuffer. PC sent one rgb-stripes frame
  as 1200 UDP packets; board log showed packets=1200 dropped=0 and HDMI
  capture validation returned HDMI_CAPTURE_OK.
Evidence: docs/reports/ethernet-video-userspace-receiver.md
Board action: ran a userspace binary from /tmp after downloading it over
  Ethernet, sent UDP from the PC, and captured HDMI. No Vivado rebuild, no
  PetaLinux rebuild, no JTAG programming, and no QSPI, NAND, eMMC, or other
  board flash writes.

Cycle ID: hdmi-linux-fixed-mode-connector
Result: PASSED. Linux now exposes a connected fixed-mode HDMI connector,
  /dev/dri/card0, and /dev/fb0. The VDMA DMA-decode failure was traced to a
  Linux CMA allocation outside the official VDMA DDR window documented in
  docs/boards/hellofpga-smart-zynq-sl.md; moving CMA inside that window removed
  VDMA errors and flip timeouts. A userspace /dev/fb0 write changed HDMI from
  the Linux login console to a deterministic three-stripe image, and automated
  HDMI capture validation passed.
Evidence: docs/reports/hdmi-linux-fixed-mode-connector.md
Board action: replaced image.ub on the TF-card FAT boot partition via board
  Linux wget over Ethernet, retained backups, rebooted from TF card, wrote a
  test frame through /dev/fb0, and captured HDMI. No JTAG programming, QSPI,
  NAND, eMMC, or other board nonvolatile storage writes.

Cycle ID: hdmi-linux-display-stack
Result: PARTIAL. The project image now enables Xilinx PL display DRM
  (CONFIG_DRM_XLNX=y, CONFIG_DRM_XLNX_PL_DISP=y), boots from the TF card, and
  exposes /dev/dri/card0. HDMI capture still sees stable 800x600 color bars.
  The image is not yet Linux-controllable because DRM has no connector/mode
  provider: /dev/fb* is absent, /sys/class/drm/card0 has no status/modes/enabled
  files, and dmesg says "[drm] Cannot find any crtc or sizes".
Evidence: docs/reports/hdmi-linux-display-stack.md
Board action: replaced image.ub on the TF-card FAT boot partition via board
  Linux wget over Ethernet, backed up the old image.ub on the same partition,
  rebooted from TF card, and captured UART/HDMI evidence. No JTAG programming,
  QSPI, NAND, eMMC, or other nonvolatile board storage writes.

Cycle ID: petalinux-vdma-hdmi-minimal-project
Result: PASSED. The VDMA HDMI hardware description was made Linux-consumable by
  connecting VDMA MM2S/S2MM interrupts to PS IRQ_F2P. PetaLinux 2018.3 built
  image.ub in the Ubuntu 18.04 chroot, packaged BOOT.BIN, and copied BOOT.BIN +
  image.ub to the ZYNQBOOT TF-card partition with matching SHA256 hashes.
Evidence: docs/reports/petalinux-vdma-hdmi-minimal-project.md
Board action: TF-card file write only; no board boot or nonvolatile flash write.

Cycle ID: vdma-boot-probe-verify
Result: PASSED. The project-built TF-card image boots to Linux userspace,
  accepts root/root over UART, eth0 links at 1000/Full and pings from the PC
  with 0% loss, and the VDMA node binds to the xilinx-vdma platform driver.
  No /dev/dri or /dev/fb* node appears, so HDMI/display output remains a
  separate device-tree/display-stack follow-up.
Evidence: docs/reports/vdma-boot-probe-verify.md
Board action: booted generated image from TF card only; no JTAG programming,
  QSPI, NAND, eMMC, or other nonvolatile board storage writes.
```

## Resolved Route Gate

The TF-card Linux ping route gate PASSED on 2026-06-29.

```text
Cycle ID: eth-ps-pl-hdmi-pass-through (route-gate phase)
Result: PASSED. Official Linux boots from TF card, eth0 link up at 1000/Full,
  PC ping 192.168.1.10 = 4/4 received, 0% loss.
Evidence: docs/reports/tf-card-linux-ping-2026-06-29.md
Decision: Outcome A - proceed on Linux/socket route, retire hand-written
  baremetal RGMII bridge.
```

## Current Decision

The active implementation route is now confirmed by hardware evidence:

```text
PC UDP RGB888 frame -> Linux userspace socket receiver -> DDR framebuffer
-> VDMA MM2S -> v_axi4s_vid_out -> rgb2dvi -> HDMI
```

The hand-written baremetal RGMII bridge + lwIP route is retired. It was
verified as a dead end: the same physical path that fails under the hand-written
bridge works perfectly under Linux + official macb driver (RX errors=0, ping
0% loss). The bridge code remains in the repo as negative evidence only.

## Current Evidence

Known-good subchains:

```text
Official VDMA HDMI image passed on connected board and PC HDMI capture.
Official pure-PL UDP loopback passed over the same PC/RJ45/RTL8211E path.
Official Linux boots from TF card, eth0 1000/Full, RX errors=0, ping 0% loss.
PetaLinux 2018.3 host tooling is installed and command-visible in WSL.
Project baremetal board-to-PC UDP heartbeat works (but PC-to-board RX does not).
Project Linux exposes a connected DRM HDMI output and /dev/fb0.
Linux userspace framebuffer writes pass automated HDMI capture validation.
Project Linux userspace UDP receiver receives a complete 800x600 RGB888 frame
and updates the physical HDMI output through /dev/fb0.
Project Linux userspace UDP receiver handles a five-frame low-FPS stream with
6000 UDP packets, dropped=0, and HDMI capture validation after the stream.
Project Linux receiver accepts UART-shell-driven pause/resume/status commands
through a FIFO control endpoint without breaking UDP receive or HDMI output.
Project Linux receiver applies a board-side RGB invert effect to generated PC
UDP input and HDMI capture validates the inverted output.
PC dashboard scaffold exposes generated input preview, FPGA HDMI return
preview, and function-control/log panel regions without camera or custom-file
input.
PC fixed demo sender generates deterministic dynamic RGB888 frames and
packetizes them through the existing UDP protocol without camera or custom-file
input.
PC dashboard control API exposes tested dry-run sender, UART/FIFO, and effect
actions without camera or custom-file input.
PC dashboard is now minimal and `start-stream`/`stop-stream` control a real
local demo sender subprocess. UART/FIFO controls are wired to the UART helper
but require a ready board receiver FIFO.
PC dashboard `start-stream` starts the real demo sender and exposes the live
HDMI return endpoint. `capture-output` remains a manual still-capture fallback.
Dashboard board-live loop now deploys/starts the receiver, drives Dashboard
`start-stream`, receives/writes twelve generated no-effect frames with
dropped=0, and validates the right-panel `/api/output-stream.mjpeg` HDMI return
stream with 80 returned frames and 26 unique hashes.
Dashboard color-block loop now uses full-screen sequential color blocks as the
PC source and validates the live HDMI return stream by classifying returned
MJPEG frames as the source colors.
Dashboard UART pause/resume/status actions now return real receiver markers
from the running board receiver through `/tmp/video_ctl`.
Unified pass-through trace validator is calibrated against synthetic good/bad
cases and is the preferred evidence check for future faithful live pass-through
claims.
Unified pass-through validator boundary/order edge cases are fixed: exact
19/20 matching passes at drop_rate=0.05, unmatched captures fail without
spurious frame_order_violation, and real wrong-order traces still fail.
Unified 15 fps image-evidence pass-through is closed: 30 generated validation
frames with image-decodable markers were received, presented to HDMI, captured
as saved JPEGs, decoded into a trace with `require_image_paths=true`, and
accepted by the committed validator with matched_frames=30 and drop_rate=0.0.
Linux direct-copy network-to-HDMI path is closed: PC sends framebuffer-native
24bpp payloads, the Linux receiver writes complete UDP frames to /dev/fb0 with
direct row memcpy, HDMI saved-image trace validation matches 30/30 frames, and
receiver dropped=0.
DRM/KMS local textured-motion display pacing is closed: the board generates
120 textured frames locally, writes only DRM dumb back buffers, receives 120
vblank page-flip events on /dev/dri/card0, HDMI capture validates 255
motion-like frames, tearing_frames=0, and frame_duration_stddev_ms=1.514.
PetaLinux GStreamer rootfs integration is closed: the generated image boots on
the connected board with GStreamer 1.12.2, gst-launch/gst-inspect, base/good/
bad plugins, kmssink, DRM/KMS tools, and V4L utilities available; fakesink
pipeline smoke passes and kmssink negotiates 800x600 KMS caps. The final RTP
raw-video-to-kmssink route is not yet closed.
The earlier RTP/raw-to-kmssink result is withdrawn: visual inspection exposed
black/white cross-frame slicing that the motion-only validator accepted.
The corrected dashboard route is closed with actual source preview,
JPEG/RTP over Ethernet, board rtpjpegdepay/jpegdec, and fbdevsink output.
Twelve HDMI samples produced 11 unique hashes, detected the yellow ball in all
frames, and preserved the blue background.
Cycle governance is simplified: cycle records are now audit packages and
third-party review inlets, not preregistered pass-gate procedures. Current
rules live in AGENTS.md.
Third-party review with independently re-run validator evidence appended to the
boundary-fix and 15fps reports; one saved HDMI JPEG was independently
marker-decoded and matched the trace's claimed frame_id.
```

Retired dead end:

```text
Project baremetal PC-to-board UDP RX through the hand-written RGMII bridge:
rx=0, rxfcs rising, no frames reach lwIP. Root cause confirmed by the Linux
ping result as the hand-written bridge BUFIO/BUFG crossing, not the physical
layer. Do not resume this work.
```

## Next Work Direction

No active work note is open. The next implementation step can build on four
verified facts: the Linux direct-copy network-to-HDMI transfer chain passes,
the board display side can page-flip textured motion through DRM/KMS with
stable vblank cadence when network receive is removed, the board boots a
PetaLinux rootfs with GStreamer tools/plugins, and the PC-to-board GStreamer
JPEG/RTP-to-fbdevsink route passes color-aware dynamic HDMI return validation.
The next route should add frame/drop accounting or begin the requested video
effects on this known-good transport and display base.
