# SDK Application Overlay

This directory contains only the first-stage application-specific source. The
build script creates a Vivado SDK workspace from the current stage-1 HDF, asks
SDK 2018.3 to generate its standard `lwIP Echo Server` application, then
replaces the echo callback with `video_udp_app.c` and copies the shared UDP
protocol parser into that app.

The VDMA MVP uses one RGB888 framebuffer at `0x01100000`, matching the official
VDMA HDMI reference design.

```text
UDP port 5005
RGB888 800x600
VDMA DDR framebuffer base 0x01100000
```

Runtime diagnostics:

```text
UDP heartbeat broadcast port 5006
UART once-per-second GEM counters: TX frames, RX frames, RX checksum/errors
UART PHY register snapshot for PHY address 1 and GMII-to-RGMII address 8
```

Use `tools/listen_stage1_heartbeat.py` on the PC to prove board-to-PC Ethernet
transmit independently from the video receive path.
