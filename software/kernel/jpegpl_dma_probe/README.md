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

## Boundary

This source is not enough to claim the active goal. The full goal still needs:

- BOOT.BIN/image update with the AXI DMA endpoint.
- Device-tree update exposing `axi_dma_0` and the client node.
- Board load of `jpegpl_dma_probe.ko`.
- Standalone `/dev/jpegpl_dma_probe` loopback with a known buffer.
- `jpegpldec` integration that sends real decoded frames through the ioctl.
- HDMI return validation that proves GStreamer continues to display dynamic
  frames after PL loopback.
