# GStreamer RTP Raw Kmssink Closed Loop

Date: 2026-07-02

## Result

WITHDRAWN on 2026-07-02 after visual review.

The motion-only validator accepted black/white frame slicing as a moving-ball
result. Direct visual comparison later proved that the source preview was not
the actual GStreamer source and that `kmssink force-modesetting=true` produced
cross-frame tearing on this board. This route is negative evidence, not a
verified workflow. The replacement route is recorded in
`docs/reports/dashboard-gstreamer-chinese-control.md`.

The connected board displayed a PC-generated GStreamer RTP/raw video stream
through board-side GStreamer and `kmssink`, and HDMI return capture validated
that the returned image sequence was dynamic and matched the moving-ball source
class.

## Objective

```text
PC GStreamer videotestsrc -> RTP/raw video over UDP -> board GStreamer udpsrc
-> rtpjitterbuffer -> rtpvrawdepay -> videoconvert -> videoscale -> kmssink
-> /dev/dri/card0 -> HDMI -> PC HDMI capture validation
```

## Changed Scope

- Created an isolated PC conda GStreamer environment under
  `build/conda-gstreamer-pc`.
- Added `--read-interval-ms` to `tools/capture_hdmi.py` so HDMI validation can
  sample over time instead of reading a burst of duplicate capture frames.
- Added `tools/validate_hdmi_ball_motion.py` for source-specific dynamic HDMI
  validation.
- Did not rebuild Vivado, PetaLinux, the bitstream, or the TF-card image.

## Final Verified Pipeline

PC sender:

```text
conda run -p .\build\conda-gstreamer-pc gst-launch-1.0 -v
  videotestsrc num-buffers=360 is-live=true pattern=ball
    motion=sweep animation-mode=wall-time flip=true
  ! video/x-raw,format=RGB,width=320,height=240,framerate=5/1
  ! rtpvrawpay pt=96 mtu=1200
  ! udpsink host=192.168.1.10 port=5011 sync=false async=false
```

Board receiver:

```text
gst-launch-1.0 -v
  udpsrc port=5011 caps="application/x-rtp, media=(string)video,
    clock-rate=(int)90000, encoding-name=(string)RAW,
    sampling=(string)RGB, depth=(string)8, width=(string)320,
    height=(string)240, colorimetry=(string)SMPTE240M,
    payload=(int)96, a-framerate=(string)5"
  ! rtpjitterbuffer latency=100 drop-on-latency=true
  ! rtpvrawdepay
  ! videoconvert
  ! videoscale
  ! video/x-raw,format=BGR,width=800,height=600
  ! kmssink force-modesetting=true sync=true
```

`force-modesetting=true` is required on this image. Without it, `kmssink`
displayed a valid first frame but HDMI samples stayed static. A board-local
`videotestsrc -> kmssink` isolation test showed the same behavior and then
passed after enabling `force-modesetting=true`.

## Verification

PC GStreamer provisioning:

- `conda create -p build/conda-gstreamer-pc -c conda-forge gstreamer
  gst-plugins-base gst-plugins-good gst-plugins-bad` completed.
- `gst-launch-1.0 version 1.28.4` is available through the conda environment.
- Required PC sender elements include `videotestsrc`, `rtpvrawpay`,
  `udpsink`, `capsfilter`, `videoconvert`, and `queue`.

PC source validation:

- Exported 12 raw RGB frames from PC `videotestsrc pattern=ball`.
- `HDMI_BALL_MOTION_OK samples=12 unique_hashes=12 frames_with_ball=12
  x_span=18.954 y_span=4.365`.

Board dependency and path validation:

- Board `gst-launch-1.0` version: 1.12.2.
- Board Ethernet to PC: `192.168.1.10 -> 192.168.1.2` ping succeeded.
- Board required elements present: `udpsrc`, `rtpjitterbuffer`,
  `rtpvrawdepay`, `videoconvert`, `videoscale`, `queue`, `capsfilter`,
  `identity`, `fpsdisplaysink`, and `kmssink`.
- Board identity/fakesink diagnostic received 59 complete depay buffers after
  a 60-frame PC send.

Board-local kmssink isolation:

- Plain `kmssink` showed a valid but static frame.
- `kmssink force-modesetting=true sync=true` passed HDMI dynamic validation:
  `HDMI_BALL_MOTION_OK samples=24 unique_hashes=24 frames_with_ball=24
  x_span=590.956 y_span=373.838`.

Final HDMI return validation:

```text
HDMI_BALL_MOTION_OK samples=24 unique_hashes=23
frames_with_ball=24 x_span=110.605 y_span=200.274
```

Final board caps evidence:

- `udpsrc`: RTP RAW RGB 320x240, payload 96, 5 fps metadata.
- `rtpjitterbuffer`: accepted the RTP caps.
- `rtpvrawdepay`: output `video/x-raw, format=RGB, width=320, height=240`.
- `videoconvert`: output `video/x-raw, format=BGR, width=320, height=240`.
- `videoscale`: output `video/x-raw, format=BGR, width=800, height=600`.
- `kmssink`: accepted `video/x-raw, format=BGR, width=800, height=600` and
  reported display size 800x600.

## Evidence Files

- `build/gstreamer-rtp-kmssink-route/pc-conda-create.log`
- `build/gstreamer-rtp-kmssink-route/pc-rtpvrawpay-caps.log`
- `build/gstreamer-rtp-kmssink-route/uart-board-element-probe.log`
- `build/gstreamer-rtp-kmssink-route/pc-source-raw-abs-motion.log`
- `build/gstreamer-rtp-kmssink-route/uart-board-identity-fakesink-after-send.log`
- `build/gstreamer-rtp-kmssink-route/hdmi-local-ball-kmssink-force-validation.json`
- `build/gstreamer-rtp-kmssink-route/uart-board-rx-320scale-force-after-send.log`
- `build/gstreamer-rtp-kmssink-route/pc-gst-send-320scale-force.out.log`
- `build/gstreamer-rtp-kmssink-route/hdmi-320scale-force-capture/`
- `build/gstreamer-rtp-kmssink-route/hdmi-320scale-force-validation.json`

## Rollback Point

- Previous commit before this cycle: `0a8e33c`.
- Board image rollback remains the TF-card backup from the GStreamer rootfs
  integration cycle:
  `/run/media/mmcblk0p1/image.ub.prev-gstreamer-rootfs-20260702`.
- PC conda environment is disposable:
  `build/conda-gstreamer-pc`.

## Residual Risks

- The verified closed loop uses 320x240 RTP/raw input scaled to 800x600 for
  HDMI. 800x600 RTP/raw input reached `kmssink` caps negotiation but HDMI
  samples stayed static without a passing dynamic route.
- The validator proves dynamic moving-ball source correspondence, not full
  frame-id correspondence or product-grade smoothness.
- `rtpvrawdepay` on board GStreamer 1.12 reports output framerate as `0/1`;
  avoid forcing `framerate=5/1` after depay because that caused
  `not-negotiated`.
- PC GStreamer is currently provided by a local conda environment in `build/`,
  not by a system-wide installation.
