# jpegpldec

`jpegpldec` is the project-owned GStreamer decoder entry point for the
MJPEG-to-PL-acceleration route.

The first implementation is intentionally conservative: it is a GStreamer
plugin that registers `jpegpldec` as a bin wrapping the system `jpegdec`
element. This proves that the board can load a project-owned decoder element
and that the current pipeline can replace:

```text
rtpjpegdepay ! jpegdec ! ...
```

with:

```text
rtpjpegdepay ! jpegpldec ! ...
```

without changing the rest of the video chain.

It is not a PL accelerator yet. Later cycles may replace the internal software
reference path with a custom decoder implementation and PL offload interface.

## Build

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\gstreamer\jpegpldec\build-wsl.ps1
```

The build expects the verified PetaLinux project sysroot to exist under:

```text
/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic
```

## Board Probe

Deploy `libgstjpegpldec.so` to `/tmp/gst-plugins/` and run:

```sh
GST_PLUGIN_PATH=/tmp/gst-plugins gst-inspect-1.0 jpegpldec
```

The current video path can then replace `jpegdec` with `jpegpldec`:

```text
udpsrc port=5011 caps=...
! rtpjitterbuffer latency=100 drop-on-latency=true
! rtpjpegdepay
! jpegpldec probe-mode=pl-probe summary-interval=30
! videoconvert
! videoscale
! video/x-raw,format=BGR,width=800,height=600
! fbdevsink device=/dev/fb0 sync=true
```

## Probe Modes

`jpegpldec` keeps the external GStreamer caps stable while exposing internal
measurement hooks:

- `probe-mode=software`: software reference path only.
- `probe-mode=pl-probe`: software reference path plus PL PIP AXI-Lite status
  sampling through `/dev/mem`.
- `summary-interval=N`: emit one `JPEGPLDEC_PROFILE` marker every `N` decoded
  frames.
- `pl-base=1136656384`: PL PIP AXI-Lite base address; default is
  `0x43c00000`.
- `pl-map-size=65536`: `/dev/mem` mapping size for the PL status probe.

Markers:

```text
JPEGPLDEC_PROFILE frames=... mode=... avg_ms=... p50_ms=... p95_ms=...
JPEGPLDEC_PL_PROBE frame=... main_frames=... pip_frames=... overlay_pixels=...
```

The PL probe reads the existing PIP status registers. It proves that the
plugin can access the live PL control/status plane while the video pipeline is
running. It does not yet move compressed JPEG data through a PL decoder.

## Integrated Probe

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1
```

The probe builds the plugin, deploys it to `/tmp/gst-plugins/`, starts a board
receiver with `probe-mode=pl-probe`, requires profiling and PL status markers,
and checks the dashboard HDMI-return MJPEG stream when the dashboard is
running.
