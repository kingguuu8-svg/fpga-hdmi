# Dashboard Board Live Loop

Date: 2026-07-01

## Objective

Complete a displayable dashboard-driven board video loop:

```text
PC Dashboard start-stream
-> PC generated RGB888 UDP frames
-> board Linux receiver
-> /dev/fb0
-> VDMA / HDMI
-> USB HDMI capture
-> Dashboard output preview
```

## Changed Scope

- Added `tools/run_dashboard_board_live_loop.ps1`.
- Added `non-black` HDMI validation to `tools/capture_hdmi.py`.
- Allowed the dashboard to use `--capture-profile non-black`.

No camera/webcam input was added. User-selectable custom file input remains
deferred.

## Verification

Ran static/self-test checks:

```powershell
rtk powershell.exe -NoProfile -Command "$null = [scriptblock]::Create((Get-Content -Raw .\tools\run_dashboard_board_live_loop.ps1)); Write-Output 'DASHBOARD_BOARD_LIVE_LOOP_SCRIPT_PARSE_OK'"
rtk powershell.exe -NoProfile -Command "python -m py_compile .\tools\capture_hdmi.py .\tools\dashboard\pc_dashboard.py .\tools\send_demo_video_udp.py"
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-board-live-loop-selftest"
```

Dashboard self-test markers:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
DASHBOARD_MINIMAL_UI_SELF_TEST_OK
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
```

Ran the board-live loop:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-board-live-loop -CaptureDevice auto -CaptureFrames 8 -Frames 5 -Fps 1 -InterPacketUs 200
```

The helper exited with status 0 and wrote:

```text
DASHBOARD_BOARD_LIVE_LOOP_OK frames=5 written=5 out=E:\main\fpga-hdml\build\dashboard-board-live-loop
```

Marker file:

```text
build/dashboard-board-live-loop/dashboard_board_live_loop.marker.txt
```

Receiver deployment evidence:

```text
ONE_SHOT_HTTP_SERVED bytes=19008
/tmp/fb_video_udp_receiver: OK
CONTROL_FIFO_READY path=/tmp/video_ctl
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=5 timeout_sec=180 control=/tmp/video_ctl effect=none
```

Dashboard evidence:

```text
ACTION_OK action=start-stream ... HDMI_CAPTURE_OK image=build\dashboard-board-live-loop\hdmi-capture\latest.png
capture_status=ok
capture_profile=non-black
image_exists=true
```

Sender evidence:

```text
DEMO_VIDEO_SEND_OK frames=5 packets=6000 target=192.168.1.10:5005
```

Receiver evidence:

```text
VIDEO_UDP_FRAME_WRITTEN frame_id=0 frames=1 packets=1200 dropped=0 skipped=0 effect=none
VIDEO_UDP_FRAME_WRITTEN frame_id=1 frames=2 packets=2400 dropped=0 skipped=0 effect=none
VIDEO_UDP_FRAME_WRITTEN frame_id=2 frames=3 packets=3600 dropped=0 skipped=0 effect=none
VIDEO_UDP_FRAME_WRITTEN frame_id=3 frames=4 packets=4800 dropped=0 skipped=0 effect=none
VIDEO_UDP_FRAME_WRITTEN frame_id=4 frames=5 packets=6000 dropped=0 skipped=0 effect=none
VIDEO_UDP_RECEIVER_DONE frames=5 skipped=0 packets=6000 dropped=0
```

Ethernet counters after the stream:

```text
RX packets:55802 errors:0 dropped:0 overruns:0 frame:0
TX packets:879 errors:0 dropped:0 overruns:0 carrier:0
```

HDMI capture evidence:

```text
validation_profile=non-black
selected_index=1
selected_backend=dshow
status=pass
mean_luma=136.39
image=build\dashboard-board-live-loop\hdmi-capture\latest.png
```

The captured image was visually inspected and shows the generated demo frame:
a bright gradient background with a PIP-style checker block in the upper-left
area.

## Board Action

Ran a Linux userspace receiver from `/tmp`, sent five generated UDP frames from
the PC through the dashboard, and captured HDMI output.

No Vivado rebuild, PetaLinux rebuild, JTAG programming, QSPI, NAND, eMMC, or
other board flash write was performed.

## Result

PASSED. The project now has a displayable dashboard-driven closed loop:
Dashboard `start-stream` caused visible non-black HDMI output generated from PC
UDP frames through the connected Zynq board.

## Residual Risks

- The output preview is action-triggered HDMI capture, not continuous live
  video.
- Pause/resume controls were not exercised in this cycle, although
  `/tmp/video_ctl` was created and ready.
- Runtime effect switching is still not part of the live dashboard loop.
- The helper restarts the dashboard process and stops stale demo senders to keep
  the test deterministic.
