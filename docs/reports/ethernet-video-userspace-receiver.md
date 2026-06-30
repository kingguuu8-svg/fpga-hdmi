# Ethernet Video Userspace Receiver

Date: 2026-06-30
Cycle ID: ethernet-video-userspace-receiver

## Objective

Receive the project UDP RGB888 frame protocol in Linux userspace, write
complete frames to the proven `/dev/fb0` path, and prove through HDMI capture
that a PC-sent known frame reaches the display.

## Scope

- Added a minimal Linux userspace receiver that binds UDP port 5005, assembles
  complete 800x600 RGB888 frames, and writes each complete frame to `/dev/fb0`.
- Reused the existing project UDP parser and frame reassembly code.
- Added a framebuffer row-copy helper and host tests.
- Extended the PC sender with an `rgb-stripes` deterministic test pattern.
- Did not rebuild Vivado or PetaLinux.
- Did not add effects, compression, retransmission, or continuous-video quality
  targets in this cycle.

## Implementation

New source paths:

```text
software/eth_pass_through/linux_app/src/fb_video_udp_receiver.c
software/eth_pass_through/linux_app/build.sh
software/eth_pass_through/scripts/build-linux-receiver-wsl.ps1
software/eth_pass_through/src/video_framebuffer.c
software/eth_pass_through/src/video_framebuffer.h
software/eth_pass_through/tests/test_linux_framebuffer_writer.c
```

The receiver flow is:

```text
UDP socket
-> video_udp_receiver_on_packet()
-> complete RGB888 frame
-> framebuffer bitfield channel mapping
-> mmap(/dev/fb0)
-> HDMI through the existing VDMA/DRM path
```

Important runtime finding:

```text
/dev/fb0 is 24bpp, but its channel bitfields are:
  red_offset=16
  green_offset=8
  blue_offset=0

Therefore the framebuffer byte order is BGR in memory. The protocol remains
RGB888; the Linux receiver converts from protocol RGB to framebuffer byte order
using FBIOGET_VSCREENINFO bitfields.
```

The first HDMI capture after a direct byte copy failed with red/blue swapped.
That was fixed by using the framebuffer bitfields instead of assuming RGB byte
order.

## Build And Test Verification

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\eth_pass_through\scripts\build-linux-receiver-wsl.ps1
```

Results:

```text
VIDEO_UDP_RECEIVER_TEST_OK
VIDEO_FB_COPY_TEST_OK
LINUX_RECEIVER_BUILD_OK
```

Generated board binary:

```text
ELF 32-bit LSB executable, ARM, EABI5, dynamically linked,
interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0
SHA-256 3914d374fe5e5fc15a22da7c47b8a6fdc26df98f02454bf3c272413594946da4
```

Raw evidence:

```text
build/ethernet-video-userspace-receiver/test_video_udp_receiver.log
build/ethernet-video-userspace-receiver/test_linux_framebuffer_writer.log
build/ethernet-video-userspace-receiver/fb_video_udp_receiver.file.txt
build/ethernet-video-userspace-receiver/fb_video_udp_receiver.sha256.txt
```

## Board Verification

Board state:

```text
UART shell: root
Kernel: Linux vdma-hdmi-minimal-bionic 4.14.0-xilinx-v2018.3 #10
eth0: 192.168.1.10/24
PC ping 192.168.1.10: 4/4 received, 0% loss
Board ping 192.168.1.2: 2/2 received, 0% loss
/dev/fb0: present
fb0 virtual_size: 800,1200
fb0 bits_per_pixel: 24
```

Deployment:

```text
PC served build/ethernet-video-userspace-receiver/ over HTTP at 192.168.1.2:8000.
Board downloaded /tmp/fb_video_udp_receiver with wget.
Board SHA-256 check passed against
3914d374fe5e5fc15a22da7c47b8a6fdc26df98f02454bf3c272413594946da4.
```

Receiver runtime:

```text
FB_INFO path=/dev/fb0 xres=800 yres=600 xres_virtual=800 yres_virtual=1200
  bpp=24 line_length=2400 smem_len=2880000
  red_offset=16 green_offset=8 blue_offset=0
FB_CHANNEL_BYTES red=2 green=1 blue=0
VIDEO_UDP_LINUX_RECEIVER_READY port=5005 frames=1 timeout_sec=60
VIDEO_UDP_FRAME_WRITTEN frame_id=0 frames=1 packets=1200 dropped=0
VIDEO_UDP_RECEIVER_DONE frames=1 packets=1200 dropped=0
```

Ethernet counters after the frame:

```text
RX packets:3447 errors:0 dropped:0 overruns:0 frame:0
TX packets:845 errors:0 dropped:0 overruns:0 carrier:0
```

PC sender:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\send_video_udp.py 192.168.1.10 --pattern rgb-stripes --frames 1 --fps 1 --payload 1200 --inter-packet-us 200"
```

Sender result:

```text
frame=0 bytes=1440000 packets=1200 elapsed_s=0.867
SEND_OK frames=1 packets=1200 target=192.168.1.10:5005
```

HDMI capture:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\capture_hdmi.py --device 1 --backend dshow --width 800 --height 600 --frames 45 --save-samples 3 --validation-profile rgb-stripes --out-dir build\ethernet-video-userspace-receiver\hdmi-after-udp-frame-bgrfix"
```

HDMI result:

```text
HDMI_CAPTURE_OK device_index=1 backend=dshow
```

Validated RGB means:

```text
top_blue:    [0.05, 0.05, 254.61]
middle_green:[0.0, 255.0, 0.0]
bottom_red: [255.0, 0.0, 0.0]
```

Raw evidence:

```text
build/ethernet-video-userspace-receiver/uart_probe.log
build/ethernet-video-userspace-receiver/uart_net_fb_probe.log
build/ethernet-video-userspace-receiver/uart_redeploy_start_receiver.log
build/ethernet-video-userspace-receiver/uart_receiver_after_send_bgrfix.log
build/ethernet-video-userspace-receiver/hdmi-after-udp-frame-bgrfix/latest-validation.json
build/ethernet-video-userspace-receiver/hdmi-after-udp-frame-bgrfix/latest.png
```

## Result

Status: PASSED.

The first-stage Ethernet video pass-through MVP is now physically closed:

```text
PC UDP RGB888 frame
-> board Linux userspace socket receiver
-> /dev/fb0
-> VDMA/DRM fixed-mode HDMI output
-> PC HDMI capture validation
```

## Residual Risks

- This cycle proves single-frame pass-through at low packet rate, not sustained
  realtime video throughput.
- There is no packet-loss recovery. Missing UDP chunks keep the previous frame.
- The receiver is deployed manually to `/tmp`; it is not yet packaged into the
  PetaLinux root filesystem or started by init.
- The framebuffer console can still draw over the video surface outside this
  controlled test.
- Effects and runtime control remain later cycles.
