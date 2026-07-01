# Dashboard Color Block Loop And UART Audit

Date: 2026-07-01

## Objective

Replace the visually ambiguous generated demo with full-screen sequential color
blocks, then verify the complete loop with machine-readable evidence:

```text
PC generated color block -> UDP sender -> board Linux receiver -> /dev/fb0
-> VDMA/HDMI -> PC HDMI capture adapter -> Dashboard live MJPEG right panel
```

Also verify that the Dashboard UART controls can drive the running receiver
through `/tmp/video_ctl` and report real receiver responses.

## Changed Scope

- Replaced the demo generator with full-screen RGB888 color blocks:
  red, green, blue, white, black, yellow, cyan, and magenta.
- Added sender log output for the color name of every transmitted frame.
- Added MJPEG return-stream color classification to
  `tools/probe_mjpeg_stream.py`.
- Added finite validation and keep-running demo modes to
  `tools/run_dashboard_board_live_loop.ps1`.
- Disabled the Linux framebuffer console cursor before starting the receiver.
  This removes the small black blinking overlay that was visible on HDMI.
- Changed Dashboard UART actions to pass commands through a command file and
  include tailed receiver markers in the action response.

## Verification

### Local checks

```text
rtk powershell.exe -NoProfile -Command "python -m py_compile tools\dashboard\demo_source.py tools\send_demo_video_udp.py tools\dashboard\pc_dashboard.py tools\probe_mjpeg_stream.py tools\capture_hdmi.py"
```

Result: passed.

```text
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\dashboard-color-block-loop-and-uart-audit\sender-selftest"
```

Result:

```text
DEMO_VIDEO_SENDER_SELF_TEST_OK ... packets=30
```

The self-test report records:

```text
pattern=full-screen-sequential-color-blocks
palette=red,green,blue,white,black,yellow,cyan,magenta
camera_input=false
custom_file_input=false
received_packets=30
```

```text
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-color-block-loop-and-uart-audit\dashboard-selftest-after-uart-fix"
```

Result:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
DASHBOARD_MINIMAL_UI_SELF_TEST_OK
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
```

```text
rtk powershell.exe -NoProfile -Command "$text=Get-Content -Raw tools\run_dashboard_board_live_loop.ps1; [void][scriptblock]::Create($text); Write-Host 'PS_PARSE_OK'"
```

Result: `PS_PARSE_OK`.

### Finite board loop

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\finite-loop -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200
```

Marker:

```text
DASHBOARD_BOARD_LIVE_LOOP_OK mode=finite receiver_frames=12 sender_frames=12 written=12 mjpeg_frames=80 mjpeg_unique=8 mjpeg_colors=8 color_names=black,blue,cyan,green,magenta,red,white,yellow
```

Sender evidence:

```text
demo_frame=0 color=red bytes=1440000 packets=1200
demo_frame=1 color=green bytes=1440000 packets=1200
demo_frame=2 color=blue bytes=1440000 packets=1200
demo_frame=3 color=white bytes=1440000 packets=1200
demo_frame=4 color=black bytes=1440000 packets=1200
demo_frame=5 color=yellow bytes=1440000 packets=1200
demo_frame=6 color=cyan bytes=1440000 packets=1200
demo_frame=7 color=magenta bytes=1440000 packets=1200
DEMO_VIDEO_SEND_OK frames=12 packets=14400 target=192.168.1.10:5005
```

Receiver evidence:

```text
CONTROL_FIFO_READY path=/tmp/video_ctl
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=12 timeout_sec=180 control=/tmp/video_ctl effect=none
VIDEO_UDP_FRAME_WRITTEN frame_id=0 frames=1 packets=1200 dropped=0 skipped=0 effect=none
...
VIDEO_UDP_FRAME_WRITTEN frame_id=11 frames=12 packets=14400 dropped=0 skipped=0 effect=none
VIDEO_UDP_RECEIVER_DONE frames=12 skipped=0 packets=14400 dropped=0
```

HDMI return evidence:

```text
MJPEG_STREAM_PROBE_OK frames=80 unique=8 colors=black,blue,cyan,green,magenta,red,white,yellow
```

This proves the Dashboard right panel is consuming a live HDMI return stream
whose frames classify as the PC source color blocks. It is not a stale static
image and not the previous decorative PIP/checker demo.

### Keep-running demo loop

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\live-demo -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 40 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200 -KeepRunning
```

Marker:

```text
DASHBOARD_BOARD_LIVE_LOOP_OK mode=keep-running receiver_frames=1000000 sender_frames=0 written=19 mjpeg_frames=40 mjpeg_unique=7 mjpeg_colors=7 color_names=black,cyan,green,magenta,red,white,yellow
```

The Dashboard was left running at `http://127.0.0.1:8765` for live inspection.

### UART control

Bottom-layer UART/FIFO probe:

```text
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_uart_control_probe.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\uart-control-probe -CaptureDevice 1
```

Observed receiver markers:

```text
CONTROL_PAUSED commands=1
VIDEO_UDP_FRAME_SKIPPED_PAUSED frame_id=100 skipped=1 packets=1200 dropped=0
CONTROL_RESUMED commands=2
CONTROL_STATUS paused=0 quit=0 commands=3 unknown=0
VIDEO_UDP_FRAME_WRITTEN frame_id=101 frames=1 packets=2400 dropped=0 skipped=1 effect=none
VIDEO_UDP_RECEIVER_DONE frames=1 skipped=1 packets=2400 dropped=0
HDMI_CAPTURE_OK
UART_CONTROL_PROBE_OK
```

Dashboard action API probe against the live demo:

```text
pause-receiver: http_status=200, response contains CONTROL_PAUSED and VIDEO_UDP_FRAME_SKIPPED_PAUSED
receiver-status while paused: http_status=200, response contains CONTROL_STATUS paused=1
resume-receiver: http_status=200, response contains CONTROL_RESUMED and VIDEO_UDP_FRAME_WRITTEN
receiver-status after resume: http_status=200, response contains CONTROL_STATUS paused=0
```

The previous Dashboard UART failure was caused by passing multi-word UART shell
commands through the PowerShell `-Command` array path. `sleep 1` was bound as a
file path in the helper. The Dashboard now writes a command file and calls
`uart_run_commands.ps1 -CommandFile ...`, which avoids that parameter-binding
failure.

## Result

PASSED.

The current demo source is a simple full-screen color-block video. The PC sender
logs the exact source color sequence, the board receiver writes those frames
with `effect=none` and `dropped=0`, the Dashboard right panel sees a live HDMI
MJPEG stream classified as the same source color set, and UART pause/resume/
status controls produce real receiver responses.

## Residual Risks

- HDMI/UVC capture and MJPEG encoding prevent pixel-perfect equality checks.
  The current proof is semantic color classification plus receiver packet/write
  markers.
- The input preview and HDMI return preview are not frame-locked.
- `-KeepRunning` uses a large finite receiver frame count and a 3600 second
  receiver timeout; it is a demo mode, not a persistent system service.
- `effect-none` and `effect-invert` Dashboard buttons still describe receiver
  launch selection. Runtime effect switching is not claimed by this cycle.

## Third-party review

Non-blocking. Recorded after cycle close. Covers this cycle and the three
related dashboard closed-loop cycles (`dashboard-board-live-loop`,
`dashboard-truthful-loop-validation`, `dashboard-live-pass-through-preview`)
because the four share the same sampling architecture and the same validation
philosophy, so the concerns apply uniformly.

### What was independently checked

- Decoded the actual MJPEG return frames in
  `build/dashboard-color-block-loop-and-uart-audit/finite-loop/mjpeg-return/mjpeg-frame-*.jpg`
  with OpenCV and inspected per-frame pixel statistics (mean, std, corner vs.
  center, unique-color count).
- Compared the captured color timeline against the sender's logged source
  sequence.
- Cross-read `tools/dashboard/demo_source.py`, `tools/send_demo_video_udp.py`,
  `tools/probe_mjpeg_stream.py`, `tools/capture_hdmi.py`, and the dashboard
  `_open_live_capture` / `stream_mjpeg` / input-preview handlers.
- Cross-read `software/eth_pass_through/src/video_framebuffer.c` and the
  `inverted-rgb-stripes` / `rgb-stripes` validation JSONs to verify the
  framebuffer BGR byte-order mapping and the invert effect.

### Findings that hold up

- The HDMI return frames are genuinely captured, not synthesized. Pure-color
  frames have `std=0` with identical corners and center (digital path, no
  noise); non-trivial colors show real capture signatures, e.g. the cyan frame
  has corner red-channel values `[35,36]` vs. center `[5]`, and the red frame
  has corners `[255,10,4]` vs. center `[254,0,0]`. A synthesized image would not
  produce an edge-vs-center gradient. The `cv2.VideoCapture` HDMI capture path
  is real.
- The RGB invert effect is real and correctly byte-order-mapped. The
  `first-board-side-effect` `inverted-rgb-stripes` capture matches `255 - source`
  to high precision (yellow `[254.58,254.58,16.02]`, magenta `[255,0,255]`, cyan
  `[5,255,255]`), and `video_framebuffer.c` uses the BGR layout
  `red_byte=2, green_byte=1, blue_byte=0` confirmed by the plain
  `rgb-stripes` capture.
- UART pause/resume/status produce real receiver markers
  (`VIDEO_UDP_FRAME_SKIPPED_PAUSED`, `CONTROL_STATUS paused=1`).
- The `dynamic_samples_unique=5` evidence in `dashboard-truthful-loop-validation`
  is credible: pure-color frames produce byte-identical JPEGs across repeats
  (same sha), so hash diversity does reflect content change, not capture noise.

### Concern 1 — sampling logic is counter-intuitive, not robust, and a detour

The user's standing objection: the natural design is a single unified
passthrough where the source transmits at a real video frame rate (15/30 fps,
bounded by link bandwidth) while the *content* changes slowly (1 color change
per second), and the HDMI return is sampled at the same rate with one shared
standard. Instead the project grew four independent, mutually inconsistent
validation standards:

- `dashboard-color-block-loop-and-uart-audit`: source 2 fps, MJPEG 10 fps,
  browser input preview 1 fps; pass = captured color *set* equals source color
  *set* (`len(unique_colors) >= 3`, per-color Euclidean distance <= 90).
- `dashboard-truthful-loop-validation`: pass = `dynamic_samples_unique >= 5`.
- `dashboard-live-pass-through-preview`: pass = `mjpeg_unique >= 2`.
- `capture_hdmi.py`: pass = best-scoring frame out of 45 captured samples,
  saved as `latest.png`.

None of these is frame-locked. Each standard was chosen so the cycle that
introduced it could close, rather than being defined up front and then
implemented to. This is "standards passively adapted to code" rather than
"code adapted to a standard", and it is the root cause the user identified as
manufacturing trouble.

### Concern 2 — three independent clocks make the dashboard visually misleading

The browser input preview (`setInterval(refreshState, 1000)`, frame counter
self-incrementing at 1 fps), the real UDP sender (`--fps 2`), and the HDMI
return MJPEG (`stream_fps=10`) run on three unrelated clocks. The user
observed "capture changes faster than the source" — that is the 10 fps MJPEG
delivery rate, not the content change rate. Worse, the state JSON advertises
`preview_matches_sender_source: true`, but the preview only reuses the *same
generator function* `make_demo_frame`; it does not read the actual sent stream.
A truthful field would be `preview_uses_same_generator_only`.

### Concern 3 — color-set equality is presented as if it were temporal equality

The source is sent starting with `red`, but the captured 80-frame timeline
begins with `white` for ~0.3 s (stale framebuffer from the previous run), then
`black` for ~0.7 s, and only later aligns with the source sequence; after the
source finishes the framebuffer freezes on `white` for ~2.5 s. `unique=8`
happens to equal the 8-color palette, so the set-equality check passes cleanly,
but the head-of-stream misalignment and the tail freeze are invisible to it.
"frames classify as the PC source color blocks" is true as a set statement and
overstates what was proven as a temporal statement.

### Concern 4 — best-of-45 selection hides instability

`capture_hdmi.py:250-273` grabs 45 frames, scores each, and stores only the
highest-scoring one as `latest.png`, then judges PASS from that single frame.
For static VDMA output (the current case) all 45 are identical, so this is
harmless today. For any dynamically changing or unstable output it would mask
flicker and present the best moment as the evidence. The pass criterion should
record and report how many of the 45 passed, not just the best score.

### Concern 5 — no latency or sustained-throughput measurement across any cycle

13 cycles closed without one measuring end-to-end latency or sustainable FPS.
The 1 fps × 1200-packet, 0.5 s-per-frame pacing leaves gigabit Ethernet under
5 % load and exposes no loss, jitter, or bandwidth bottleneck. The unified
passthrough cycle should report latency and a sustained drop rate at a real
video rate.

### Recommended next cycle (non-blocking, for the user to approve)

Establish a single unified passthrough standard that replaces the four
ad-hoc ones:

- Source transmits at 15 fps (30 fps as a stress tier), payload 1400,
  `inter_packet_us 0`; content may still change slowly, but every frame
  carries the protocol's existing incrementing `frame_id`.
- HDMI return is sampled at the same 15 fps.
- Browser input preview is derived from the actual sent stream, not an
  independent generator.
- Pass criterion is frame-correspondence: the `frame_id` read back from the
  capture matches the sender's sequence within an allowed end-to-end latency,
  plus a sustained drop rate and a latency report — not color-set equality and
  not best-of-N.

Bandwidth check: 800x600x3x15 = ~207 Mbps, ~15420 packets/s, comfortably
within gigabit; 30 fps = ~345 Mbps as a stress tier. This both produces honest
temporal evidence and stress-tests the link, which the current 1 fps path
never does.

This section is non-blocking. The four cycles remain PASSED for what they
actually proved (physical HDMI path live, invert effect real, UART control
real, Ethernet pass-through functional at low rate). The concern is that the
PASSED label carries more guarantee than the validation scripts check, and
that a single unified standard should replace the four ad-hoc ones before the
project claims a verified closed loop.
