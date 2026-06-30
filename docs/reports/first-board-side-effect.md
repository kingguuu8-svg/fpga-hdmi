# First Board-Side Effect

Date: 2026-06-30
Cycle ID: first-board-side-effect

## Objective

Add the first board-side visual effect to the Linux receiver and prove that the
board changes the displayed frame while the PC sends the same deterministic
non-camera input pattern.

## Scope

- Added one effect: RGB invert.
- Added host tests for the effect transform.
- Added `--effect none|invert` to the Linux receiver.
- Added an `inverted-rgb-stripes` HDMI validation profile.
- Added `tools/run_first_effect_probe.ps1`.
- Video input remained deterministic PC-generated UDP frames. No camera or
  webcam was used as an input source.
- HDMI capture was used only as an output verification instrument.

## Effect Definition

The input frame is protocol RGB888. The board-side invert effect computes:

```text
out.r = 255 - in.r
out.g = 255 - in.g
out.b = 255 - in.b
```

For the deterministic `rgb-stripes` input this means:

```text
top blue    -> yellow
middle green-> magenta
bottom red  -> cyan
```

The framebuffer byte-order mapping remains separate from the effect transform:
the effect operates on protocol RGB, then the receiver maps RGB into `/dev/fb0`
byte order.

## Verification

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_first_effect_probe.ps1
```

Host build and tests:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
VIDEO_CONTROL_TEST_OK
VIDEO_EFFECT_TEST_OK
LINUX_RECEIVER_BUILD_OK
```

Board binary:

```text
ELF 32-bit LSB executable, ARM, EABI5, dynamically linked
SHA-256 73ef6f5b0e6ac03528ad1c73eb5d2bdcd665ad12514e1d436bff4bdcab1c35ab
```

Deployment and receiver start:

```text
ONE_SHOT_HTTP_SERVED bytes=19008
/tmp/fb_video_udp_receiver: OK
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=1 timeout_sec=90 control=none effect=invert
```

PC input sender:

```text
frame=200 bytes=1440000 packets=1200 elapsed_s=0.905
SEND_OK frames=1 packets=1200 target=192.168.1.10:5005
```

Board receiver:

```text
VIDEO_UDP_FRAME_WRITTEN frame_id=200 frames=1 packets=1200 dropped=0 skipped=0 effect=invert elapsed_ms=7979
VIDEO_UDP_RECEIVER_DONE frames=1 skipped=0 packets=1200 dropped=0 elapsed_ms=7979
```

Ethernet counters:

```text
RX packets:19106 errors:0 dropped:0 overruns:0 frame:0
TX packets:1223 errors:0 dropped:0 overruns:0 carrier:0
```

HDMI capture:

```text
validation_profile: inverted-rgb-stripes
HDMI_CAPTURE_OK device_index=1 backend=dshow
top_yellow:     [254.58, 254.58, 16.02]
middle_magenta: [255.0, 0.0, 255.0]
bottom_cyan:    [5.0, 255.0, 255.0]
```

Raw evidence:

```text
build/first-board-side-effect/test_video_effect.log
build/first-board-side-effect/fb_video_udp_receiver.sha256.txt
build/first-board-side-effect/send_rgb_stripes_input.log
build/first-board-side-effect/uart_after_effect_frame.log
build/first-board-side-effect/hdmi-after-invert-effect/latest-validation.json
build/first-board-side-effect/hdmi-after-invert-effect/latest.png
```

## Result

Status: PASSED.

The board now performs a verified visual transform in the Linux receiver path.
The PC sent a normal deterministic RGB stripe frame; the receiver logged
`effect=invert`; HDMI capture saw the expected inverted CMY stripes.

## Residual Risks

- This is a stateless full-frame software effect, not yet a PL-side PIP,
  rotate, or scale effect.
- The receiver still processes one full frame in CPU memory before writing
  `/dev/fb0`; throughput is not optimized.
- Runtime effect switching through UART is not implemented yet; this cycle uses
  a process startup option.
