# Native 720p Display v2 v12 Closed Loop

Date: 2026-07-16

## Result

PASSED for the native display and visual-integrity boundary. The connected
XC7Z020 now boots a native display design in which the PC RTP/JPEG source is
decoded by `jpegpldec backend=pl-decoder`, presented through DRM/KMS and the
display VDMA, processed by the same-source PL PIP core, and returned over HDMI.
The output is dynamic, the large PIP contains the complete source frame, the
main/PIP frame counters remain locked, and the bidirectional HDMI tearing gate
found zero torn frames.

This result does not claim 30 distinct HDMI content frames per second. The PC
source and RTP caps request 30 fps, while a 189-frame board PTS sample measured
15.018 effective decoded/presented content fps. The synchronous 65 MHz PL
decode plus the blocking GStreamer 1.12 `kmssink` page-flip path is the
remaining performance boundary.

## Implemented Fixes

- Removed the obsolete second display VDMA and replaced it with one AXI-stream
  broadcaster. Main and PIP consumers now share the same source frame boundary.
- Corrected the JPEG AXI DMA interrupt after removing that VDMA. The DMA moved
  from concat input `In3` to `In2`, matching Linux GIC63. This removed the
  first-chunk wait that had appeared as a system hang.
- Corrected the PL JPEG output byte order to BGR and made `jpegpldec` expose the
  coherent output mmap directly while rejecting downstream allocation pools
  that exhausted the 32 MiB CMA reservation.
- Corrected PIP geometry. Write-side capture now samples the complete source
  at 1:4 into the 320x180 frame RAM. Read-side addressing independently selects
  the complete 320x180 large view or a 160x90 1:2 read of that RAM. The old
  implementation captured only the source's upper-left quadrant.
- Made dashboard `start-stream` establish and read back the large PIP preset,
  so the UI state, TCP control result, registers, and visible output agree.
- Changed DShow HDMI capture negotiation to request MJPG in the initial
  `VideoCapture` open parameters. The previous post-open format setter returned
  success but silently retained YUY2 at 1280x720@10.

## Build Evidence

- Full RTL simulation passed the framebuffer reader, PIP overlay, AXI-stream
  broadcaster, and JPEG DMA probe jobs with `SIM_FLOW_OK`.
- PIP OOC synthesis at the real 150 MHz clock passed with WNS `+0.579 ns` and
  zero DRC errors.
- The v12 full implementation passed with WNS `+0.207 ns`, WHS `+0.028 ns`,
  no failed or unrouted nets, and zero Error-severity DRC violations.
- Bitstream SHA-256:
  `a91a2126db77d5244287c5584cde0426a67257238816b218e77bbde98dbf22cf`.
- BOOT.BIN SHA-256:
  `ceb135b8148bec96ebc5334b99f0be4fcaf6b59160e59ac21ec958778d39c10e`.
- Reused image.ub SHA-256:
  `ec15fa4c8ea6728ec15c35be992acc0ad44b0d3264ed6cff058eef04dd9d990e`.

The preferred source-only rebuild is
`examples/eth-ps-pl-hdmi-pass-through/tcl/rebuild_stage1_vdma_board_incremental.tcl`.
Its generated marker is:

```text
STAGE1_VDMA_BOARD_INCREMENTAL_BUILD_OK ... wns=0.207 drc_errors=0
```

## Board Evidence

The TF-card update used a downloaded temporary image, SHA-256 verification,
backup, copy, sync, and post-copy verification before reboot. The rollback
image is `/run/media/mmcblk0p1/BOOT.BIN.prev-v11-424a9b80`, whose SHA-256 is
`424a9b8027e4d21987dc23e2c170f107264a8833d538c6267caf36a2547d73d1`.

After reboot:

- `/dev/dri/card0` and `/dev/fb0` existed;
- HDMI connector status was `connected` with mode `1280x720`;
- CMA was 32 MiB;
- Ethernet linked at 1000/Full with zero RX/TX errors and drops.

The fixed 1280x720 JPEG vector passed on v12:

```text
status=0x00000011
input_bytes=30054
output_bytes=2764800
pixels=921600
cycles=2558675
commands=57600
responses=57600
stalls=115200
errors=0x00000000
elapsed_ns=30569692
output_fnv=0xa567410c
```

The final long-running receiver snapshot recorded 7,890 successful PL decode
frames, zero failures, average 30.734 ms, plugin p95 31.398 ms, and maximum
32.441 ms in the progress counter. It retained 12,796 KiB free CMA and the
PC had exactly one GStreamer sender process.

## HDMI And PIP Evidence

- Ball capture: 90 frames, 90 unique hashes, ball detected in all 90, motion
  spans `x=314.685`, `y=326.277`.
- Large PIP validation: 87/87 post-warm-up frames passed complete-source
  geometry and border checks.
- Main/PIP counter validation: six samples, offset span 0 and maximum delta
  difference 0.
- Bidirectional tearing sequence: 600 paced RFC2435 frames sent; HDMI capture
  returned 90 unique frames; row motion 90, column motion 90, tearing 0.
- DShow capture after MJPG negotiation: median read interval improved from
  94 ms to 16 ms. The dashboard endpoint returned 260 complete JPEG parts in
  a 15-second probe including device-open time.

Primary raw evidence:

- `build/native-720p-display-v2/uart-v12-postboot.log`
- `build/native-720p-display-v2/uart-deploy-test-v12.log`
- `build/native-720p-display-v2/uart-v12-final-health.log`
- `build/native-720p-display-v2/uart-v12-final-pts.log`
- `build/native-720p-display-v2/hdmi-v12-ball-pip-large-90/`
- `build/native-720p-display-v2/pip-frame-sync-v12.json`
- `build/native-720p-display-v2/hdmi-v12-tearing-90-final/`
- `build/native-720p-display-v2/hdmi-v12-mjpg-90/`
- `build/720p-native-vdma-board-v12-incremental/reports/`

## Operational Finding

A stale second PC `gst-launch-1.0` sender used the same RTP destination during
the first v11 live test. Competing SSRC/PTS timelines made the board appear
static despite valid packets. Killing both stale senders and restarting one
dashboard-owned sender restored dynamic output. Final evidence therefore
requires exactly one PC sender process.

## Residual Risk And Next Boundary

The installed GStreamer 1.12 `kmssink` has no `skip-vsync` or asynchronous
page-flip property. The PL decoder consumes about 31 ms and the sink blocks the
same streaming thread for display submission, so the jitter buffer drops
roughly every other 30 fps source frame. The measured median PTS interval is
66.67 ms, or 15.018 effective content fps.

The next performance route is not another raw UDP or fbdev workaround. It is a
multi-buffer DMA-BUF/KMS path: obtain at least two downstream display buffers,
let the kernel import their DMA addresses, decode directly into the selected
back buffer, put a queue between decode and page-flip, and retain vblank-based
release. That work must preserve the zero-tearing and exact-output gates from
this cycle.

## Rollback

Restore `/run/media/mmcblk0p1/BOOT.BIN.prev-v11-424a9b80` as `BOOT.BIN`, sync,
and reboot. The v11 runtime files and v12 runtime files use the same plugin and
driver ABI.
