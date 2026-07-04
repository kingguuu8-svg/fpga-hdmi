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
! jpegpldec
! videoconvert
! videoscale
! video/x-raw,format=BGR,width=800,height=600
! fbdevsink device=/dev/fb0 sync=true
```
