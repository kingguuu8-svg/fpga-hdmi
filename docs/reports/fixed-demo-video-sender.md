# Fixed Demo Video Sender

Date: 2026-07-01

## Objective

Add a fixed built-in dynamic video source for the PC dashboard MVP, without
adding camera/webcam capture or user-selected input files.

## Changed Scope

- Added `tools/dashboard/demo_source.py`, a deterministic RGB888 dynamic frame
  generator.
- Added `tools/send_demo_video_udp.py`, a PC-side UDP sender that uses the
  existing project video packet format.
- Added `tools/dashboard/__init__.py` so dashboard helpers can be imported by
  the sender.
- Updated the dashboard and project documentation to record that custom input
  files remain deferred after MVP.

## Verification

Ran:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\fixed-demo-video-sender"
```

Result:

```text
DEMO_VIDEO_SENDER_SELF_TEST_OK out=build\fixed-demo-video-sender packets=30
```

Also ran a parser inspection to confirm that the sender exposes no camera,
webcam, file, or input-file option:

```text
DEMO_VIDEO_SENDER_CLI_NO_CAMERA_OR_FILE_OK options=-h,--help,--port,--width,--height,--fps,--frames,--start-frame-id,--payload,--inter-packet-us,--self-test,--out-dir
```

The self-test verified:

- generated RGB888 frame size is correct
- frame 0 and frame 1 differ
- one generated frame is packetized through localhost UDP loopback
- all 30 packets are received
- received payload bytes match the generated frame size
- received packet frame id is stable
- camera input is disabled
- custom-file input is disabled

Raw evidence:

```text
build/fixed-demo-video-sender/self-test.json
```

## Board Action

None. This cycle only adds the PC-side fixed built-in demo video sender.

## Result

PASSED. The dashboard MVP now has a deterministic dynamic input source that can
feed the existing Ethernet video receiver without depending on a camera,
webcam, file picker, or custom user media.

## Residual Risks

- This is a generated demo source, not arbitrary video-file playback.
- The self-test proves localhost packetization, not board receive/display.
- Dashboard start/stop/control integration remains the next cycle.
