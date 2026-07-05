# jpegpl DMA Probe Kernel Client

This module is the planned Linux-side bridge between `jpegpldec` and the PL
AXI DMA endpoint:

```text
jpegpldec decoded raw buffer
-> /dev/jpegpl_dma_probe ioctl
-> dma_alloc_coherent TX buffer
-> AXI DMA MM2S
-> axis_dma_probe_core
-> AXI DMA S2MM
-> dma_alloc_coherent RX buffer
-> /dev/jpegpl_dma_probe ioctl returns data
-> jpegpldec continues the same external GStreamer pipeline
```

The module deliberately uses kernel DMAengine plus `dma_alloc_coherent` instead
of `/dev/mem` against normal userspace or `GstBuffer` addresses. That is the
minimum path that can make a cache-coherency claim defensible.

The ioctl accepts one logical userspace buffer. The verified AXI DMA endpoint
has a 14-bit BTT field, so the driver internally splits larger buffers into
16380-byte aligned transactions and returns one complete output buffer. The
device-tree `max-transfer-size` property can override that transaction limit.

## Build

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\kernel\jpegpl_dma_probe\build-wsl.ps1
```

Expected marker:

```text
JPEGPL_DMA_PROBE_CLIENT_BUILD_OK
```

## Device Tree Client Node

The running device tree must expose the AXI DMA controller from the updated
HDF and a client node with named `tx` and `rx` DMA channels. See
`software/petalinux/jpegpl-dma-probe/system-user.dtsi.fragment`.

## Verified Boundary

Connected-board testing now proves module binding, a 115200-byte standalone
loopback, 60 consecutive decoded `jpegpldec` frames through the coherent DMA
path, exact PL transaction/byte counters, and dynamic HDMI output. The probe
still copies userspace data into kernel coherent buffers and does not return
the PL output as the downstream GstBuffer. Zero-copy and GStreamer writeback
remain separate work.
