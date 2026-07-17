# PC Dashboard

The dashboard is a PC-side web console for the Zynq video pipeline.
The preferred mode is the real GStreamer route:
`1280x720@30 RTP/JPEG -> jpegpldec backend=pl-decoder -> kmssink -> PL PIP -> HDMI`.
The legacy custom UDP/fbdev route is recovery-only.

MVP panels:

```text
Input To FPGA:
  local preview of the PC GStreamer videotestsrc ball source
  no camera/webcam input
  custom file input deferred after MVP

FPGA Output:
  live HDMI return MJPEG stream from the capture adapter
  output verification only, not an input source

Function Control Panel:
  start-stream starts the board GStreamer receiver over UART and the PC
  GStreamer RTP/JPEG sender; the board command preflights jpegpldec, KMS, and
  the PIP TCP control daemon
  stop-stream stops the PC sender and attempts to stop the board receiver
  capture-output is only a manual HDMI snapshot fallback
  receiver-status tails the board GStreamer receiver and PIP daemon logs over
  UART
  pause/resume controls the board gst-launch process; PIP preset buttons use
  the TCP control daemon
```

Run the GStreamer/Chinese UI self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-gstreamer-chinese-control"
```

Expected markers include:

```text
DASHBOARD_GSTREAMER_CONTROL_SELF_TEST_OK
DASHBOARD_CHINESE_UI_SELF_TEST_OK
```

Run the displayable board-live loop:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\finite-loop -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200
```

This deploys the receiver to `/tmp`, starts the dashboard, triggers
`start-stream`, reads `/api/output-stream.mjpeg`, and requires the returned
MJPEG stream to classify as the generated full-screen color-block source.

Run the board-live loop and leave the dashboard/sender running:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\live-demo -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 40 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200 -KeepRunning
```

Run the fixed demo-video sender self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\fixed-demo-video-sender"
```

Run the local GStreamer dashboard:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765 --pipeline gstreamer --uart-port COM16 --uart-login-root --uart-password root"
```

Dashboard action API:

```text
GET  /api/actions
POST /api/action {"action":"start-stream"}
POST /api/action {"action":"stop-stream"}
POST /api/action {"action":"capture-output"}
POST /api/action {"action":"pause-receiver"}
POST /api/action {"action":"resume-receiver"}
POST /api/action {"action":"receiver-status"}
POST /api/action {"action":"effect-none"}
POST /api/action {"action":"effect-invert"}
```

Current behavior:

```text
start-stream:
  board: preflight /dev/dri/card0, the deployed jpegpldec plugin, and
    /tmp/pip-tools/pip_effect_server; then run udpsrc port=5011 ! rtpjitterbuffer !
    rtpjpegdepay ! jpegparse !
    capssetter caps="image/jpeg,framerate=(fraction)30/1" !
    jpegpldec backend=pl-decoder !
    video/x-raw,format=BGR,width=1280,height=720 ! kmssink
    force-modesetting=true sync=false qos=false
  board control: start the PIP TCP daemon, apply the large same-source preset,
    then read it back so the dashboard state reflects the actual registers
  PC: the GStreamer executable in the project Conda environment runs
    videotestsrc ball at 1280x720@30 ! tee; one branch
    records the actual RGB source preview, the other uses I420 ! jpegenc !
    rtpjpegpay ! udpsink

right panel:
  live HDMI return through /api/output-stream.mjpeg
  DShow negotiates MJPG at device-open time; setting FOURCC after opening the
  capture device silently falls back to 1280x720 YUY2 at 10 fps on the current
  adapter

capture-output:
  manual HDMI snapshot capture through tools/capture_hdmi.py; not the primary
  right-panel video path

pause-receiver / resume-receiver / receiver-status:
  pause/resume send STOP/CONT to the board gst-launch process;
  receiver-status tails both receiver and PIP daemon logs

effect-none / effect-invert:
  retained for legacy UDP mode; use the PIP preset buttons for the active PL
  effect path
```

The board must have these runtime files before `start-stream`:

```text
/tmp/gst-plugins/libgstjpegpldec.so
/tmp/pip-tools/pip_effect_server
```

The dashboard fails explicitly with `JPEGPLDEC_PLUGIN_MISSING` or
`PIP_CONTROL_SERVER_MISSING` rather than silently falling back to software
JPEG or fbdev. Use `--gst-decoder jpegdec --gst-sink fbdevsink` only for an
explicit recovery comparison.

The PC source and RTP caps request 30 fps. The current synchronous PL decode
plus GStreamer 1.12 `kmssink` route presents about 15 distinct HDMI content
frames per second; the dashboard's faster MJPG capture does not change that
board-side content rate. See `docs/project-roadmap.md` and the latest native
display report for the measured boundary.

Disable UART explicitly if the serial port should not be touched:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --uart-disabled"
```

Use dry-run mode only when testing command semantics without launching the
sender process:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --action-mode dry-run"
```

Use legacy UDP/fbdev mode only for recovery comparison with older dashboard
cycles:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --pipeline legacy-udp"
```
