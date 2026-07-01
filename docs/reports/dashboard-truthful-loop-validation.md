# Dashboard Truthful Loop Validation

Date: 2026-07-01

Result: PASSED

## Objective

Correct the dashboard closed-loop demo so it does not present unrelated input
art or a stale HDMI still image as proof of a live pipeline.

## Changes

- Dashboard input preview now serves `/api/input-preview.bmp` generated from
  the same `tools/dashboard/demo_source.py` frame function used by the UDP
  sender.
- `start-stream` and `capture-output` schedule HDMI capture on a background
  thread. The button response returns after the sender starts and capture is
  scheduled, instead of blocking until DirectShow capture completes.
- Dashboard state now labels HDMI preview as a snapshot and records
  `preview_matches_sender_source=true`.
- The board-live helper now interrupts stale UART foreground commands before
  deployment, uses the known HDMI capture device index `1` by default, saves
  HDMI samples, and requires at least two distinct sample hashes.

## Verification

Commands run:

```powershell
rtk powershell.exe -NoProfile -Command "python -m py_compile tools\dashboard\pc_dashboard.py tools\dashboard\demo_source.py tools\send_demo_video_udp.py tools\capture_hdmi.py"
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-truthful-loop-validation-selftest"
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-truthful-loop-validation -CaptureDevice 1 -CaptureBackend dshow -CaptureFrames 90 -CaptureSaveSamples 6 -Frames 12 -Fps 2 -InterPacketUs 200
```

Markers:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
DASHBOARD_MINIMAL_UI_SELF_TEST_OK
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
DASHBOARD_BOARD_LIVE_LOOP_OK frames=12 written=12 dynamic_samples_unique=5
```

Board receiver evidence:

```text
CONTROL_FIFO_READY path=/tmp/video_ctl
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=12 timeout_sec=180 control=/tmp/video_ctl effect=none
VIDEO_UDP_FRAME_WRITTEN frame_id=0 frames=1 packets=1200 dropped=0 skipped=0 effect=none
...
VIDEO_UDP_FRAME_WRITTEN frame_id=11 frames=12 packets=14400 dropped=0 skipped=0 effect=none
VIDEO_UDP_RECEIVER_DONE frames=12 skipped=0 packets=14400 dropped=0
RX packets:117106 errors:0 dropped:0 overruns:0 frame:0
```

Dashboard evidence:

```text
detail: HDMI_CAPTURE_SCHEDULED count=1
capture_status: ok
capture_started_at_s: 0.869
capture_finished_at_s: 8.661
preview_matches_sender_source: true
semantic: snapshot, not a continuous video widget
```

HDMI evidence:

```text
validation_profile: non-black
selected_index: 1
selected_backend: dshow
frames_read: 90
mean_luma: 137.36
saved_samples: 6
unique_sample_hashes: 5
```

Visual inspection of saved HDMI samples showed the checker/PIP block moving
between `latest-sample-00.png` and `latest-sample-05.png`.

## Board Action

Ran the Linux userspace receiver from `/tmp`, sent generated UDP frames from
the PC dashboard sender, and captured HDMI through the PC HDMI capture adapter.
No Vivado rebuild, PetaLinux rebuild, JTAG programming, TF-card write, or board
flash write.

## Residual Risks

- The dashboard output panel is still a refreshed HDMI snapshot, not a
  continuous browser video widget.
- Windows may label the HDMI/UVC capture adapter as camera access; this is
  output verification and not a webcam/video input source.
- Pause/resume/effect buttons are wired, but this cycle did not prove a live
  recorded control choreography.

## Third-party review

Non-blocking. This cycle is one of the four dashboard closed-loop cycles that
share the same sampling architecture and validation philosophy. The unified
third-party review covering all four is recorded in
`docs/reports/dashboard-color-block-loop-and-uart-audit.md` under
"Third-party review". Summary of concerns that apply to this cycle: the
`dynamic_samples_unique=5` evidence is credible (pure-color frames produce
byte-identical JPEGs across repeats, so hash diversity reflects content
change, not capture noise), but it proves "the output changed several times",
not "captured frame N corresponds to sent frame N"; and the dashboard input
preview reuses the sender's generator function rather than reading the actual
sent stream, so `preview_matches_sender_source: true` overstates what is
shown. See the unified review for the recommended single-passthrough-standard
follow-up. This cycle remains PASSED for what it proved: the dashboard loop
has an honest input preview source and dynamic HDMI evidence.
