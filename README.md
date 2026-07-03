# Zynq-7020 Network Video Effects System

This repository contains a project-local Codex skills workflow for an XC7Z020
board. Project-specific skills live under `skills/`; do not install them into
the user-level Codex skills directory.

## Project Direction

The target system is:

```text
PC video stream -> Ethernet -> Zynq PS/DDR -> PL video effects -> HDMI output
PC control      -> UART fallback -> board control endpoint -> PL registers
```

The MVP keeps USB-JTAG as the reliable development and recovery path. Replacing
the downloader, USB control, and local cables with Ethernet/LAN control is a
post-MVP milestone, not part of the first working network-video loop.

Route document:

```text
docs/project-roadmap.md
```

## Current MVP

The TF-card Linux route gate has passed. The current first-stage path is:

```text
PC UDP RGB888 -> Linux userspace socket receiver -> DDR framebuffer
-> VDMA MM2S -> HDMI
```

The official Smart_ZYNQ_SP2_LINUX_ALL_TEST image boots from TF card and can be
pinged by the PC at `192.168.1.10` with 0% loss. The hand-written baremetal
RGMII bridge is retired as a dead end; future network-video work uses Linux
sockets.

The verified foundation path remains:

```text
probe Windows Xilinx tools and USB
-> build a Vivado 2018.3 bitstream in WSL
-> scan the connected XC7Z020 over Xilinx hw_server/XSCT
-> program the bitstream to PL SRAM
-> write run evidence under build/reports
```

The connected target reports:

```text
Cable: HelloFpga JTAG-JT2 26SA093A
Target: xc7z020
```

The active board profile is:

```text
boards/hellofpga-smart-zynq-sl-7020.tcl
```

The active pass-through implementation target is:

```text
Example: examples/eth-ps-pl-hdmi-pass-through
Part: xc7z020clg484-1
Input: PC UDP frames, 800x600 RGB888, port 5005
Buffer: PS DDR framebuffer
Output: official VDMA-style 800x600 HDMI path
Status: stage-1 UDP framebuffer HDMI pass-through passed
Control: UART fallback FIFO pause/resume/status passed
Effect: first board-side RGB invert effect passed with generated PC input
Dashboard: GStreamer visual control console is now the preferred UI route. It
  starts the board GStreamer receiver over UART, starts the PC GStreamer
  RTP/raw sender, shows a Chinese control surface, and previews HDMI return
  through MJPEG. Legacy UDP/fbdev dashboard mode remains available as
  `--pipeline legacy-udp` recovery context.
```

## PC Dashboard

Run the dashboard GStreamer/Chinese UI self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-gstreamer-chinese-control"
```

Expected markers include:

```text
DASHBOARD_GSTREAMER_CONTROL_SELF_TEST_OK
DASHBOARD_CHINESE_UI_SELF_TEST_OK
```

Run the local GStreamer dashboard:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --host 127.0.0.1 --port 8765 --pipeline gstreamer --uart-port COM16 --uart-login-root --uart-password root"
```

`start-stream` uses:

```text
PC GStreamer videotestsrc ball -> I420 -> jpegenc -> rtpjpegpay ->
  udpsink port 5011
Board GStreamer udpsrc -> rtpjitterbuffer -> rtpjpegdepay -> jpegdec ->
  videoconvert -> videoscale -> fbdevsink /dev/fb0
HDMI capture adapter -> /api/output-stream.mjpeg
```

The left panel reads raw RGB frames tee'd from the actual GStreamer source.

Run the legacy UDP dashboard board-live loop only for recovery comparison:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\finite-loop -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 80 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200
```

Run the board-live loop and leave the dashboard/sender running for inspection:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dashboard_board_live_loop.ps1 -OutDir build\dashboard-color-block-loop-and-uart-audit\live-demo -CaptureDevice 1 -CaptureBackend dshow -StreamFps 10 -MjpegFrames 40 -MjpegMinUnique 2 -MjpegMinColors 3 -Frames 12 -Fps 2 -InterPacketUs 200 -KeepRunning
```

Run the fixed demo-video sender self-test:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py --self-test --out-dir build\fixed-demo-video-sender"
```

Send the fixed generated demo stream to the board receiver:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\send_demo_video_udp.py 192.168.1.10 --frames 5 --fps 1"
```

The dashboard does not use camera/webcam input or custom input files as video
sources. Windows may still report camera access because the HDMI capture
adapter is exposed as a UVC/DirectShow device.

Dashboard action endpoints:

```text
GET  /api/actions
POST /api/action {"action":"start-stream"}
POST /api/action {"action":"capture-output"}
POST /api/action {"action":"pause-receiver"}
POST /api/action {"action":"resume-receiver"}
POST /api/action {"action":"receiver-status"}
POST /api/action {"action":"effect-none"}
POST /api/action {"action":"effect-invert"}
POST /api/action {"action":"stop-stream"}
```

In GStreamer mode, `pause-receiver`, `resume-receiver`, `effect-none`, and
`effect-invert` intentionally return not-implemented rather than pretending to
control the pipeline. `receiver-status` tails the board GStreamer log over
UART. Use `--pipeline legacy-udp` only when testing the retired UDP/fbdev
receiver controls.

The previous PL-only video effects demo remains available as a side demo, not
the current network-video MVP:

```text
Example: examples/video-pip
Part: xc7z020clg484-1
Clock: M19, 50 MHz, LVCMOS33
HDMI: TMDS_33 output pins from the Smart ZYNQ SL schematic
Stage 1: 640x480 timing and test pattern pass xsim
Stage 2: 160x120 PIP compositor pass xsim
Stage 3: preset PIP demo script passes xsim
Programming: PL SRAM only
```

The earlier schematic-backed bare-board LED chaser MVP remains available:

```text
Example: examples/led-chaser
Part: xc7z020clg484-1
Clock: M19, 50 MHz, LVCMOS33
LED1: P20, LVCMOS33, active-high
LED2: P21, LVCMOS33, active-high
Programming: PL SRAM only
```

## Unified Pass-Through Validator

Run the calibrated validator self-check:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\validate_passthrough_trace.py --calibration --out-dir build\unified-passthrough-validator-calibration"
```

Expected marker:

```text
UNIFIED_PASSTHROUGH_VALIDATOR_CALIBRATION_OK
```

Trace schema:

```text
docs/protocols/unified-passthrough-trace.md
```

This validator checks temporal frame correspondence, latency, drop rate,
ordering, content identity, and black/no-frame rejection. It is the preferred
evidence check for future hardware work that claims faithful live pass-through.
The calibration cycle is PC-side only; it does not itself prove board HDMI
pass-through at 15 fps.

Before relying on the validator for hardware evidence, run the edge regression:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\validate_passthrough_trace.py --boundary-order-regression --out-dir build\unified-validator-boundary-order-fix"
```

Expected marker:

```text
UNIFIED_VALIDATOR_BOUNDARY_ORDER_FIX_OK
```

For the current preferred Linux network-to-HDMI transfer check, use the
workflow owner:

```text
skills/zynq7020-pipeline/SKILL.md
```

Current preferred runner:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_linux_net_to_hdmi_direct_copy_probe.ps1
```

Expected marker:

```text
LINUX_NET_TO_HDMI_DIRECT_COPY_OK
```

The older unified 15 fps image-evidence hardware loop remains useful recovery
context:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_unified_15fps_trace_probe.ps1 -OutDir build\unified-15fps-image-evidence-pass-through -CaptureDevice 1 -CaptureBackend dshow -StreamFps 30 -MjpegFrames 220 -MjpegMinUnique 8 -MjpegMinColors 8 -Frames 30 -WarmupFrames 12 -ValidationStartFrameId 100 -Fps 15 -TraceMaxLatencyMs 1000 -UdpPayload 1200 -HoldRepeats 1 -InterPacketUs 0 -PacketWindowFraction 0.85 -ReceiverSyncMode none -ReceiverPresentFps 15
```

Expected marker:

```text
UNIFIED_15FPS_IMAGE_EVIDENCE_OK
```

This hardware loop uses generated RGB888 frames with a small image-decodable
marker, not camera/webcam input. The trace requirement for max latency applies
to the HDMI-UVC/MJPEG return evidence path; the passing run measured
`trace_max_latency_ms=257.561`.

## Ethernet Video Pass-Through

Current active artifacts:

```text
docs/project-roadmap.md
docs/current-cycle.md
docs/reports/eth-ps-pl-hdmi-pass-through.md
docs/reports/tf-card-linux-resume-2026-06-26.md
docs/protocols/unified-passthrough-trace.md
examples/eth-ps-pl-hdmi-pass-through/
software/eth_pass_through/
tools/send_demo_video_udp.py
tools/send_video_udp.py
tools/validate_passthrough_trace.py
tools/send_unified_test_video_udp.py
tools/build_unified_trace_from_mjpeg.py
tools/run_linux_net_to_hdmi_direct_copy_probe.ps1
tools/run_unified_15fps_trace_probe.ps1
```

Known good subchains:

```text
Official VDMA DDR framebuffer -> HDMI capture: passed at 800x600.
Official pure-PL UDP loopback over the same RJ45 path: passed.
Official Linux TF-card Ethernet route: passed, ping 0% loss.
PetaLinux 2018.3 in WSL: installed at /opt/petalinux-v2018.3.
Project baremetal hand-written RGMII bridge -> PS lwIP RX: retired dead end.
Linux userspace direct-copy network-to-HDMI path: passed; see
skills/zynq7020-pipeline/SKILL.md for the current entry point.
```

Baremetal fallback build, only if explicitly needed for historical comparison:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\eth_pass_through\scripts\build-sdk-app-wsl.ps1
```

Do not use the retired custom-reader entry point:

```powershell
.\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-board-wsl.ps1
```

It targets the old 640x480 RGB565 custom reader and intentionally fails.

## Video PIP Side Demo

Run simulation first:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\sim-wsl.ps1 -Example video-pip
```

Expected markers:

```text
STAGE1_TIMING_AND_PATTERN_OK
STAGE2_PIP_OK
STAGE3_EFFECT_PIPE_OK
STAGE4_BUTTON_CONTROL_OK
STAGE5_AUTO_DEMO_SCRIPT_OK
SIM_OK
```

Build the downloadable PL-only side-demo bitstream:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\build-wsl.ps1 -BoardProfile .\boards\hellofpga-smart-zynq-sl-7020.tcl -Example video-pip
```

This writes PL SRAM only when programmed. It does not write QSPI, NAND, eMMC,
SD, or any flash storage.

Latest video evidence:

```text
build/reports/video-pip-auto-demo.md
build/reports/hdmi-effects-verified.md
build/reports/latest-hdmi-effects-run.json
build/reports/hdmi-capture/latest.png                 # prior capture artifact
build/reports/hdmi-capture/latest-sequence.png        # prior fast-loop capture artifact
build/reports/hdmi-capture/latest-validation.json     # latest capture attempt status
build/reports/video-pip-stage12.md
build/video-pip/sim/xsim-run.log
build/video-pip/reports/drc.rpt
build/video-pip/reports/timing_summary.rpt
build/video-pip/video-pip.bit
```

Current automatic demo:

```text
640x480 HDMI output with a clean stable background A.
PIP window B runs a preset loop: hidden -> appear -> move -> rotate ->
scale -> rotate+scale while moving -> repeat.
The previous HDMI capture path used the UVC adapter as DirectShow device index
1. If the adapter does not open after reprogramming, physically replug the UVC
capture adapter before recording.
Each phase lasts 300 video frames, about 5.04 seconds at 640x480 timing.
```

## Recording Demo Script

Record 35 to 40 seconds from the HDMI capture input. The visible loop is:

```text
0. Clean background A only
1. PIP B appears with a white border
2. PIP B moves diagonally
3. PIP B shows 90-degree rotation
4. PIP B shows 2x scale
5. PIP B moves while using 90-degree rotation plus 2x scale
6. Loop back to background-only intro
```

Use this narration:

```text
This is a PL-only Zynq-7020 HDMI video-effects pipeline. The FPGA generates a
stable background video source, overlays a second picture-in-picture source,
and applies scripted movement, rotation, and scaling before realtime HDMI
output.
```

## Button Control Status

The dynamic demo path has been implemented in RTL. The onboard KEY1/KEY2 button
logic has been implemented and passes simulation, but it is not wired into the
current downloadable HDMI top because the board's onboard key pins conflict with
the working differential HDMI output resources.

Evidence and decision record:

```text
build/reports/dynamic-video-button-control-attempt.md
```

Use external buttons on verified free J5/J6 GPIO pins, UART commands, or a later
PS-side control path for reliable physical operation.

## Run The LED MVP

From the repository root:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-pipeline\scripts\run-mvp.ps1 -BoardProfile .\boards\hellofpga-smart-zynq-sl-7020.tcl -Backend auto
```

Expected final line:

```text
MVP_PIPELINE_OK bitstream=E:\main\fpga-hdml\build\led-chaser\led-chaser.bit backend=xsct
```

Latest run evidence:

```text
build/reports/latest-mvp-run.json
build/led-chaser/reports/drc.rpt
build/led-chaser/reports/timing_summary.rpt
build/led-chaser/led-chaser.bit
```

## Build Only

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-vivado\scripts\build-wsl.ps1 -BoardProfile .\boards\hellofpga-smart-zynq-sl-7020.tcl -Example led-chaser
```

## Program Only

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skills\zynq7020-hardware\scripts\program-xsct.ps1 -Bitstream .\build\led-chaser\led-chaser.bit
```

## Board Evidence

The board profile is based on the official HelloFPGA Smart ZYNQ SL page:

```text
http://www.hellofpga.com/index.php/2023/05/10/smart-zynq-sl/
```

Downloaded schematic:

```text
build/reports/SmartZynq_SL_Schematic_V1d3_20241005.pdf
```

Important pages:

```text
Page 6: LED circuit, active-high through 30R to ground
Page 10: 50M CLOCK CLK=M19, LED1=P20, LED2=P21
Page 11: Vivado constraint reference for clk_50, LED1, LED2
```

## Skill Entry Points

Always start from the orchestrator:

```text
skills/zynq7020-pipeline/SKILL.md
```

Child skills:

```text
skills/zynq7020-environment/SKILL.md
skills/zynq7020-vivado/SKILL.md
skills/zynq7020-hardware/SKILL.md
```
