---
name: zynq7020-pipeline
description: Orchestrate the repository-local XC7Z020 end-to-end MVP workflow using project skills. Use for full pipeline requests spanning environment validation, board-profile selection, Vivado RTL build, timing and DRC gates, JTAG programming, connected-board verification, and reproducible build reports.
---

# Zynq-7020 Pipeline

Run the shortest safe path in this order:

1. Read `docs/environment-baseline.md`. If it exists and none of its
   invalidation conditions are met, trust the baseline and skip environment
   probing. Otherwise load `../zynq7020-environment/SKILL.md` and probe tools,
   USB, UART, and JTAG; after a successful probe, update the baseline.
2. Identify the exact carrier board and create a verified profile under
   `boards/`. Stop rather than guessing pins.
3. Load `../zynq7020-vivado/SKILL.md` and build the shortest verified example:
   `examples/led-static` when no board clock is verified, `examples/led-chaser`
   after clock and LED constraints are verified, `examples/video-pip` only for
   the PL-only side demo, or `examples/eth-ps-pl-hdmi-pass-through` for the
   network-video pass-through path.
4. Require clean DRC and non-negative setup slack.
5. Load `../zynq7020-hardware/SKILL.md`, select the working JTAG backend, and
   program SRAM.
6. Confirm the LED sequence physically and preserve all reports.

Use `scripts/run-mvp.ps1 -BoardProfile <path> -Backend auto` after the board
profile and JTAG driver are ready. Pass `-Example led-static` only when the
board profile has no verified clock yet.

For the PL-only video side demo, run xsim first and require all relevant stage
markers before building or programming:

```text
STAGE1_TIMING_AND_PATTERN_OK
STAGE2_PIP_OK
STAGE3_EFFECT_PIPE_OK
STAGE4_BUTTON_CONTROL_OK
SIM_OK
```

For the active network-video path, the accepted direction is confirmed by
hardware evidence (2026-06-29):

```text
PC UDP RGB888 -> Linux userspace socket receiver -> DDR framebuffer
-> VDMA MM2S -> HDMI
```

Route gate result: PASSED.

```text
The official Smart_ZYNQ_SP2_LINUX_ALL_TEST image boots from a FAT32 TF card.
Linux macb driver brings up eth0 at 1000/Full with RX errors=0. PC ping
192.168.1.10 = 4/4, 0% loss. The hand-written baremetal RGMII bridge is
retired as a dead end; its RX failure was the bridge implementation, not the
physical layer. See docs/reports/tf-card-linux-ping-2026-06-29.md.
```

Verified Linux boot path (for reference when the board needs to be brought up
for network-video work):

```text
1. Format TF card: 1GB FAT32 partition (Windows does not offer FAT32 above 32GB).
2. Copy BOOT.BIN + image.ub from Smart_ZYNQ_SP2_LINUX_ALL_TEST to the partition.
3. Set board DIP switch to SD boot, insert card, press POR RST.
4. UART (COM16, CH340, 115200) prints U-Boot then Linux boot.
5. Login as root (no password) via UART.
6. ifconfig eth0 192.168.1.10 netmask 255.255.255.0 up  (no DHCP on direct link).
7. Clear stale PC ARP (arp -d 192.168.1.10) — Linux MAC differs from baremetal.
8. ping 192.168.1.10 from PC.
```

Verified PetaLinux build path for the active VDMA HDMI image (2026-06-30):

```text
1. Build or rebuild examples/eth-ps-pl-hdmi-pass-through with:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1
2. Require STAGE1_VDMA_BOARD_BUILD_OK, non-negative WNS, and DRC with no errors.
3. Inspect the HDF if device-tree generation fails. The VDMA interrupts must
   terminate at processing_system7_0/IRQ_F2P. In the verified design:
   axi_vdma_0/mm2s_introut -> vdma_irq_concat/In0
   axi_vdma_0/s2mm_introut -> vdma_irq_concat/In1
   vdma_irq_concat/dout -> processing_system7_0/IRQ_F2P[15:0]
4. Use the Ubuntu 18.04 chroot at /opt/chroots/ubuntu18-petalinux2018, not
   direct Ubuntu 22.04, for PetaLinux 2018.3 full image builds.
5. Re-import the HDF, run petalinux-build, then package:
   petalinux-package --boot --fsbl images/linux/zynq_fsbl.elf --fpga <bit> --u-boot images/linux/u-boot.elf --force -o images/linux/BOOT.BIN
6. Copy BOOT.BIN and image.ub to the ZYNQBOOT FAT32 TF-card partition and
   verify hashes before booting the board.
```

Verified project-image boot/probe path (2026-06-30):

```text
1. Boot the generated project image from the TF card.
2. If no new UART output appears, send Enter on COM16; an already-booted board
   may be sitting at:
   vdma-hdmi-minimal-bionic login:
3. Log in as root/root for the generated PetaLinux image.
4. Configure direct-link Ethernet when DHCP is absent:
   ifconfig eth0 192.168.1.10 netmask 255.255.255.0 up
5. Clear stale PC ARP and ping 192.168.1.10 from the PC.
6. Require 4/4 ping before continuing video work.
7. Confirm VDMA probe:
   dmesg | grep -i vdma
   readlink /sys/bus/platform/devices/43000000.dma/driver
8. Confirm whether Linux exposes a display node:
   ls -l /dev/dri /dev/fb* 2>&1
```

Historical result before the fixed-mode connector cycle:

```text
Boot/probe PASSED: Linux boots, eth0 links at 1000/Full, PC ping is 4/4 with
0% loss, and 43000000.dma binds to xilinx-vdma.

Display output follow-up (2026-06-30):
/dev/dri/card0 now exists after enabling CONFIG_DRM_XLNX and
CONFIG_DRM_XLNX_PL_DISP and adding an xlnx,pl-disp DT node. HDMI capture still
shows stable 800x600 color bars. The path is not yet Linux-controllable:
/dev/fb* is absent, card0 has no status/modes/enabled connector files, and
dmesg reports "[drm] Cannot find any crtc or sizes".
```

Verified PetaLinux PL-display overlay path (2026-06-30):

```text
1. Apply the repository overlay to the WSL PetaLinux project:
   rtk wsl -d Ubuntu-22.04 -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/apply-overlay.sh /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic
2. If kernel config fragments do not refresh, force kernel config metadata:
   rtk wsl -d Ubuntu-22.04 -u root -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/run-command-in-chroot.sh /opt/chroots/ubuntu18-petalinux2018 /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic bash -lc 'source /opt/petalinux-v2018.3/components/yocto/source/layers/core/oe-init-build-env build >/tmp/oe-init.log && bitbake virtual/kernel -c kernel_configme -f'
3. Build in the verified Ubuntu 18.04 chroot:
   rtk wsl -d Ubuntu-22.04 -u root -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/build-in-chroot.sh /opt/chroots/ubuntu18-petalinux2018 /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic /mnt/e/main/fpga-hdml/build/hdmi-linux-display-stack
4. Verify generated artifacts before board update:
   - kernel build .config has CONFIG_DRM_XLNX=y and CONFIG_DRM_XLNX_PL_DISP=y
   - decompiled system.dtb contains drm-pl-disp-drv compatible "xlnx,pl-disp"
   - image.ub hash is recorded in the cycle report
5. If the TF card is in the board, update image.ub without removing it:
   - serve build/hdmi-linux-display-stack/image.ub from the PC on 192.168.1.2
   - board wget downloads to /tmp/image.ub.new
   - board verifies sha256, backs up /run/media/mmcblk0p1/image.ub, copies the
     new image, syncs, and reboots
6. After reboot, require:
   - Linux kernel build number changed
   - /dev/dri/card0 exists
   - dmesg shows xilinx-vdma probe and xlnx-pl-disp probe
   - current known blocker is recorded if no connector/modes exist
```

Verified fixed-mode Linux HDMI framebuffer path (preferred, 2026-06-30):

```text
1. Apply software/petalinux/hdmi-linux-display-stack/apply-overlay.sh.
   The overlay installs the Xilinx fixed-HDMI component, OF graph, and a CMA
   reservation inside the board's VDMA-visible DDR window.
2. Build with software/petalinux/hdmi-linux-display-stack/build-in-chroot.sh.
3. Verify the kernel map contains xlnx_fixed_hdmi_driver_init and the final DT
   contains fixed-hdmi plus the CMA reservation. Mode and pixel-format values
   must match docs/project-roadmap.md and board timing must match
   docs/boards/hellofpga-smart-zynq-sl.md.
4. Update TF-card image.ub through the running board only after SHA-256
   verification and retaining the prior image as a recovery copy.
5. After reboot, require:
   - /dev/dri/card0 and /dev/fb0
   - connector status connected
   - connector mode matching docs/project-roadmap.md
   - VDMA start address inside the board DDR window
   - no VDMA decode error or atomic flip timeout
6. Write a deterministic raw frame to /dev/fb0.
7. Capture HDMI with tools/capture_hdmi.py using the validation profile that
   matches the test frame. Require HDMI_CAPTURE_OK.

Verified outcome:
Linux framebuffer console and userspace raw-frame writes both reached physical
HDMI. The first failed probe placed CMA above the official VDMA DDR decode
window; the preferred path fixes that in device tree rather than using
userspace /dev/mem or changing PL.
```

Verified Linux UDP-to-HDMI pass-through path (preferred for stage-1 closure,
2026-06-30):

```text
1. Build and test the Linux receiver:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\eth_pass_through\scripts\build-linux-receiver-wsl.ps1
2. Serve build/ethernet-video-userspace-receiver/ from the PC over HTTP on
   the direct-link interface, then download fb_video_udp_receiver to /tmp on
   the board and verify SHA-256.
3. Start the receiver from the board UART shell:
   /tmp/fb_video_udp_receiver --frames 1 --timeout-sec 60 > /tmp/fb_video_udp_receiver.log 2>&1 &
4. Send a deterministic RGB frame from the PC:
   rtk powershell.exe -NoProfile -Command "python .\tools\send_video_udp.py 192.168.1.10 --pattern rgb-stripes --frames 1 --fps 1 --payload 1200 --inter-packet-us 200"
5. Require the board log to contain:
   VIDEO_UDP_FRAME_WRITTEN frame_id=0 frames=1 packets=1200 dropped=0
   VIDEO_UDP_RECEIVER_DONE frames=1 packets=1200 dropped=0
6. Capture HDMI with tools/capture_hdmi.py using validation-profile
   rgb-stripes and require HDMI_CAPTURE_OK.
```

Verified outcome:
The stage-1 network-video pass-through MVP is closed. The receiver must map
protocol RGB888 into the framebuffer channel byte order reported by
FBIOGET_VSCREENINFO; on the verified image /dev/fb0 is 24bpp with red byte 2,
green byte 1, and blue byte 0.

Verified sustained low-FPS stream path (preferred when checking repeated frame
updates, 2026-06-30):

```text
1. Run the integrated probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_sustained_stream_probe.ps1 -Frames 5 -Fps 1 -InterPacketUs 200
2. The helper builds and host-tests the receiver, deploys it through a
   one-shot PowerShell/.NET file server, starts it from UART, sends five
   rgb-stripes frames, reads board logs, and captures HDMI.
3. Require:
   VIDEO_UDP_RECEIVER_TEST_OK
   VIDEO_FB_COPY_TEST_OK
   /tmp/fb_video_udp_receiver: OK
   VIDEO_UDP_RECEIVER_DONE frames=5 packets=6000 dropped=0
   HDMI_CAPTURE_OK
   SUSTAINED_STREAM_PROBE_OK
```

Verified outcome:
The single-frame route was extended to five paced frames with no receiver
drops. This proves repeated receiver/framebuffer updates, but not high-FPS
throughput or visual motion.

Verified UART receiver-control path (preferred when checking fallback control,
2026-06-30):

```text
1. Run the integrated probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_uart_control_probe.ps1
2. The helper builds and host-tests the receiver, deploys it through a
   one-shot PowerShell/.NET file server, starts it with --control-fifo
   /tmp/video_ctl, sends UART shell commands, sends UDP frames, and captures
   HDMI.
3. Require:
   VIDEO_CONTROL_TEST_OK
   CONTROL_FIFO_READY path=/tmp/video_ctl
   CONTROL_PAUSED
   VIDEO_UDP_FRAME_SKIPPED_PAUSED frame_id=100
   CONTROL_RESUMED
   CONTROL_STATUS paused=0
   VIDEO_UDP_FRAME_WRITTEN frame_id=101
   VIDEO_UDP_RECEIVER_DONE frames=1 skipped=1 packets=2400 dropped=0
   HDMI_CAPTURE_OK
   UART_CONTROL_PROBE_OK
```

Verified outcome:
The receiver can be controlled from the UART shell without stopping UDP receive
or breaking HDMI output. The FIFO is the current fallback transport; TCP/UDP
control remains a later transport for the same command semantics.

Verified first board-side effect path (preferred when checking the software
effect stage, 2026-06-30):

```text
1. Run the integrated probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_first_effect_probe.ps1
2. The helper builds and host-tests the receiver, deploys it through a
   one-shot PowerShell/.NET file server, starts it with --effect invert, sends
   a deterministic generated rgb-stripes UDP frame, and captures HDMI.
3. Require:
   VIDEO_EFFECT_TEST_OK
   /tmp/fb_video_udp_receiver: OK
   VIDEO_UDP_LINUX_RECEIVER_READY ... effect=invert
   VIDEO_UDP_FRAME_WRITTEN frame_id=200 ... effect=invert
   VIDEO_UDP_RECEIVER_DONE frames=1 skipped=0 packets=1200 dropped=0
   HDMI_CAPTURE_OK with validation-profile inverted-rgb-stripes
   FIRST_EFFECT_PROBE_OK
```

Verified outcome:
The board applies RGB invert to generated PC UDP input. This path does not use
camera/webcam input; HDMI capture is only output verification.

Verified PC dashboard scaffold path (preferred for dashboard layout checks,
2026-07-01):

```text
1. Run the self-test:
   rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\visual-dashboard-scaffold"
2. Require:
   DASHBOARD_SCAFFOLD_SELF_TEST_OK
3. The self-test proves:
   - input-preview panel exists
   - FPGA-output preview panel exists
   - function-control panel exists
   - camera/webcam input is disabled
   - custom file input is disabled/deferred
```

Verified outcome:
The dashboard scaffold can run locally without external Python UI dependencies.
It is a PC-side console, not board firmware.

Verified fixed demo-video sender path (preferred for PC generated-video input,
2026-07-01):

```text
1. Run the self-test:
   rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\fixed-demo-video-sender"
2. Require:
   DEMO_VIDEO_SENDER_SELF_TEST_OK
3. The self-test proves:
   - generated RGB888 frame size is correct
   - multiple generated frames differ
   - one generated frame packetizes through localhost UDP loopback
   - all expected packets and payload bytes are received
   - camera/webcam input is disabled
   - custom-file input is disabled/deferred
4. To send the generated stream to the board receiver after it is running:
   rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py 192.168.1.10 --frames 5 --fps 1"
```

Verified outcome:
The dashboard MVP has a deterministic PC generated-video source that reuses the
existing UDP frame protocol. It does not use camera/webcam input, and
user-selectable custom input files remain deferred after MVP.

Verified dashboard control-integration path (preferred for PC control-surface
checks, 2026-07-01):

```text
1. Run the self-test:
   rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-control-integration"
2. Require:
   DASHBOARD_SCAFFOLD_SELF_TEST_OK
   DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
3. The self-test proves:
   - dashboard HTML/state/previews load
   - control buttons expose action hooks
   - /api/actions returns sender, UART/FIFO, and effect action semantics
   - /api/action accepts six dry-run actions
   - action logs record the expected command semantics
   - camera/webcam input is disabled
   - custom-file input is disabled/deferred
```

Verified outcome:
The dashboard has a tested dry-run control surface. This is not live board
control yet; it is the stable PC-side API surface that later binds to the real
sender subprocess and UART/FIFO transport.

Verified dashboard minimal live-control path (preferred for local dashboard
checks, 2026-07-01):

```text
1. Run the self-test:
   rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-live-minimal-controls"
2. Require:
   DASHBOARD_MINIMAL_UI_SELF_TEST_OK
   DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
3. The self-test proves:
   - dashboard HTML is plain functional UI, with no gradient or box-shadow
   - start-stream launches the real demo sender process
   - localhost receives a real ZVID UDP packet from the sender
   - stop-stream terminates the dashboard-owned sender process
   - UART actions fail explicitly with UART_NOT_CONFIGURED when no UART is set
   - camera/webcam input is disabled
   - custom-file input is disabled/deferred
4. Run locally:
   rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765"
5. If the UART receiver FIFO is ready and the serial port should be used, keep
   the default COM16 or pass:
   --uart-port COM16 --control-fifo /tmp/video_ctl
6. If the serial port must not be touched, pass:
   --uart-disabled
```

Verified outcome:
The dashboard is no longer a decorative dry-run panel. It is a minimal PC-side
control panel whose stream buttons operate a real local sender process. UART
buttons are wired to the existing helper but still require a running board
receiver and `/tmp/video_ctl`; deploying/starting that receiver remains the
next board-live cycle.

Verified dashboard HDMI-capture binding path (preferred for checking output
preview wiring, 2026-07-01):

```text
1. Run the deterministic dashboard self-test:
   rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-hdmi-capture-binding"
2. Require:
   DASHBOARD_SCAFFOLD_SELF_TEST_OK
   DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
   DASHBOARD_MINIMAL_UI_SELF_TEST_OK
   DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
3. Run a preview capture:
   rtk powershell.exe -NoProfile -Command "python .\tools\capture_hdmi.py --device auto --backend dshow --width 800 --height 600 --frames 20 --validation-profile none --out-dir build\dashboard-hdmi-capture-binding\hdmi-capture"
4. Require:
   HDMI_CAPTURE_OK
```

Verified outcome:
The dashboard can call HDMI capture from `start-stream` and `capture-output`,
and the output panel refreshes the latest capture image. The 2026-07-01 live
preview capture opened DirectShow device index 0 and wrote `latest.png`, but
the captured frame was near black. Treat that as a board receiver/output
readiness issue, not a dashboard capture wiring issue.

Timeout fix:
If dashboard `start-stream` reports `HDMI_CAPTURE_TIMEOUT`, use the version
after `docs/reports/dashboard-hdmi-capture-timeout-fix.md`. The verified
dashboard path uses a capture timeout of at least 90 seconds and 8 preview
frames by default. Retest returned `HDMI_CAPTURE_OK`, `capture_status=ok`, and
`image_exists=true`; the captured frame was still near black, so the remaining
problem was board output readiness.

Historical live dashboard pass-through preview path (superseded by the
color-block classification path, 2026-07-01):

```text
1. Run the helper:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-live-pass-through-preview -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -Frames 12 -Fps 2 -InterPacketUs 200
2. Require:
   build/dashboard-live-pass-through-preview/dashboard_board_live_loop.marker.txt
   contains DASHBOARD_BOARD_LIVE_LOOP_OK frames=12 written=12
   mjpeg_frames=80 mjpeg_unique=26
3. Require receiver evidence:
   CONTROL_FIFO_READY path=/tmp/video_ctl
   VIDEO_UDP_LINUX_RECEIVER_READY
   twelve VIDEO_UDP_FRAME_WRITTEN markers
   VIDEO_UDP_RECEIVER_DONE frames=12 skipped=0 packets=14400 dropped=0
4. Require Dashboard evidence:
   ACTION_OK action=start-stream ... HDMI_RETURN_STREAM_READY
   input_source.preview_matches_sender_source=true
   output_preview.live_stream_endpoint=/api/output-stream.mjpeg
   output_preview.semantic names still capture as manual fallback
5. Require live HDMI return evidence:
   tools/probe_mjpeg_stream.py reads /api/output-stream.mjpeg
   MJPEG_STREAM_PROBE_OK
   returned frame hashes contain at least two unique values
```

Verified outcome:
The connected board displayed the generated PC demo stream through HDMI, the
Dashboard served the exact generated UDP source as its input preview, and the
right panel consumed a live MJPEG stream from the HDMI return adapter. The
saved MJPEG frames showed visible PIP/checker motion. This path is kept as
recovery context only; use the color-block classification path below for new
closed-loop checks. It runs the receiver from `/tmp` and does not write board
flash.

Verified color-block live dashboard loop and UART audit path (preferred for
displayable closed-loop checks, 2026-07-01):

```text
1. Run the finite helper:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\finite-loop -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200
2. Require:
   build/dashboard-color-block-loop-and-uart-audit/finite-loop/dashboard_board_live_loop.marker.txt
   contains DASHBOARD_BOARD_LIVE_LOOP_OK mode=finite
   receiver_frames=12 sender_frames=12 written=12
   mjpeg_frames=80 mjpeg_unique=8 mjpeg_colors=8
   color_names=black,blue,cyan,green,magenta,red,white,yellow
3. Require sender evidence:
   demo_frame=0 color=red
   demo_frame=1 color=green
   demo_frame=2 color=blue
   DEMO_VIDEO_SEND_OK frames=12 packets=14400 target=192.168.1.10:5005
4. Require receiver evidence:
   CONTROL_FIFO_READY path=/tmp/video_ctl
   VIDEO_UDP_LINUX_RECEIVER_READY ... effect=none
   twelve VIDEO_UDP_FRAME_WRITTEN markers
   VIDEO_UDP_RECEIVER_DONE frames=12 skipped=0 packets=14400 dropped=0
5. Require live HDMI return evidence:
   tools/probe_mjpeg_stream.py reads /api/output-stream.mjpeg
   MJPEG_STREAM_PROBE_OK frames=80 unique=8
   colors=black,blue,cyan,green,magenta,red,white,yellow
6. To leave a live demo running, add -KeepRunning and use a live-demo out dir:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\live-demo -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 40 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200 -KeepRunning
7. To audit UART controls through the dashboard, POST:
   pause-receiver, receiver-status, resume-receiver, receiver-status
   and require CONTROL_PAUSED, CONTROL_STATUS paused=1, CONTROL_RESUMED,
   and CONTROL_STATUS paused=0 in the Dashboard action responses.
```

Verified outcome:
The source is now full-screen sequential color blocks instead of a decorative
PIP/checker pattern. The finite board loop proves the PC sender, Linux receiver,
/dev/fb0, HDMI output, HDMI capture adapter, and Dashboard right-panel MJPEG
stream carry the same color-block sequence with `effect=none` and dropped=0.
The small black blinking overlay seen during testing was the Linux framebuffer
console cursor; the helper disables it before starting the receiver. Dashboard
UART pause/resume/status actions now return real receiver log markers from the
running board receiver.

Verified unified pass-through validator calibration path (required before any
future faithful live pass-through claim, 2026-07-01):

```text
1. Run the calibration:
   rtk powershell.exe -NoProfile -Command "python .\tools\validate_passthrough_trace.py --calibration --out-dir build\unified-passthrough-validator-calibration"
2. Require:
   UNIFIED_PASSTHROUGH_VALIDATOR_CALIBRATION_OK
3. Require the calibration summary booleans:
   known_good_pass=1
   known_bad_black_fail=1
   known_bad_wrong_order_fail=1
   known_bad_missing_frame_fail=1
   known_bad_wrong_content_fail=1
   known_bad_latency_fail=1
4. Use docs/protocols/unified-passthrough-trace.md for the trace schema.
5. In the next hardware cycle, the runner must emit a decoded trace and call:
   python .\tools\validate_passthrough_trace.py <trace.json> --result-json <result.json>
```

Verified outcome:
The reusable validator is calibrated against synthetic known-good and known-bad
traces. It checks frame_id correspondence, drop rate, latency, ordering,
content identity, black/no-frame rejection, and optional image fixture hashes.
This calibration is PC-side only; it does not claim board pass-through at
15 fps. It exists so the next hardware cycle cannot introduce a new ad-hoc
pass condition.

Verified unified pass-through validator boundary/order regression path
(preferred after calibration and before using the validator as a hardware pass
gate, 2026-07-01):

```text
1. Run the edge regression:
   rtk powershell.exe -NoProfile -Command "python .\tools\validate_passthrough_trace.py --boundary-order-regression --out-dir build\unified-validator-boundary-order-fix"
2. Require:
   UNIFIED_VALIDATOR_BOUNDARY_ORDER_FIX_OK
3. Require the measured fields:
   calibration_status=pass
   boundary_19_of_20_status=pass
   boundary_19_of_20_drop_rate=0.05
   unmatched_high_then_lower_status=fail
   unmatched_high_then_lower_has_unmatched_capture=1
   unmatched_high_then_lower_has_frame_order_violation=0
   wrong_order_status=fail
   wrong_order_has_frame_order_violation=1
4. In the next hardware cycle, do not rely only on runner-decoded metadata.
   Require independent captured-image evidence with `require_image_paths=true`
   or equivalent offline re-decode before claiming faithful pass-through.
```

Verified outcome:
The validator now handles the exact 19/20 boundary with integer-count
`drop_rate=0.05`, rejects unmatched captures without inventing a later order
violation, and still rejects real wrong-order traces. This path is PC-side
only; it repairs the validator gate before the next hardware run.

Verified unified 15 fps image-evidence pass-through path (preferred for
faithful board-live closed-loop checks, 2026-07-01):

```text
1. Run the integrated hardware probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_unified_15fps_trace_probe.ps1 -OutDir build\unified-15fps-image-evidence-pass-through -CaptureDevice 1 -CaptureBackend dshow -StreamFps 30 -MjpegFrames 220 -MjpegMinUnique 8 -MjpegMinColors 8 -Frames 30 -WarmupFrames 12 -ValidationStartFrameId 100 -Fps 15 -TraceMaxLatencyMs 1000 -UdpPayload 1200 -HoldRepeats 1 -InterPacketUs 0 -PacketWindowFraction 0.85 -ReceiverSyncMode none -ReceiverPresentFps 15
2. Require receiver/build markers:
   VIDEO_UDP_RECEIVER_TEST_OK
   VIDEO_FB_COPY_TEST_OK
   VIDEO_CONTROL_TEST_OK
   VIDEO_EFFECT_TEST_OK
   LINUX_RECEIVER_BUILD_OK
   VIDEO_UDP_LINUX_RECEIVER_READY ... present_interval_ms=67
   thirty validation VIDEO_UDP_FRAME_WRITTEN ids 100..129
3. Require trace/image markers:
   UNIFIED_TRACE_FROM_MJPEG_OK
   UNIFIED_PASSTHROUGH_TRACE_OK
   UNIFIED_15FPS_IMAGE_EVIDENCE_OK
4. Require final measured fields:
   sender_fps=15
   sent_frames=30
   receiver_written_frames=30
   receiver_dropped_packets=0
   mjpeg_saved_frames>=60
   mjpeg_unique_hashes>=8
   mjpeg_unique_colors>=8
   trace_require_image_paths=1
   trace_image_path_failures=0
   validator_status=pass
   trace_sent_frames=30
   trace_matched_frames>=29
   trace_drop_rate<=0.05
   trace_order_violations=0
   trace_content_mismatches=0
   trace_black_frames=0
```

Verified outcome:
The board-live loop passed with 30 generated validation frames, 30 receiver
writes, dropped=0, 220 saved HDMI MJPEG frames, 47 unique returned image hashes,
8 decoded colors, and a validator trace that decoded all 30 validation frame
IDs from saved JPEGs with `require_image_paths=true`. The receiver must use
`--present-fps 15` for this check so framebuffer writes do not catch up in
bursts that the HDMI/UVC return path can miss. The trace latency threshold is
for the HDMI-UVC/MJPEG evidence path; the passing run measured max
return-path latency of 257.561 ms.

Verified Linux direct-copy network-to-HDMI path (preferred when checking the
Linux userspace transfer chain after the 2026-07-02 review):

```text
1. Run the integrated hardware probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_linux_net_to_hdmi_direct_copy_probe.ps1
2. Require receiver/build markers:
   VIDEO_UDP_RECEIVER_TEST_OK
   VIDEO_FB_COPY_TEST_OK
   VIDEO_CONTROL_TEST_OK
   VIDEO_EFFECT_TEST_OK
   LINUX_RECEIVER_BUILD_OK
   FB_COPY_MODE mode=direct-memcpy
   VIDEO_UDP_LINUX_RECEIVER_READY ... fb_copy_mode=direct-memcpy
3. Require sender evidence:
   sender_wire_format=fb24-native
   sent_frames=30
4. Require receiver evidence:
   thirty validation VIDEO_UDP_FRAME_WRITTEN ids 100..129
   receiver_written_frames=30
   receiver_dropped_packets=0
5. Require trace/image markers:
   UNIFIED_TRACE_FROM_MJPEG_OK
   UNIFIED_PASSTHROUGH_TRACE_OK
   LINUX_NET_TO_HDMI_DIRECT_COPY_OK
6. Require final measured fields:
   receiver_fb_copy_mode=direct-memcpy
   sender_wire_format=fb24-native
   sender_fps=15
   sent_frames=30
   receiver_written_frames=30
   receiver_dropped_packets=0
   receiver_effect=none
   trace_require_image_paths=1
   trace_image_path_failures=0
   validator_status=pass
   trace_sent_frames=30
   trace_matched_frames>=29
   trace_drop_rate<=0.05
   trace_order_violations=0
   trace_content_mismatches=0
   trace_black_frames=0
```

Verified outcome:
The Linux userspace receiver no longer needs a long per-pixel RGB-to-
framebuffer reorder loop for this path. The PC sends framebuffer-native 24bpp
payloads, the receiver writes complete frames to `/dev/fb0` with direct row
memcpy, and HDMI saved-image validation matched 30/30 marker-backed frames
with dropped=0 and max return-path latency 62.382 ms. This is the preferred
Tier 1 response to the 2026-07-02 review's tearing concern. It does not yet
replace fbdev with DRM/KMS page-flip or GStreamer.

Verified DRM/KMS local-motion display pacing path (preferred when isolating
display-side page-flip smoothness after a network-driven DRM run fails):

```text
1. Run the integrated hardware probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_drm_kms_local_motion_pacing_probe.ps1
2. Require build markers:
   VIDEO_UDP_RECEIVER_TEST_OK
   VIDEO_FB_COPY_TEST_OK
   VIDEO_CONTROL_TEST_OK
   VIDEO_EFFECT_TEST_OK
   LINUX_RECEIVER_BUILD_OK
   DRM_KMS_RECEIVER_BUILD_OK
3. Require board display markers:
   VIDEO_DRM_LOCAL_MOTION_READY ... display_backend=drm-kms
   DRM_DUMB_BUFFERS count=2
   120 DRM_PAGE_FLIP_SUBMITTED markers
   120 DRM_PAGE_FLIP_EVENT markers
   VIDEO_DRM_LOCAL_MOTION_DONE ... generated_frames=120
4. Require HDMI tearing validation:
   MOTION_TEARING_VALIDATION_OK
   DRM_KMS_LOCAL_MOTION_PACING_OK
5. Require final measured fields:
   display_backend=drm-kms
   drm_device=/dev/dri/card0
   video_source=board-generated-textured-motion
   fbdev_live_write_used=0
   drm_dumb_buffers=2
   drm_page_flip_calls=120
   drm_vblank_flip_events=120
   generated_frames=120
   motion_content_type=textured-motion
   captured_motion_frames>=120
   tearing_frames=0
   frame_duration_stddev_ms<=4.0
   validator_status=pass
```

Verified outcome:
The board display side can page-flip textured motion through `/dev/dri/card0`
with two DRM dumb buffers and vblank events without using `/dev/fb0` live-screen
mmap writes. The passing run generated 120 board-local textured frames, received
120 vblank page-flip events, captured 255 motion-like HDMI frames, measured
tearing_frames=0, and measured frame_duration_stddev_ms=1.514 from DRM event
timestamps. This is a display-side diagnostic route only; it does not prove that
the PC UDP receive path is smooth.

Verified PetaLinux GStreamer rootfs integration path (preferred before any
GStreamer RTP-to-kmssink route gate, 2026-07-02):

```text
1. Apply the repository overlay to the active PetaLinux project:
   rtk wsl -d Ubuntu-22.04 -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/apply-overlay.sh /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic
2. Build in the verified Ubuntu 18.04 chroot:
   rtk wsl -d Ubuntu-22.04 -u root -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/build-in-chroot.sh /opt/chroots/ubuntu18-petalinux2018 /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic /mnt/e/main/fpga-hdml/build/petalinux-gstreamer-rootfs-integration
3. Require the PetaLinux build log to show all attempted tasks succeeded.
4. Record image.ub and rootfs.manifest SHA-256 hashes.
5. If the TF card is already booted in the board, update image.ub without
   removing the card:
   - serve build/petalinux-gstreamer-rootfs-integration/image.ub from the PC on
     the direct-link interface
   - board wget downloads it to /tmp
   - board verifies SHA-256 before copying it to /run/media/mmcblk0p1/image.ub
   - board backs up the previous image.ub first, syncs, and reboots
6. After reboot, require:
   - /usr/bin/gst-launch-1.0
   - /usr/bin/gst-inspect-1.0
   - gst-launch-1.0 version 1.12.2
   - /dev/dri/card0 and /dev/fb0 still present
7. Probe required elements with gst-inspect-1.0:
   videotestsrc, filesrc, udpsrc, tcpclientsrc, tcpserversrc,
   rtpjitterbuffer, rtpvrawdepay, rtph264depay, videoconvert, videoscale,
   queue, capsfilter, identity, fpsdisplaysink, kmssink, v4l2src, v4l2sink
8. Probe helper tools:
   modetest, v4l2-ctl, yavta
9. Run a cheap smoke pipeline:
   gst-launch-1.0 -q videotestsrc num-buffers=5 ! video/x-raw,width=320,height=240,framerate=5/1 ! videoconvert ! fakesink
10. Treat kmssink presence and KMS caps negotiation as dependency evidence
    only. Do not claim the final RTP/raw-video-to-kmssink route until a later
    route gate validates frame/drop accounting and HDMI return quality.
```

Verified outcome:
The board boots a generated PetaLinux image with GStreamer tools, base/good/bad
plugins, kmssink, DRM/KMS userspace tools, and V4L utilities in the rootfs. The
image update path over board Ethernet passed SHA-256 verification and retained
a TF-card rollback copy. The fakesink GStreamer smoke pipeline passed; kmssink
loaded and negotiated 800x600 KMS caps in a background smoke run. The package
set deliberately excludes gstreamer1.0-plugins-ugly, gstreamer1.0-libav, and
ffmpeg unless license flags are explicitly accepted. Do not use
packagegroup-petalinux-gstreamer on this image; it pulls OMX, which failed to
compile and is not needed for the Zynq-7020 DRM/KMS route.

Withdrawn GStreamer RTP/raw-to-kmssink path (negative evidence, 2026-07-02):

```text
Do not promote or reuse this route. Motion-only validation accepted
black/white cross-frame slicing from kmssink force-modesetting, and the old
dashboard preview was not the actual source.
```

Verified GStreamer dashboard control path (preferred visual console, 2026-07-02):

```text
1. Run the self-test:
   rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-gstreamer-chinese-control"
2. Require:
   DASHBOARD_GSTREAMER_CONTROL_SELF_TEST_OK
   DASHBOARD_CHINESE_UI_SELF_TEST_OK
3. Start the dashboard:
   rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765 --pipeline gstreamer --uart-port COM16 --uart-login-root --uart-password root"
4. Press or POST `start-stream`.
5. Require the action response to show:
   - pipeline.mode=gstreamer
   - pipeline.transport=rtp/jpeg
   - pipeline.sink=fbdevsink
   - GSTREAMER_RECEIVER_STARTED in the UART response
   - a running PC sender PID
6. Require the left panel source mode to be
   latest-actual-gstreamer-source-frame.
7. Capture interval HDMI samples and require preserved color plus motion.
```

Verified outcome:
The browser-visible control console is Chinese-localized and represents the
corrected mature route. The PC tees actual RGB source frames to the left
preview, converts a second branch to I420, encodes JPEG, and sends RFC 2435
RTP. The board depayloads/decodes/scales and writes through fbdevsink.
Connected-board validation measured 12 HDMI samples, 11 unique hashes,
yellow-ball detection in all frames, x_span=283.98, y_span=277.77, and blue
background RGB mean (16.0, 59.1, 75.2).

Verified PL dual-VDMA PIP effect path (preferred for the first PL-side effect,
2026-07-03):

```text
1. Run xsim for examples/eth-ps-pl-hdmi-pass-through:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through
2. Require:
   AXI_FRAMEBUFFER_LINE_READER_OK
   PL_DUAL_VDMA_PIP_CORE_SIM_OK
   SIM_OK
3. Build the VDMA HDMI board bitstream:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1
4. Require:
   STAGE1_VDMA_BOARD_BUILD_OK
   non-negative WNS
   routed DRC errors=0
5. Build the Linux receiver/helper package:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\eth_pass_through\scripts\build-linux-receiver-wsl.ps1
6. Require:
   VDMA_MM2S_CONFIG_BUILD_OK
7. Package a new BOOT.BIN with the updated bitstream and the existing verified
   PetaLinux FSBL/U-Boot. If the board is already booted from TF card, update
   BOOT.BIN over Ethernet only after SHA-256 verification, and retain a
   BOOT.BIN backup on the TF-card boot partition.
8. Reboot and require:
   /dev/fb0 exists
   /dev/dri/card0 exists
   dmesg shows xilinx-vdma, xlnx-pl-disp, and fixed HDMI probes
9. Deploy and run vdma_mm2s_config on the board. It must read FBIOGET_* data
   from /dev/fb0 and program axi_vdma_1 to the same smem_start, stride, hsize,
   and vsize. Require:
   VDMA_MM2S_CONFIGURED
   VDMA_MM2S_STATUS ... halted=0 ... errors=0x000
10. Start the dashboard in GStreamer mode, press or POST start-stream, and
    require a running RTP/JPEG fbdevsink stream.
11. Validate physical HDMI with:
    tools/capture_hdmi.py --validation-profile pip-overlay
    Require HDMI_CAPTURE_OK.
12. Validate the dashboard right-panel return:
    tools/probe_mjpeg_stream.py http://127.0.0.1:8765/api/output-stream.mjpeg
    tools/validate_pip_overlay_frames.py <saved-frame-dir>
    Require MJPEG_STREAM_PROBE_OK and PIP_OVERLAY_FRAMES_OK.
```

Verified outcome:
The first PL-side effect is closed. Linux/GStreamer receives RTP/JPEG and
writes `/dev/fb0`; VDMA0 and VDMA1 read the same DDR framebuffer; PL scales the
second stream into a fixed same-source PIP window and overlays it before HDMI.
Direct HDMI capture passed the PIP validator, and the dashboard-returned MJPEG
stream passed 24/24 saved-frame PIP validation. This path proves PL-side effect
placement, not runtime movement, rotation, arbitrary scaling, or high-fps
transport quality.

Verified controllable PL PIP effect path (preferred for runtime PIP controls,
2026-07-04):

```text
1. Run xsim for examples/eth-ps-pl-hdmi-pass-through:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through
2. Require:
   AXI_FRAMEBUFFER_LINE_READER_OK
   PL_CONTROLLED_PIP_CORE_SIM_OK
   PL_DUAL_VDMA_PIP_CORE_SIM_OK
   SIM_OK
3. Build the VDMA HDMI board bitstream:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1
4. Require:
   STAGE1_VDMA_BOARD_BUILD_OK
   non-negative WNS
   routed DRC errors=0
5. Build the Linux receiver/helper package:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\eth_pass_through\scripts\build-linux-receiver-wsl.ps1 -OutDir build\pl-controlled-pip-effect-pipeline\linux-tools
6. Require:
   VDMA_MM2S_CONFIG_BUILD_OK
   PIP_EFFECT_CTL_BUILD_OK
7. Package a new BOOT.BIN with the updated bitstream and the existing verified
   PetaLinux FSBL/U-Boot. If the board is already booted from TF card, update
   BOOT.BIN over Ethernet only after SHA-256 verification, and retain a
   BOOT.BIN backup on the TF-card boot partition.
8. Reboot and require:
   /dev/fb0 exists
   /dev/dri/card0 exists
   dmesg shows xilinx-vdma, xlnx-pl-disp, and fixed HDMI probes
9. Deploy and run vdma_mm2s_config on the board. It must read FBIOGET_* data
   from /dev/fb0 and program axi_vdma_1 to the same smem_start, stride, hsize,
   and vsize. Require:
   VDMA_MM2S_CONFIGURED
   VDMA_MM2S_STATUS ... halted=0 ... errors=0x000
10. Deploy /tmp/pip_effect_ctl and require:
    PIP_EFFECT_STATUS ... enable=1 ... scale=4 ... x=560 y=420
11. Start the dashboard in GStreamer mode:
    rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765 --pipeline gstreamer --uart-port COM16 --uart-login-root --uart-password root"
12. Press or POST PIP preset actions and require PIP_EFFECT_STATUS readback:
    pip-top-left: x=16 y=16
    pip-bottom-right: x=560 y=420
    pip-large: scale=2 active_w=400 active_h=300
    pip-small: scale=4 active_w=200 active_h=150
    pip-invert: effect=1
    pip-grayscale: effect=2
    pip-bypass: enable=0
13. Press or POST start-stream and require:
    pipeline.mode=gstreamer
    pipeline.transport=rtp/jpeg
    pipeline.sink=fbdevsink
    stream_state=running
    HDMI_RETURN_STREAM_READY endpoint=/api/output-stream.mjpeg
14. Validate physical HDMI:
    - after pip-bypass, tools/capture_hdmi.py --validation-profile pip-overlay
      must fail because pip_white_border pixels=0
    - after pip-bottom-right, the same capture must return HDMI_CAPTURE_OK
15. Validate the dashboard right-panel return:
    tools/probe_mjpeg_stream.py http://127.0.0.1:8765/api/output-stream.mjpeg
    tools/validate_pip_overlay_frames.py <saved-frame-dir>
    Require MJPEG_STREAM_PROBE_OK and PIP_OVERLAY_FRAMES_OK.
```

Verified outcome:
The same-source PL PIP effect is runtime-controllable from the dashboard
through UART and a board-side `/dev/mem` AXI-Lite helper. Buttons update real
PL registers for enable/bypass, position, scale, and small-window color effect.
Physical HDMI capture showed the expected negative/positive transition:
`pip-bypass` removed the PIP border and failed the PIP validator, while
`pip-bottom-right` restored the PIP and passed. The dashboard MJPEG return
also passed 24/24 PIP frame validation. This path proves preset-based runtime
PIP control, not arbitrary sliders, rotation, a kernel driver, or high-fps
transport quality.

Verified low-latency PIP TCP control path (preferred for runtime PIP preset
controls after the controlled-PIP bitstream is already deployed, 2026-07-04):

```text
1. Build the Linux receiver/helper package:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\eth_pass_through\scripts\build-linux-receiver-wsl.ps1 -OutDir build\pip-tcp-control-service\linux-tools
2. Require:
   PIP_EFFECT_CTL_BUILD_OK
   PIP_EFFECT_SERVER_BUILD_OK
3. Deploy /tmp/pip_effect_server to the board over Ethernet and verify its
   SHA-256 against build\pip-tcp-control-service\linux-tools\pip_effect_server.sha256.txt.
4. Start the resident daemon from the board shell:
   /tmp/pip_effect_server --port 5012 > /tmp/pip_effect_server.log 2>&1 &
5. Require:
   PIP_CONTROL_SERVER_READY host=0.0.0.0 port=5012 base=0x43c00000
6. Directly probe from the PC with TCP commands:
   status
   preset top-left
   preset bottom-right
   Require PIP_EFFECT_STATUS and PIP_CONTROL_OK for each command.
7. Start the dashboard with the TCP target:
   rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765 --pipeline gstreamer --uart-port COM16 --uart-login-root --uart-password root --pip-control-host 192.168.1.10 --pip-control-port 5012"
8. Run the latency probe:
   rtk powershell.exe -NoProfile -Command "python .\tools\probe_pip_control_latency.py --url http://127.0.0.1:8765 --repeat 1 --out-dir build\pip-tcp-control-service\dashboard-probe"
9. Require:
   PIP_CONTROL_LATENCY_SUMMARY result=pass
   transports=tcp
   seven ok samples for the top-left, bottom-right, large, small, invert,
   grayscale, and bypass PIP actions
   parsed PIP_EFFECT_STATUS readback for each action
```

Verified outcome:
Runtime PIP preset control no longer pays the per-click UART login/shell/helper
startup cost. The dashboard uses a resident POSIX TCP daemon on the board,
falls back to UART only if TCP is unavailable, and reports control transport,
end-to-end latency, and PL register readback. The passing run measured seven
dashboard PIP actions over TCP with p50=2.184 ms and max=24.1 ms. This path
does not change video transport, HDMI quality, PL logic, or boot persistence.

Verified video bottleneck probe path (preferred before deciding that PL-side
decode is required, 2026-07-04):

```text
1. Run the diagnostic matrix:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_video_bottleneck_probe.ps1 -DurationSec 6 -OutDir build\video-bottleneck-probe
2. Require:
   VIDEO_BOTTLENECK_PROBE_OK
   build\video-bottleneck-probe\video-bottleneck-summary.json
3. Inspect the JPEG matrix:
   - rtp-jpeg-to-fakesink at 5/10/15/30fps
   - rtp-jpeg-to-fbdevsink at 5/10/15/30fps
   - rendered frames, drops, average fps, and /proc-derived gst-launch CPU %
4. For raw/direct-copy contrast, either use the summary's raw reference or run:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_video_bottleneck_probe.ps1 -RunRawDirectCopy -OutDir build\video-bottleneck-probe
5. Treat raw receiver throughput separately from HDMI/MJPEG return validation.
   A raw receiver pass with a return-trace failure is not a full HDMI loop pass.
```

Verified outcome:
The current 320x240 RTP/JPEG path is not proven to be PS-limited at the
dashboard's conservative 5fps setting. The passing measurement reached about
30.50fps into fakesink and about 27.69fps into fbdevsink with no
fpsdisplaysink drops. A live raw 800x600 framebuffer-native receiver contrast
accepted 42 frames / 50400 packets with dropped=0, while its HDMI/MJPEG return
trace failed in that rerun. Before committing to PL-side decode, run the next
probe at higher input resolution or with stricter HDMI-return validation.

Verified `jpegpldec` plugin-skeleton path (preferred entry point for later
GStreamer decoder offload work, 2026-07-04):

```text
1. Build the project-owned GStreamer plugin:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\gstreamer\jpegpldec\build-wsl.ps1 -OutDir build\jpegpldec-plugin-skeleton\plugin
2. Require:
   JPEGPLDEC_PLUGIN_BUILD_OK
   libgstjpegpldec.so is an ARM 32-bit shared object
3. Deploy to the board:
   mkdir -p /tmp/gst-plugins
   wget -O /tmp/gst-plugins/libgstjpegpldec.so http://192.168.1.2:<port>/libgstjpegpldec.so
   sha256sum /tmp/gst-plugins/libgstjpegpldec.so
4. Inspect the plugin:
   GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec.bin gst-inspect-1.0 jpegpldec
5. Require the inspect output to show:
   Filename /tmp/gst-plugins/libgstjpegpldec.so
   Long-name JPEG PL decoder skeleton
   sink caps image/jpeg
   src caps video/x-raw
   Children: software-reference-decoder
6. Replace the board receiver with:
   GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec.bin \
   gst-launch-1.0 -v udpsrc port=5011 caps=... \
     ! rtpjitterbuffer latency=100 drop-on-latency=true \
     ! rtpjpegdepay ! jpegpldec ! videoconvert ! videoscale \
     ! video/x-raw,format=BGR,width=800,height=600 \
     ! fbdevsink device=/dev/fb0 sync=true
7. Require board log caps through:
   GstRtpJPEGDepay -> GstJpegPlDec -> GstJpegDec:software-reference-decoder
   -> GstVideoConvert -> GstVideoScale -> GstFBDEVSink
8. Validate dashboard HDMI return:
   rtk powershell.exe -NoProfile -Command "python .\tools\probe_mjpeg_stream.py 'http://127.0.0.1:8765/api/output-stream.mjpeg' --out-dir build\jpegpldec-plugin-skeleton\mjpeg-probe --frames 90 --min-unique 10 --timeout-sec 20"
9. Require:
   MJPEG_STREAM_PROBE_OK
```

Verified outcome:
The board can load a project-owned GStreamer decoder plugin from `/tmp` and
run the existing RTP/JPEG-to-HDMI path with `jpegpldec` replacing `jpegdec`.
The first `jpegpldec` implementation is a `GstBin` wrapper around the system
`jpegdec` child named `software-reference-decoder`; it proves the replacement
entry point, not PL codec acceleration or latency improvement.

Verified `jpegpldec` PL-probe/profile path (preferred before choosing a PL
decoder offload target, 2026-07-04):

```text
1. Keep the dashboard PC GStreamer sender running, or start an equivalent
   RTP/JPEG sender to 192.168.1.10:5011.
2. Run the integrated probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -OutDir build\jpegpldec-pl-probe-and-profile
3. The helper builds libgstjpegpldec.so, serves it over the PC direct-link
   interface, deploys it to /tmp/gst-plugins on the board, and starts:
   rtpjpegdepay ! jpegpldec probe-mode=pl-probe summary-interval=30
   ! videoconvert ! videoscale ! ... ! fbdevsink
4. Require:
   JPEGPLDEC_PLUGIN_BUILD_OK
   JPEGPLDEC_DEPLOY_INSPECT_DONE
   gst-inspect shows probe-mode, summary-interval, pl-base, and pl-map-size
   JPEGPLDEC_PROFILE_RECEIVER_STARTED
   JPEGPLDEC_PROFILE frames=...
   JPEGPLDEC_PL_PROBE_READY base=0x43c00000
   JPEGPLDEC_PL_PROBE frame=...
   JPEGPLDEC_PL_PROBE_OK
5. When the dashboard is running, also require:
   MJPEG_STREAM_PROBE_OK from /api/output-stream.mjpeg
```

Verified outcome:
`jpegpldec` now provides a stable measurement and PL status-probe point without
changing the external GStreamer caps. The passing run measured steady-state
wrapper timing near 2 ms at the current 320x240 RTP/JPEG input, read live PL
PIP status registers through `/dev/mem`, and kept HDMI return dynamic
(`frames=60 unique=46`). This path proves plugin profiling plus PL
control/status access; it does not prove compressed JPEG data movement through
PL, PL JPEG decode, or latency improvement. Before writing a full PL JPEG
decoder, run this probe at the target source resolution or add a real
PS-to-PL buffer/data probe behind `jpegpldec`.

Verified `jpegpldec` decoded-buffer marker path (preferred quick check before
adding a private DMA-safe PL return path, 2026-07-04):

```text
1. Keep the dashboard PC GStreamer sender running, or start an equivalent
   RTP/JPEG sender to 192.168.1.10:5011.
2. Run:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode pl-buffer-probe -OutDir build\jpegpldec-pl-buffer-datapath-probe
3. The helper builds and deploys libgstjpegpldec.so, moves PL PIP to
   bottom-right, and starts:
   rtpjpegdepay ! jpegpldec probe-mode=pl-buffer-probe summary-interval=30
   ! videoconvert ! videoscale ! ... ! fbdevsink
4. Require:
   JPEGPLDEC_PLUGIN_BUILD_OK
   JPEGPLDEC_DEPLOY_INSPECT_DONE
   JPEGPLDEC_PROFILE_RECEIVER_STARTED
   JPEGPLDEC_BUFFER_PROBE ... result=pass
   JPEGPLDEC_PL_PROBE frame=...
   MJPEG_STREAM_PROBE_OK
   JPEGPLDEC_BUFFER_MARKER_OK
   JPEGPLDEC_PL_PROBE_OK
```

Verified outcome:
The plugin can map decoded I420 buffers, stamp a top-left luma checker, and
the marker is visible in the HDMI-return frames after downstream GStreamer,
framebuffer write, VDMA, PL PIP, and HDMI. The passing run measured
`JPEGPLDEC_BUFFER_MARKER_OK frames=60 pass_frames=60`.

Boundary:
This is not a private `jpegpldec` DMA-safe buffer loopback. It proves marked
data from `jpegpldec` reaches the existing framebuffer -> VDMA -> PL display
path. It does not prove PL direct access to `GstBuffer` memory, cache
flush/invalidate correctness for a shared buffer, PL writeback, or returning a
PL-modified buffer to GStreamer. Those require a new or exposed DMA-safe buffer
path such as AXI DMA/VDMA endpoint plus CMA/dma-buf/driver support.

Verified AXI-Stream DMA probe core simulation path (preferred first hardware
source step before adding an AXI DMA BD endpoint, 2026-07-04):

```text
1. Run xsim for examples/eth-ps-pl-hdmi-pass-through:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through
2. Require existing regression markers:
   AXI_FRAMEBUFFER_LINE_READER_OK
   PL_CONTROLLED_PIP_CORE_SIM_OK
   PL_DUAL_VDMA_PIP_CORE_SIM_OK
3. Require the new probe marker:
   AXIS_DMA_PROBE_CORE_SIM_OK
4. The new source/testbench pair is:
   examples/eth-ps-pl-hdmi-pass-through/rtl/axis_dma_probe_core.v
   examples/eth-ps-pl-hdmi-pass-through/sim/tb_axis_dma_probe_core.v
```

Verified outcome:
The PL data-plane probe core accepts 32-bit AXI4-Stream input, passes packets
through by default, can apply a 32-bit XOR marker to prove payload modification,
and reports frames, beats, bytes, input checksum, and output checksum through
AXI-Lite-visible counters. This is only a simulated PL core. It is not yet a
board DMA endpoint, a Linux coherent/CMA buffer client, a cache-coherency proof,
or a `jpegpldec` GStreamer writeback path.

Verified AXI DMA PL probe endpoint build path (preferred before adding a
Linux DMA client, 2026-07-05):

```text
1. Run xsim for examples/eth-ps-pl-hdmi-pass-through:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example eth-ps-pl-hdmi-pass-through
2. Require:
   AXI_FRAMEBUFFER_LINE_READER_OK
   PL_CONTROLLED_PIP_CORE_SIM_OK
   PL_DUAL_VDMA_PIP_CORE_SIM_OK
   AXIS_DMA_PROBE_CORE_SIM_OK
   SIM_OK
3. Build the stage-1 VDMA board bitstream:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1
4. Require:
   STAGE1_VDMA_BOARD_BUILD_OK
   non-negative WNS
   routed DRC with no Error or Critical Warning
5. Inspect the generated BD handoff and require:
   axi_dma_0
   axis_dma_probe_core_0
   axi_dma_0/M_AXIS_MM2S -> axis_dma_probe_core_0/S_AXIS
   axis_dma_probe_core_0/M_AXIS -> axi_dma_0/S_AXIS_S2MM
   axi_dma_0/M_AXI_MM2S and M_AXI_S2MM mapped through HP0
   axi_dma_0 AXI-Lite at 0x43020000
   axis_dma_probe_core_0 AXI-Lite at 0x43c10000
```

Verified outcome:
The board BD now builds with a generic PS-to-PL-to-PS AXI DMA stream endpoint
around `axis_dma_probe_core`. The passing build produced a bitstream with
WNS=0.245 and no routed DRC Error or Critical Warning. This path proves only
hardware endpoint construction. It does not prove a Linux coherent/CMA buffer
client, `jpegpldec` DMA handoff, cache coherency, PL writeback to GStreamer,
or board runtime behavior.

Verified `jpegpl_dma_probe` kernel client build path (preferred Linux-side
source step before board runtime DMA loopback, 2026-07-05):

```text
1. Build the kernel DMA client and userspace test tool:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\kernel\jpegpl_dma_probe\build-wsl.ps1 -OutDir build\jpegpl-dma-probe-kernel-client
2. Require:
   JPEGPL_DMA_PROBE_TEST_SELF_TEST_OK
   JPEGPL_DMA_PROBE_CLIENT_BUILD_OK
3. Require generated artifacts:
   build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe.ko
   build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe_test
```

Verified outcome:
The Linux-side probe client now compiles against the current PetaLinux 2018.3
Linux 4.14 build tree. The module exposes `/dev/jpegpl_dma_probe` through a
misc device, requests DMAengine `tx`/`rx` channels, and uses
`dmam_alloc_coherent` buffers for the future AXI DMA loopback. This path proves
source/build feasibility only. It does not prove device-tree binding, module
load, runtime DMA, cache coherency on hardware, real `jpegpldec` frames, or
GStreamer writeback.

Verified `jpegpldec` PS-to-PL decoded-buffer probe path (preferred runtime
cache/data-plane gate before PL writeback, 2026-07-05):

```text
1. Run the integrated connected-board probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode dma-probe -SummaryInterval 10 -Frames 60 -Fps 5 -OutDir build\jpegpldec-dma-buffer-probe
2. Require the standalone full-frame precheck:
   JPEGPL_DMA_PROBE_TEST_OK length=115200
3. Require the GStreamer profile and no DMA failures:
   JPEGPLDEC_PROFILE frames=60 mode=dma-probe
   JPEGPLDEC_DMA_PROBE ... bytes=115200 chunks=8 ... result=pass
4. Require PL counters after the run:
   PL_DMA_FRAMES=0x000001E0
   PL_DMA_BYTES=0x00697800
   PL_DMA_LAST_FRAME_BYTES=0x0000021C
5. Require dynamic HDMI validation and the final marker:
   HDMI_BALL_MOTION_OK
   JPEGPLDEC_PL_PROBE_OK
```

Verified outcome:
The existing external RTP/JPEG pipeline keeps `rtpjpegdepay ! jpegpldec !
videoconvert ! videoscale ! fbdevsink`. Inside `jpegpldec`, every decoded I420
buffer crosses the real coherent AXI DMA MM2S -> PL probe -> S2MM path. The
14-bit DMA BTT limit is contained inside the kernel ioctl as eight transactions
per logical frame. Sixty logical frames produced 480 PL packets and 6,912,000
bytes with zero reported mismatch; HDMI validation saw 300 samples, 121 unique
hashes, and 270.141 pixels of ball motion. This clears the cache/data-plane
gate for PL writeback. It does not yet replace the downstream GstBuffer with
the PL-returned data.

Verified `jpegpldec` PL-returned GstBuffer writeback path (preferred copy-back
gate before adding useful PL pixel modification, 2026-07-05):

```text
1. Run the connected-board writeback probe:
   rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode dma-writeback -SummaryInterval 10 -Frames 60 -Fps 5 -OutDir build\jpegpldec-dma-writeback
2. Require the standalone full-frame precheck:
   JPEGPL_DMA_PROBE_TEST_OK length=115200
3. Require writeback logs and profile:
   JPEGPLDEC_DMA_WRITEBACK ... stamp=top-left-i420-luma-checker-via-dma ... result=pass
   JPEGPLDEC_PROFILE frames=60 mode=dma-writeback
4. Require PL counters:
   PL_DMA_FRAMES=0x000001E0
   PL_DMA_BYTES=0x00697800
   PL_DMA_LAST_FRAME_BYTES=0x0000021C
5. Require HDMI-visible writeback marker evidence:
   JPEGPLDEC_BUFFER_MARKER_OK
```

Verified outcome:
`jpegpldec` now reconnects the PS-to-PL-to-PS returned raw bytes into the
downstream GstBuffer through a copy-back writeback path. The plugin uses a
staging I420 copy to avoid pre-modifying the original GstBuffer, stamps a
deterministic luma checker before DMA, and copies the coherent RX result into
the writable GstBuffer. The passing run processed 60 logical frames, recorded
480 PL DMA transactions and 6,912,000 bytes, and saw the writeback marker on
HDMI-return frames. This is not zero-copy, not PL-generated pixel modification,
and not JPEG entropy decode acceleration.

Do not resume hand-written baremetal RGMII bridge work. The Linux route is
confirmed; future network-video work builds on Linux sockets, not baremetal lwIP.
