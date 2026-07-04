# jpegpldec Plugin Skeleton

Cycle ID: jpegpldec-plugin-skeleton

Date: 2026-07-04

## Objective

Create and verify a project-owned GStreamer decoder element named
`jpegpldec` that can replace `jpegdec` in the current RTP/JPEG-to-HDMI
pipeline. This first cycle intentionally uses the system `jpegdec` as the
software reference path inside the custom element; it does not claim PL codec
acceleration yet.

## Changed Scope

- Added `software/gstreamer/jpegpldec/`.
- Implemented `libgstjpegpldec.so` as a GStreamer plugin registering the
  `jpegpldec` element.
- The first implementation is a `GstBin` wrapper around the system `jpegdec`
  child named `software-reference-decoder`.
- Added a WSL/PetaLinux cross-build script that uses the verified PetaLinux
  2018.3 ARM toolchain and GStreamer/GLib target sysroots.

## Verification

Build:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\gstreamer\jpegpldec\build-wsl.ps1 -OutDir build\jpegpldec-plugin-skeleton\plugin
```

Observed:

```text
JPEGPLDEC_PLUGIN_BUILD_OK out=/mnt/e/main/fpga-hdml/build/jpegpldec-plugin-skeleton/plugin/libgstjpegpldec.so
```

Artifact:

```text
libgstjpegpldec.so: ELF 32-bit LSB shared object, ARM, EABI5
sha256=e84560077e6c7d4a2dc46b303c3df65f6b97cd450ea9392e7cffcd5716a23711
```

Board deployment:

```sh
mkdir -p /tmp/gst-plugins
wget -O /tmp/gst-plugins/libgstjpegpldec.so http://192.168.1.2:8088/libgstjpegpldec.so
sha256sum /tmp/gst-plugins/libgstjpegpldec.so
GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec.bin gst-inspect-1.0 jpegpldec
```

Observed:

```text
Filename /tmp/gst-plugins/libgstjpegpldec.so
Long-name JPEG PL decoder skeleton
Klass Codec/Decoder/Image
Children: software-reference-decoder
```

Board pipeline replacement:

```text
udpsrc port=5011 caps=application/x-rtp,...
! rtpjitterbuffer latency=100 drop-on-latency=true
! rtpjpegdepay
! jpegpldec
! videoconvert
! videoscale
! video/x-raw,format=BGR,width=800,height=600
! fbdevsink device=/dev/fb0 sync=true
```

Observed from `/tmp/gst_jpegpldec_receiver.log`:

```text
GstRtpJPEGDepay:src caps = image/jpeg, width=320, height=240
GstJpegPlDec:jpegpldec0/GstJpegDec:software-reference-decoder.GstPad:sink caps = image/jpeg
GstJpegPlDec:jpegpldec0/GstJpegDec:software-reference-decoder.GstPad:src caps = video/x-raw, format=I420, width=320, height=240
GstVideoConvert:src caps = video/x-raw, format=BGR
GstFBDEVSink:sink caps = video/x-raw, format=BGR, width=800, height=600
```

Dashboard/HDMI return probes:

```powershell
rtk powershell.exe -NoProfile -Command "python .\tools\probe_mjpeg_stream.py 'http://127.0.0.1:8765/api/output-stream.mjpeg' --out-dir 'build\jpegpldec-plugin-skeleton\mjpeg-probe' --frames 90 --min-unique 10 --timeout-sec 20"
rtk powershell.exe -NoProfile -Command "python .\tools\probe_mjpeg_stream.py 'http://127.0.0.1:8765/api/input-stream.mjpeg' --out-dir 'build\jpegpldec-plugin-skeleton\input-mjpeg-probe' --frames 60 --min-unique 10 --timeout-sec 15"
```

Observed:

```text
MJPEG_STREAM_PROBE_OK frames=90 unique=31
MJPEG_STREAM_PROBE_OK frames=60 unique=60
```

## Board Action

- Deployed `/tmp/gst-plugins/libgstjpegpldec.so` over Ethernet using board
  `wget`.
- Ran `gst-inspect-1.0 jpegpldec` with `GST_PLUGIN_PATH=/tmp/gst-plugins`.
- Stopped the temporary board `gst-launch-1.0` receiver and restarted it with
  `jpegpldec` replacing `jpegdec`.
- Reused the already-running PC GStreamer sender and dashboard HDMI/UVC return.
- No BOOT.BIN, image.ub, rootfs, FPGA bitstream, JTAG programming, TF-card
  image write, or board flash write was performed.

## Evidence

- `build/jpegpldec-plugin-skeleton/plugin/libgstjpegpldec.file.txt`
- `build/jpegpldec-plugin-skeleton/plugin/libgstjpegpldec.sha256.txt`
- `build/jpegpldec-plugin-skeleton/uart_deploy_inspect.log`
- `build/jpegpldec-plugin-skeleton/uart_start_jpegpldec_pipeline.log`
- `build/jpegpldec-plugin-skeleton/mjpeg-probe/mjpeg-stream-probe.json`
- `build/jpegpldec-plugin-skeleton/input-mjpeg-probe/mjpeg-stream-probe.json`
- `build/jpegpldec-plugin-skeleton/dashboard-state-after-jpegpldec.json`

## Result

PASSED. The board loaded the project-owned `jpegpldec` plugin from `/tmp`, the
plugin registered the expected `image/jpeg -> video/x-raw` element, the live
RTP/JPEG receiver pipeline ran with `jpegpldec` in place of `jpegdec`, and the
HDMI return stream remained dynamic.

## Residual Risks

- This is a plugin/control-plane milestone, not a performance or PL-codec
  acceleration milestone.
- The current `jpegpldec` implementation delegates decode to the system
  `jpegdec` child. Future PL acceleration requires replacing that internal
  software reference path.
- The dashboard state still reports the generic GStreamer receiver path because
  this cycle manually replaced the board-side receiver outside the dashboard
  start action.
