# jpegpl PL Decoder Kernel Client

This module is the Linux-side bridge between a compressed JPEG buffer and the
PL decoder data plane:

```text
compressed baseline JPEG
-> /dev/jpegpl_dma_probe ioctl
-> dmam_alloc_coherent TX buffer
-> AXI DMA MM2S
-> jpeg_core
-> coordinate-checked RGB888 stream writer
-> AXI DataMover S2MM
-> dmam_alloc_coherent RX buffer
-> RGB888 returned to userspace
```

The module deliberately uses kernel DMAengine plus `dmam_alloc_coherent`
instead of `/dev/mem` against normal userspace or `GstBuffer` addresses. That
is the minimum path that can make a cache-coherency claim defensible.

The decode ioctl accepts one logical compressed buffer. The AXI DMA endpoint
has a 14-bit BTT field, so the driver internally splits larger buffers into
16380-byte transactions; JPEG EOI, rather than DMA TLAST, ends the frame. The
device-tree `max-transfer-size` property can override that transaction limit.
`timeout_ms` is one deadline shared by every chunk and the subsequent PL-done
wait. A timed-out channel is terminated synchronously before the ioctl returns.

## Build

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\kernel\jpegpl_dma_probe\build-wsl.ps1
```

Expected marker:

```text
JPEGPL_DMA_PROBE_CLIENT_BUILD_OK
```

## Register Smoke

With the module loaded, verify the PL control-plane contract without DMA:

```sh
/tmp/jpegpl_dma_probe_test --register-smoke --width 1280 --height 720
```

The ioctl writes and reads back `DST_BASE`, `STRIDE`, `DIMENSIONS`, and
`EXPECTED_PIXELS`, and requires `VERSION=0x4a504c31`. It prints:

```text
JPEGPL_REGISTER_SMOKE_OK
```

Before every decode, the driver repeats that configuration readback, starts the
core, and requires the CONTROL readback to report live `busy` in bit 0 plus the
requested mode bits: bit 1 `count_only` and bit 2 `input_sink`. CONTROL bit 3
is `done`.

The test utility bounds the counter on both sides. Input-sink requires at least
one cycle per four accepted bytes, while decode modes require at least one
cycle per output pixel; all modes use the datapath's 200 MHz maximum as the
upper bound. Full writeback runs can also pass `--expect-fnv <value>` so a
known vector must match its expected BGR bytes before `JPEGPL_DECODE_OK` is
printed.

## Boot-Only Packaging

`software/petalinux/jpegpl-dma-probe/package-boot-wsl.ps1` deliberately does
not rebuild Linux. It may reuse the current `image.ub` only when the caller has
confirmed that the PL/device-tree topology is unchanged and supplies the full
expected hashes explicitly:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\petalinux\jpegpl-dma-probe\package-boot-wsl.ps1 `
  -Bitstream <path> `
  -OutDir <path> `
  -ExpectedBitstreamSha256 <64-hex> `
  -ExpectedImageUbSha256 <64-hex> `
  -ReuseExistingImageUb
```

The success marker is `JPEGPL_BOOT_ONLY_PACKAGE_OK`; it records the BOOT,
bitstream, and reused image hashes. If the HDF changes DMA channels, addresses,
interrupts, or another Linux-visible property, rebuild `image.ub` instead of
using this shortcut.

## Device Tree Client Node

The running device tree must expose the AXI DMA controller from the updated
HDF and a client node with a named `tx` DMA channel plus the decoder register
range. See
`software/petalinux/jpegpl-dma-probe/system-user.dtsi.fragment`.

## Verified Boundary

The previous dual-DMA loopback remains historical evidence in the cycle log.
The current ioctl drives only the compressed-input MM2S DMA channel; PL writes
RGB output through DataMover into the coherent output buffer. The ioctl exposes
input/output byte counts, decoded pixels, cycles, write commands/responses,
stalls, and PL error flags. Board-live qualification is owned by the
corresponding cycle report; a successful module build alone is not decoder
evidence.
