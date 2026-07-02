# DRM/KMS Vblank Motion Tearing Cycle

Date: 2026-07-02

Cycle ID: `drm-kms-vblank-motion-tearing`

Result: FAILED.

## Objective

Replace the board display path used by the video receiver from fbdev live-screen
writes to DRM/KMS double-buffered page-flip, and verify human-visible motion
quality with textured motion content.

## Changed Scope

- Added `software/eth_pass_through/linux_app/src/drm_kms_udp_receiver.c`.
- Added the DRM receiver build target to
  `software/eth_pass_through/linux_app/build.sh`.
- Added `tools/send_motion_video_udp.py` for markerless textured-motion UDP
  frames.
- Added `tools/validate_motion_tearing.py`, calibrated in this cycle against
  synthetic no-tear and torn textured-motion frames.
- Added `tools/probe_hdmi_motion_capture.py` for markerless HDMI capture
  frames.
- Added `tools/run_drm_kms_vblank_motion_tearing_probe.ps1`.

## Verification

- `python -m py_compile` passed for the motion sender, HDMI capture probe, and
  tearing validator.
- PowerShell parser accepted
  `tools/run_drm_kms_vblank_motion_tearing_probe.ps1`.
- Linux receiver build and host tests printed `VIDEO_UDP_RECEIVER_TEST_OK`,
  `VIDEO_FB_COPY_TEST_OK`, `VIDEO_CONTROL_TEST_OK`,
  `VIDEO_EFFECT_TEST_OK`, `LINUX_RECEIVER_BUILD_OK`, and
  `DRM_KMS_RECEIVER_BUILD_OK`.
- Tearing validator calibration printed `MOTION_TEARING_CALIBRATION_OK` with
  `known_good_pass=1` and `known_bad_torn_fail=1`.
- Connected-board run reached DRM/KMS output:
  - `DRM_OUTPUT connector=30 crtc=28 mode=800x600 refresh=60`
  - `DRM_DUMB_BUFFERS count=2`
  - `VIDEO_UDP_DRM_RECEIVER_READY display_backend=drm-kms`
  - `DRM_PAGE_FLIP_SUBMITTED` count = 60
  - `DRM_PAGE_FLIP_EVENT` count = 60
  - `VIDEO_UDP_DRM_RECEIVER_DONE ... frames=60 packets=72000 dropped=0`
- HDMI motion capture and tearing validation printed
  `MOTION_TEARING_VALIDATION_OK captured_motion_frames=120 tearing_frames=0`.

## Board Action

Deployed and ran `/tmp/drm_kms_udp_receiver` from the UART shell, sent PC UDP
textured-motion frames over Ethernet, displayed through `/dev/dri/card0`
DRM/KMS dumb-buffer page flips, and captured HDMI through the PC UVC adapter.
No Vivado build, PetaLinux build, JTAG programming, TF-card write, or board
flash write was performed.

## Result

pass_condition=(display_backend == drm-kms and drm_device == /dev/dri/card0
and fbdev_live_write_used == 0 and drm_dumb_buffers == 2 and
drm_page_flip_calls == 60 and drm_vblank_flip_events == 60 and
sent_frames == 60 and receiver_written_frames == 60 and
receiver_dropped_packets == 0 and motion_content_type == textured-motion and
captured_motion_frames >= 60 and tearing_validator_calibrated == 1 and
tearing_frames == 0 and frame_duration_stddev_ms <= 4.0 and
validator_status == pass).

measured=(display_backend=drm-kms, drm_device=/dev/dri/card0,
fbdev_live_write_used=0, drm_dumb_buffers=2, drm_page_flip_calls=60,
drm_vblank_flip_events=60, sent_frames=60, receiver_written_frames=60,
receiver_dropped_packets=0, motion_content_type=textured-motion,
captured_motion_frames=120, tearing_validator_calibrated=1,
tearing_frames=0, frame_duration_stddev_ms=19.614,
validator_status=pass).

The cycle failed because `frame_duration_stddev_ms=19.614` is above the frozen
`<= 4.0` smoothness threshold.

## Evidence

- `build/drm-kms-vblank-motion-tearing/drm-kms-vblank-motion-tearing-summary.json`
- `build/drm-kms-vblank-motion-tearing/uart_after_drm_receiver.log`
- `build/drm-kms-vblank-motion-tearing/validator-calibration/motion-tearing-calibration.json`
- `build/drm-kms-vblank-motion-tearing/motion-tearing-validation/motion-tearing-validation.json`
- `build/drm-kms-vblank-motion-tearing/mjpeg-return/mjpeg-stream-probe.json`

## Notes

- The Linux network-to-DRM-to-HDMI functional path is implemented and verified
  at the event/capture level.
- The smoothness gate is still not met. The board receiver needed about 37 s to
  process and page-flip 60 full 800x600 RGB888 UDP frames, despite zero packet
  drops in the receiver.
- The failure is not a tearing failure: the calibrated validator found
  `tearing_frames=0` over 120 captured motion frames.
