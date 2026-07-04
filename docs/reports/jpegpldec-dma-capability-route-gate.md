# jpegpldec DMA Capability Route Gate

Cycle ID: jpegpldec-dma-capability-route-gate

Date: 2026-07-04

## Objective

Check whether the currently booted board image already exposes a user-space
DMA-safe buffer path that `jpegpldec` can use for a private PS-to-PL buffer
probe without changing the external GStreamer pipeline.

This is a route gate for the larger objective:

```text
jpegpldec decoded/working buffer
-> DMA-safe PS buffer
-> PL readable/writeable endpoint
-> cache/coherency validation
-> optional PL writeback into GStreamer
```

## Changed Scope

- Added `tools/run_board_dma_capability_probe.ps1`.
- The probe logs board kernel/device capabilities over UART and writes a JSON
  summary.
- No runtime video pipeline, bitstream, rootfs, or board image was changed.

## Verification

Command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_board_dma_capability_probe.ps1 -OutDir build\jpegpldec-dma-capability-route-gate
```

Observed:

```text
JPEGPLDEC_DMA_CAPABILITY_PROBE_OK result=missing-userspace-dma-buffer-interface cma=1 dma_shared_buffer=1 xilinx_dma=1 dma_heap=0 udmabuf=0 uio_dev=0 fb0=1 vdma=1
```

Kernel:

```text
Linux vdma-hdmi-minimal-bionic 4.14.0-xilinx-v2018.3 #13 SMP PREEMPT Thu Jul 2 09:49:08 UTC 2026 armv7l GNU/Linux
```

Positive capability evidence:

```text
CONFIG_CMA=y
CONFIG_DMA_SHARED_BUFFER=y
CONFIG_DMA_ENGINE=y
CONFIG_XILINX_DMA=y
CONFIG_UIO=y
/sys/devices/soc0/amba_pl/43000000.dma
/sys/bus/platform/drivers/xilinx-vdma
/dev/fb0
fb0 virtual_size=800,1200
fb0 stride=2400
```

Missing direct user-space buffer evidence:

```text
DEV_DMA_HEAP_ABSENT
DEV_UIO_ABSENT
DEV_UDMABUF_ABSENT
DEV_ION_ABSENT
SYS_UIO_ABSENT
SYS_UDMABUF_ABSENT
```

## Result

PASSED as a negative route gate.

The current image has kernel-side DMA/CMA/Xilinx DMA support and the existing
VDMA/display path, but it does not expose a direct user-space DMA buffer
allocator or user-accessible PL DMA endpoint suitable for `jpegpldec` to create
a private DMA-safe buffer and hand it to PL.

## Decision

Do not attempt PL writeback or GStreamer reconnect from `jpegpldec` on the
current image/bitstream as-is. It would require guessing physical addresses or
sharing normal cached `GstBuffer` memory with PL, which would not prove cache
coherency.

The next implementation step should add one explicit data endpoint:

1. Preferred route: add a small AXI DMA loopback/checksum path in PL and a
   Linux DMA client interface that allocates coherent/CMA-backed buffers and
   exposes them to `jpegpldec`.
2. Acceptable route: add `udmabuf` or equivalent reserved-memory userspace
   buffer support, then use PL to read/checksum that physical buffer.
3. Avoid: `/dev/mem` against normal `malloc` or `GstBuffer` virtual memory.
   That does not provide a reliable physical address or cache-coherency proof.

## Evidence

- `tools/run_board_dma_capability_probe.ps1`
- `build/jpegpldec-dma-capability-route-gate/summary.json`
- `build/jpegpldec-dma-capability-route-gate/uart-dma-capability.log`

## Board Action

- UART read-only probe.
- No BOOT.BIN, image.ub, rootfs, FPGA bitstream, TF-card image, JTAG
  programming, or board flash write was performed.

## Rollback

No rollback required; this cycle did not change board state.

## Third-Party Review

None.

## Residual Risks

- This route gate only proves that the currently booted image does not expose a
  ready user-space DMA buffer API. It does not evaluate a rebuilt image with
  `udmabuf`, a custom DMA proxy driver, or a new AXI DMA endpoint.
- The existing framebuffer/VDMA path remains valid for display-side effects,
  but it is not equivalent to a private `jpegpldec` buffer loopback.
