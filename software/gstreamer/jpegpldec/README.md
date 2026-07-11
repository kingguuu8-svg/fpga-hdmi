# jpegpldec

`jpegpldec` is the project-owned GStreamer decoder entry point for the
MJPEG-to-PL-acceleration route.

`jpegpldec` keeps a software-reference backend and also provides a real
`pl-decoder` backend. The outer element remains a bin so the current pipeline
can replace:

```text
rtpjpegdepay ! jpegdec ! ...
```

with:

```text
rtpjpegdepay ! jpegpldec ! ...
```

without changing the rest of the video chain.

without changing the downstream video chain. `backend=pl-decoder` replaces the
system `jpegdec` child with an internal `GstVideoDecoder`, sends the compressed
buffer through `/dev/jpegpl_dma_probe`, and publishes the returned raw frame
as a timed downstream GstBuffer.

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

## Backends

- `backend=software-reference`: default path. `jpegpldec` keeps the internal
  software `jpegdec` child and only adds profiling/probe hooks.
- `backend=pl-compressed-probe`: sends compressed JPEG input buffers through
  `/dev/jpegpl_dma_probe` before falling back to the software reference decode.
  This is the first PL decode-backend boundary. It proves real compressed JPEG
  ingress into the PL DMA data plane, not PL entropy decode yet.
- `backend=pl-decoder`: accepts the qualified profile owned by
  `docs/project-roadmap.md` and the decoder contract, invokes
  `JPEGPL_DMA_PROBE_IOC_DECODE`, and publishes the PL-decoded raw format owned
  by the roadmap. The
  system `jpegdec` child is absent from the selected runtime graph.
- `verify-output-hash=true`: computes a diagnostic FNV hash for each PL output.
  It is disabled by default because it adds ARM work and is not part of decode.

The backend may only be changed while the element is in `NULL`. Unsupported
profiles fail explicitly; select `backend=software-reference` as the recovery
path.

## Real Backend Gate

Run the complete build, fixed-vector, software-regression, RTP/JPEG, PL decode,
HDMI capture, graph, and health gate with:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_real_backend.ps1
```

The connected display pipeline uses `fbdevsink sync=false qos=false` for this
paced low-rate gate defined by the roadmap. `rtpjpegdepay` on the current GStreamer version advertises
`framerate=0/1`; clock-synchronizing that unknown-rate stream caused display
wait/drop behavior even though PL decode had completed.

## Probe Modes

`jpegpldec` keeps the external GStreamer caps stable while exposing internal
measurement hooks:

- `probe-mode=software`: software reference path only.
- `probe-mode=pl-probe`: software reference path plus PL PIP AXI-Lite status
  sampling through `/dev/mem`.
- `probe-mode=buffer-probe`: software reference path plus decoded I420 buffer
  checksum and top-left luma marker stamping.
- `probe-mode=pl-buffer-probe`: combines `pl-probe` and `buffer-probe`.
- `probe-mode=dma-probe`: loops each decoded raw buffer through
  `/dev/jpegpl_dma_probe`, verifies returned bytes and checksums, and leaves
  the original GstBuffer on the existing downstream path.
- `probe-mode=pl-dma-probe`: combines `pl-probe` and `dma-probe`.
- `probe-mode=dma-writeback`: copies the decoded raw buffer into a staging
  buffer, stamps a top-left I420 luma marker in that staging copy, sends it
  through `/dev/jpegpl_dma_probe`, and writes the PL-returned bytes into the
  downstream GstBuffer.
- `probe-mode=pl-dma-writeback`: combines `pl-probe` and `dma-writeback`.
- `probe-mode=compressed-dma-probe`: loops compressed JPEG input through
  `/dev/jpegpl_dma_probe` before software decode, parses JPEG metadata, and
  verifies returned bytes and checksums.
- `probe-mode=pl-compressed-dma-probe`: combines `pl-probe` and
  `compressed-dma-probe`.
- `summary-interval=N`: emit one `JPEGPLDEC_PROFILE` marker every `N` decoded
  frames.
- `pl-base=1136656384`: PL PIP AXI-Lite base address; default is
  `0x43c00000`.
- `pl-map-size=65536`: `/dev/mem` mapping size for the PL status probe.

Markers:

```text
JPEGPLDEC_PROFILE frames=... mode=... avg_ms=... p50_ms=... p95_ms=...
JPEGPLDEC_PL_PROBE frame=... main_frames=... pip_frames=... overlay_pixels=...
JPEGPLDEC_BUFFER_PROBE frame=... checksum_before=... checksum_after=... result=pass
JPEGPLDEC_DMA_PROBE frame=... bytes=... chunks=... checksum_host=... result=pass
JPEGPLDEC_DMA_WRITEBACK frame=... checksum_staged=... checksum_written=... result=pass
JPEGPLDEC_COMPRESSED_DMA_PROBE frame=... jpeg_width=... jpeg_height=... sampling=... result=pass
```

The PL probe reads the existing PIP status registers. It proves that the
plugin can access the live PL control/status plane while the video pipeline is
running.

The compressed DMA probe is the first PL decode-backend boundary. It taps the
compressed `image/jpeg` GstBuffer on the decoder sink pad, parses enough JPEG
headers to verify the contract, sends those exact compressed bytes through the
PL DMA endpoint, and then continues through the software reference decoder.
It does not yet implement Huffman decode, dequant, IDCT, color conversion, or
decoded-frame generation in PL.

The buffer probe modifies the decoded I420 buffer before downstream
`videoconvert`, `videoscale`, `fbdevsink`, VDMA, PL PIP, and HDMI. It proves
that data produced inside `jpegpldec` can be marked and later observed through
the existing PL display data path. It does not prove an independent DMA-safe
private buffer, PL writeback, or a GStreamer buffer returned from PL.

The DMA probe uses kernel-owned coherent TX/RX buffers and the AXI DMA
loopback endpoint. The verified endpoint is handled inside the ioctl as
16380-byte transactions, so one decoded I420 GstBuffer remains one logical
plugin frame. This proves PS-to-PL-to-PS data integrity and cache-safe access.
It deliberately does not replace the downstream GstBuffer with PL output;
that is the next writeback step.

The DMA writeback mode is the first GStreamer reconnection step. It avoids
modifying the original GstBuffer before DMA by using a staging copy, then
copies the coherent RX result back into the writable downstream GstBuffer.
This proves that downstream `videoconvert`, `videoscale`, `fbdevsink`, VDMA,
PL PIP, and HDMI consume bytes returned from the PS-to-PL-to-PS path. It is
still not zero-copy and does not yet implement JPEG entropy decode in PL.

## Integrated Probe

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1
```

The probe builds the plugin, deploys it to `/tmp/gst-plugins/`, starts a board
receiver with `probe-mode=pl-probe`, requires profiling and PL status markers,
and checks the dashboard HDMI-return MJPEG stream when the dashboard is
running.

For the decoded-buffer data-path marker probe:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode pl-buffer-probe -OutDir build\jpegpldec-pl-buffer-datapath-probe
```

For the real PS-to-PL DMA buffer probe and dynamic HDMI verification:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode dma-probe -SummaryInterval 10 -Frames 60 -Fps 5 -OutDir build\jpegpldec-dma-buffer-probe
```

For the PL-returned GstBuffer writeback probe:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode dma-writeback -SummaryInterval 10 -Frames 60 -Fps 5 -OutDir build\jpegpldec-dma-writeback
```

For the 720p compressed-JPEG PL ingress probe:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_jpegpldec_pl_probe.ps1 -ProbeMode compressed-dma-probe -InputWidth 1280 -InputHeight 720 -OutputWidth 800 -OutputHeight 600 -Fps 30 -Frames 5 -SummaryInterval 5 -OutDir build\jpegpldec-pl-decode-720p30-v0
```
