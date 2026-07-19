# Native 720p30 DMA-BUF Display v1 Closed Loop

Date: 2026-07-19

## Result

PASSED for the connected-board 1280x720 HDMI display-throughput boundary.
The PC 30 fps RTP/JPEG source was decoded by `jpegpldec backend=pl-decoder`,
written into a four-slot DRM DMA-BUF pool, submitted through the bounded
GStreamer queue to `kmssink`, and returned through the native HDMI path. The
60-second ball run produced measured HDMI content cadence of `29.975 fps`,
above the `29.5 fps` gate. HDMI motion was present throughout the capture and
the independent bidirectional stripe gate reported zero tearing.

This cycle claims 720p30 HDMI output, not 720p60 or 1080p performance. The
PL PIP topology remains in the HDMI path from the previously closed v12
cycle; this cycle's display gate focuses on the decoder-to-KMS buffering and
presentation boundary rather than re-running the PIP geometry checks.

## Implemented Scope

- `jpegpldec` uses `output-mode=drm-dmabuf` and the PL decoder backend; the
  software JPEG decoder was absent on the board.
- The plugin and probe driver use four DMA-BUF slots. The downstream queue is
  bounded to three buffers, and `kmssink` runs with `sync=false` and `qos=false`.
- The gate captures HDMI at 60 fps while the source is paced at 30 fps. This
  avoids sampling a 30 fps output at the same phase and confusing content
  cadence with capture cadence.
- The gate now removes stale PC `gst-launch-1.0` RTP senders before and after
  each run. The ball and stripe checks use separate board receiver sessions so
  a new RTP SSRC/timestamp session is not misclassified as a display failure.
- The selected run sets `dmabuf-device-sync=false`; the earlier comparison with
  device synchronization enabled added about 5.2 ms to the steady decode
  path and did not solve the long-run display freeze.

## Formal HDMI Evidence

The formal output directory is:

`build/native-720p30-dmabuf-display-v1/formal-60s-capture60-four-slot-clean-single-source-com15/`

Ball source and HDMI return:

```text
HDMI_BALL_MOTION_OK samples=3600 unique_hashes=3502
  frames_with_ball=3599 x_span=339.4 y_span=344.597
HDMI_CONTENT_CADENCE_OK capture_frames=3600
  distinct_content_frames=1866 effective_content_fps=29.975
```

The cadence report measured `1866` distinct content frames over
`62219 ms`; the gate required at least `1770` distinct frames and `29.5 fps`.

Independent stripe return and tearing check:

```text
validator_status=pass
mjpeg_frames=600 unique_content_hashes=559
row_motion_frames=600 column_motion_frames=600 tearing_frames=0
```

## Board Evidence

The ball receiver stop log records:

```text
JPEGPLDEC_DMABUF_POOL_READY slots=4 width=1280 height=720
JPEGPLDEC_PL_DECODE_PROGRESS frames=1800 failures=0 avg_ms=30.871
JPEGPLDEC_PROFILE frames=1800 backend=pl-decoder mode=software
  avg_ms=31.029 p50_ms=30.771 p95_ms=31.728 max_ms=165.047
KERNEL_HEALTH_OK
RX packets: ... errors:0 dropped:0
```

The independent stripe receiver also completed PL decode with zero failures;
its final progress reached `1560` frames, with `KERNEL_HEALTH_OK` and
`RX ... errors:0 dropped:0`. The board-side DMA-BUF pool was four slots in
both sessions.

The deployed runtime hashes were:

```text
libgstjpegpldec.so
8fb7182d81f93242a937b2f64c8dca75ee90b82105dd9d47ddc2c74f6fe5592e

jpegpl_dma_probe.ko
d540d9d45872e5830c40a4182430167ef8ca1d8181d2a5063f584f693b95b57f
```

The driver self-test passed with checksum `0x6bf6a41d`. No Vivado or boot
image change was required for this cycle; the board used the existing native
720p image and the runtime plugin/driver were deployed temporarily.

## Evidence Files

- `build/native-720p30-dmabuf-display-v1/formal-60s-capture60-four-slot-clean-single-source-com15/summary.json`
- `build/native-720p30-dmabuf-display-v1/formal-60s-capture60-four-slot-clean-single-source-com15/ball-motion-validation.json`
- `build/native-720p30-dmabuf-display-v1/formal-60s-capture60-four-slot-clean-single-source-com15/ball-content-cadence.json`
- `build/native-720p30-dmabuf-display-v1/formal-60s-capture60-four-slot-clean-single-source-com15/bidirectional-tearing-validation.json`
- `build/native-720p30-dmabuf-display-v1/formal-60s-capture60-four-slot-clean-single-source-com15/uart-ball-stop.log`
- `build/native-720p30-dmabuf-display-v1/formal-60s-capture60-four-slot-clean-single-source-com15/uart-stop.log`

## Residual Risk And Boundary

- The four-slot path is verified at 1280x720 and 30 fps only. It does not
  establish the maximum achievable rate or resolution.
- The stripe test uses a fresh receiver session. It proves the single-session
  HDMI buffer/presentation path is not tearing, but does not prove seamless
  RTP SSRC/timestamp handover inside one long-lived jitterbuffer.
- `dmabuf-device-sync=false` is part of the passing configuration. The
  synchronization ioctl path was measured but is not the selected throughput
  route.
- PIP geometry and main/PIP lockstep remain covered by
  `native-720p-display-v2-v12`; they were not independently re-measured in
  this cycle.

## Rollback

No boot image or Vivado source changed. Roll back this cycle by using the
previous runtime plugin/driver artifacts and the v12 board package documented
in `docs/reports/native-720p-display-v2-v12-closed-loop-2026-07-16.md`.
