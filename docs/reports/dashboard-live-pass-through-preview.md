# Dashboard Live Pass-Through Preview

Date: 2026-07-01

Result: PASSED

## Objective

Make the dashboard right panel show the live HDMI return path for the no-effect
pass-through case, instead of presenting a static HDMI capture image as if it
were video.

## Definitions

- `capture`: a still-frame evidence action. It grabs one or more frames from
  the HDMI capture adapter and writes files for verification.
- `live return preview`: the dashboard right panel. It opens the HDMI capture
  adapter and serves a continuous MJPEG stream at `/api/output-stream.mjpeg`.

The MVP demo should use live return preview for the user-facing right panel.
Still capture remains only as a manual fallback/evidence mechanism.

## Changes

- The dashboard output panel now points at `/api/output-stream.mjpeg`.
- The live stream endpoint opens the HDMI capture adapter and emits JPEG frames
  continuously.
- `start-stream` no longer waits for or schedules a still capture by default.
  It starts the UDP sender and reports that the HDMI return stream endpoint is
  ready.
- Added `tools/probe_mjpeg_stream.py` to verify the same MJPEG stream that the
  browser consumes.
- Updated `tools/run_dashboard_board_live_loop.ps1` to validate the MJPEG live
  return path instead of validating only `latest.png`.

## Verification

Commands run:

```powershell
rtk powershell.exe -NoProfile -Command "python -m py_compile tools\dashboard\pc_dashboard.py tools\probe_mjpeg_stream.py tools\dashboard\demo_source.py tools\send_demo_video_udp.py tools\capture_hdmi.py"
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-live-pass-through-preview-selftest"
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-live-pass-through-preview -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -Frames 12 -Fps 2 -InterPacketUs 200
```

Markers:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
DASHBOARD_MINIMAL_UI_SELF_TEST_OK
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
DASHBOARD_BOARD_LIVE_LOOP_OK frames=12 written=12 mjpeg_frames=80 mjpeg_unique=26
```

Board receiver evidence:

```text
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=12 timeout_sec=180 control=/tmp/video_ctl effect=none
VIDEO_UDP_FRAME_WRITTEN frame_id=0 frames=1 packets=1200 dropped=0 skipped=0 effect=none
...
VIDEO_UDP_FRAME_WRITTEN frame_id=11 frames=12 packets=14400 dropped=0 skipped=0 effect=none
VIDEO_UDP_RECEIVER_DONE frames=12 skipped=0 packets=14400 dropped=0
```

Dashboard evidence:

```text
detail: HDMI_RETURN_STREAM_READY endpoint=/api/output-stream.mjpeg
input_source.preview_matches_sender_source: true
output_preview.live_stream_enabled: true
output_preview.live_stream_endpoint: /api/output-stream.mjpeg
output_preview.semantic: manual snapshot fallback; the right panel uses live_stream_endpoint
```

MJPEG return evidence:

```text
url: http://127.0.0.1:8765/api/output-stream.mjpeg
frames: 80
unique_hashes: 26
status: pass
```

Visual inspection of `mjpeg-frame-00.jpg` and `mjpeg-frame-79.jpg` showed the
same generated no-effect demo image returning over HDMI, with the checker/PIP
block at different positions.

## Board Action

Ran the Linux userspace receiver from `/tmp`, sent generated UDP frames from
the PC dashboard sender, and streamed HDMI back through the PC HDMI capture
adapter. No Vivado rebuild, PetaLinux rebuild, JTAG programming, TF-card write,
or board flash write.

## Residual Risks

- This validates live visual pass-through, not pixel-perfect source/output
  equality. The HDMI/UVC adapter applies its own capture path and the MJPEG
  endpoint JPEG-encodes returned frames.
- The generated input preview and HDMI return preview are not frame-locked in
  the browser; they are two live views of the same deterministic source path.
- Windows may still report HDMI/UVC adapter access as camera access. Webcam
  input remains disabled.
