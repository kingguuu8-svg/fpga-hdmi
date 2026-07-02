# DRM/KMS Local Motion Pacing

Date: 2026-07-02

Result: PASSED.

## Objective

Isolate the board display side from full-frame UDP receive and verify that the
current Linux DRM/KMS output path can present textured motion through
double-buffered dumb buffers with vblank page-flip events, no fbdev live-screen
write, no visible tearing, and stable pacing.

This cycle does not claim that the PC UDP network input path is smooth under
the DRM/KMS receiver. It answers a narrower question from the previous failed
cycle: whether the display side itself can meet the smoothness and tearing gate
when packet receive and userspace frame assembly are removed.

## Changes

- `software/eth_pass_through/linux_app/src/drm_kms_udp_receiver.c`
  - Added `--local-motion`.
  - Added board-local generated textured-motion frames.
  - Added `--present-fps`, `--start-delay-sec`, and `--hold-sec`.
  - The local path writes only non-visible DRM dumb buffers and presents by
    `DRM_IOCTL_MODE_PAGE_FLIP` with flip-complete events.

- `tools/run_drm_kms_local_motion_pacing_probe.ps1`
  - Builds and deploys `/tmp/drm_kms_udp_receiver`.
  - Starts local textured motion on `/dev/dri/card0`.
  - Captures HDMI through the PC UVC adapter.
  - Runs the already-committed motion tearing validator.
  - Computes frame-duration stddev from DRM vblank event timestamps.

## Frozen Gate

```text
display_backend == drm-kms and drm_device == /dev/dri/card0
and video_source == board-generated-textured-motion and
fbdev_live_write_used == 0 and drm_dumb_buffers == 2 and
drm_page_flip_calls == 120 and drm_vblank_flip_events == 120 and
generated_frames == 120 and motion_content_type == textured-motion and
captured_motion_frames >= 120 and tearing_frames == 0 and
frame_duration_stddev_ms <= 4.0 and validator_status == pass.
```

Validator:

```text
already-committed tools/validate_motion_tearing.py calibrated in a prior
cycle, plus direct board-log checks for DRM/KMS markers, dumb-buffer count,
page-flip count, vblank-event count, generated frame count, and no fbdev live
write.
```

## Verification

Static and host checks:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
VIDEO_CONTROL_TEST_OK
VIDEO_EFFECT_TEST_OK
LINUX_RECEIVER_BUILD_OK
DRM_KMS_RECEIVER_BUILD_OK
POWERSHELL_PARSE_OK for tools/run_drm_kms_local_motion_pacing_probe.ps1
python -m py_compile tools/probe_hdmi_motion_capture.py tools/validate_motion_tearing.py
```

Connected-board command:

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_drm_kms_local_motion_pacing_probe.ps1
```

Final marker:

```text
DRM_KMS_LOCAL_MOTION_PACING_OK display_backend=drm-kms drm_device=/dev/dri/card0 video_source=board-generated-textured-motion fbdev_live_write_used=0 drm_dumb_buffers=2 drm_page_flip_calls=120 drm_vblank_flip_events=120 generated_frames=120 motion_content_type=textured-motion captured_motion_frames=255 tearing_frames=0 frame_duration_stddev_ms=1.514 validator_status=pass summary=E:\main\fpga-hdml\build\drm-kms-local-motion-pacing\drm-kms-local-motion-pacing-summary.json
```

Measured:

```text
display_backend=drm-kms
drm_device=/dev/dri/card0
video_source=board-generated-textured-motion
fbdev_live_write_used=0
drm_dumb_buffers=2
drm_page_flip_calls=120
drm_vblank_flip_events=120
generated_frames=120
motion_content_type=textured-motion
captured_motion_frames=255
tearing_frames=0
frame_duration_stddev_ms=1.514
validator_status=pass
```

## Board Evidence

DRM/KMS setup:

```text
DRM_OUTPUT connector=30 crtc=28 mode=800x600 refresh=60 name=800x600
DRM_DUMB_BUFFERS count=2 width=800 height=600 pitch0=2400 pitch1=2400 format=RGB888
VIDEO_DRM_LOCAL_MOTION_READY display_backend=drm-kms drm_device=/dev/dri/card0 video_source=board-generated-textured-motion frames=120 present_fps=30.000 fbdev_live_write_used=0 motion_content_type=textured-motion
```

Completion:

```text
VIDEO_DRM_LOCAL_MOTION_DONE display_backend=drm-kms drm_device=/dev/dri/card0 video_source=board-generated-textured-motion fbdev_live_write_used=0 generated_frames=120 motion_content_type=textured-motion drm_dumb_buffers=2 drm_page_flip_calls=120 drm_vblank_flip_events=120 hold_sec=10 elapsed_ms=13986
```

HDMI tearing validation:

```text
MOTION_TEARING_VALIDATION_OK captured_motion_frames=255 tearing_frames=0 validator_status=pass
```

## Evidence

- `build/drm-kms-local-motion-pacing/drm-kms-local-motion-pacing-summary.json`
- `build/drm-kms-local-motion-pacing/uart_deploy_start_local_motion.log`
- `build/drm-kms-local-motion-pacing/uart_after_local_motion.log`
- `build/drm-kms-local-motion-pacing/hdmi-motion-capture/mjpeg-stream-probe.json`
- `build/drm-kms-local-motion-pacing/motion-tearing-validation/motion-tearing-validation.json`

## Interpretation

The board display side can produce stable DRM/KMS vblank page-flipped textured
motion through `/dev/dri/card0` without using `/dev/fb0` live-screen mmap
writes. The previous `drm-kms-vblank-motion-tearing` failure is therefore not
explained by the HDMI scanout or DRM page-flip mechanism alone. The remaining
smooth-network-video work is in the network-driven receive/presentation path:
packet receive, frame assembly, buffering policy, or a higher-level Linux
pipeline such as GStreamer.

## Residual Risks

- This cycle uses board-generated textured motion, not PC UDP input. It proves
  the display side, not end-to-end network-driven smooth playback.
- The legacy page-flip API was used, not atomic commit. The required evidence
  is the received vblank flip event count and timestamp cadence.
- HDMI capture reported 255 motion-like frames out of 360 saved frames. The
  non-motion tail comes from the post-demo hold/black period and is outside the
  pass condition; the validator counted only motion-like frames.
