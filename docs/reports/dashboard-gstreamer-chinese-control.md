# Dashboard GStreamer Chinese Control

Cycle ID: dashboard-gstreamer-chinese-control

Date: 2026-07-02

## Result

PASSED after visual correction.

## Objective

Make the Chinese dashboard represent the actual mature GStreamer path and show
the real PC source beside the HDMI return.

## Final Route

```text
PC videotestsrc ball
-> tee -> actual RGB source preview
-> I420 -> jpegenc -> rtpjpegpay -> UDP 5011
-> board rtpjitterbuffer -> rtpjpegdepay -> jpegdec
-> videoconvert -> videoscale -> BGR 800x600
-> fbdevsink /dev/fb0 -> HDMI -> PC UVC capture
```

The board start command first kills stale `gst-launch-1.0` processes and hides
the cursor on the active framebuffer virtual terminal.

## Corrections

- Removed the unrelated Python-rendered approximation from the left panel.
- Replaced cross-version RTP/raw transport with RFC 2435 JPEG/RTP.
- Replaced tearing `kmssink force-modesetting=true` output with `fbdevsink`.
- Changed the sender to unlimited runtime by default.
- Changed sender logs to truncate on each start.

The earlier motion-only check was insufficient: it accepted black/white
cross-frame slicing as motion. The withdrawn result is documented in
`docs/reports/gstreamer-rtp-raw-kmssink-closed-loop.md`.

## Verification

```text
python -m py_compile tools\dashboard\pc_dashboard.py
python .\tools\dashboard\pc_dashboard.py --self-test \
  --out-dir build\dashboard-gstreamer-chinese-control
```

Required markers passed:

```text
DASHBOARD_GSTREAMER_CONTROL_SELF_TEST_OK
DASHBOARD_CHINESE_UI_SELF_TEST_OK
```

Connected-board evidence:

- PC GStreamer 1.28.4 has `jpegenc`, `rtpjpegpay`, and `multifilesink`.
- Board GStreamer 1.12.2 has `rtpjpegdepay`, `jpegdec`, and `fbdevsink`.
- Board log reached `jpegdec -> videoconvert -> videoscale -> fbdevsink`.
- Twelve interval HDMI samples contained 11 unique hashes.
- Yellow-ball detection passed in all 12 frames.
- Ball centroid motion measured `x_span=283.98`, `y_span=277.77`.
- Background RGB mean measured `(16.0, 59.1, 75.2)`.
- Visual inspection showed the same blue background, yellow moving ball, and
  source crosshair in the actual PC source and HDMI return.

## Evidence

- `build/dashboard-gstreamer-chinese-control/`
- `build/dashboard-gstreamer-live/uart-gstreamer-start-1783006010603.log`
- `build/dashboard-gstreamer-live/uart-jpeg-manual-send-status.log`
- `build/dashboard-gstreamer-live/final-color-motion/`
- `build/dashboard-gstreamer-live/final-color-motion/color-motion-validation.json`

## Board Action

- Used Ethernet for JPEG/RTP video.
- Used UART for receiver lifecycle control.
- Used HDMI/UVC for return verification.
- Did not rebuild Vivado or PetaLinux and did not write the TF card.

## Residual Risks

- JPEG compression causes small expected color differences.
- Pause, resume, and effects remain explicit not-implemented actions in the
  GStreamer dashboard mode.

