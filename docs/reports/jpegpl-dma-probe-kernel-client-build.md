# jpegpl DMA Probe Kernel Client Build

Cycle ID: jpegpl-dma-probe-kernel-client-build

Date: 2026-07-05

## Objective

Add the Linux-side coherent DMA client needed before `jpegpldec` can honestly
claim a PS-to-PL buffer loopback.

The key design choice is to avoid `/dev/mem` on normal userspace or
`GstBuffer` virtual addresses. The module uses kernel DMAengine and
`dma_alloc_coherent` so the later cache-coherency claim can be based on a real
DMA-safe allocation path.

## Changed Scope

- Added `software/kernel/jpegpl_dma_probe/`.
- Added a kernel module, `jpegpl_dma_probe.ko`, that:
  - binds to `compatible = "fpga-hdml,jpegpl-dma-probe-1.0"`;
  - requests named DMAengine channels `tx` and `rx`;
  - allocates coherent TX/RX buffers with `dmam_alloc_coherent`;
  - exposes `/dev/jpegpl_dma_probe` through a misc character device;
  - accepts `JPEGPL_DMA_PROBE_IOC_RUN`;
  - copies user input into the coherent TX buffer;
  - starts S2MM before MM2S through DMAengine;
  - copies the coherent RX buffer back to userspace;
  - reports input/output FNV-1a checksums and elapsed time.
- Added `jpegpl_dma_probe_test`, a small userspace loopback probe tool.
- Added `build.sh` and `build-wsl.ps1` for the existing PetaLinux 2018.3 kernel
  build tree.
- Added `software/petalinux/jpegpl-dma-probe/system-user.dtsi.fragment` as the
  intended device-tree client node after importing an HDF containing
  `axi_dma_0`.

## Verification

Build command:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\kernel\jpegpl_dma_probe\build-wsl.ps1 -OutDir build\jpegpl-dma-probe-kernel-client
```

Observed markers:

```text
JPEGPL_DMA_PROBE_TEST_SELF_TEST_OK checksum=0x6fd741bd
JPEGPL_DMA_PROBE_CLIENT_BUILD_OK out=/mnt/e/main/fpga-hdml/build/jpegpl-dma-probe-kernel-client
```

Artifacts:

```text
jpegpl_dma_probe.ko: ELF 32-bit LSB relocatable, ARM, EABI5
sha256=1d9bf62790f8610bd743c6f31c84aea21a171067ef7d07749848977118203008

jpegpl_dma_probe_test: ELF 32-bit LSB executable, ARM, EABI5
sha256=f2556f2bdeaa2cddfbc063bbe65af280bd6da5142f994e2f45bac74322fc6901
```

The source directory was cleaned after external-module build; generated kernel
intermediates are not tracked.

## Result

PASSED for source/build feasibility.

This proves:

- The kernel client code compiles against the current PetaLinux 2018.3
  Linux 4.14 build tree.
- The userspace ioctl test tool cross-builds for ARM.
- The host self-test validates the deterministic test pattern/checksum logic.
- The project now has a concrete Linux DMA-safe API boundary for later
  `jpegpldec` integration.

This does not prove:

- The module loads on the board.
- The device tree binds the module to `axi_dma_0`.
- AXI DMA MM2S/S2MM channels are operational at runtime.
- A real decoded `jpegpldec` buffer has been looped through PL.
- Cache coherency has been validated on hardware.
- GStreamer continues displaying a PL-returned buffer.

## Board Action

None.

No BOOT.BIN, image.ub, rootfs, TF-card update, module insertion, JTAG
programming, or board flash write was performed.

## Evidence

- `software/kernel/jpegpl_dma_probe/`
- `software/petalinux/jpegpl-dma-probe/system-user.dtsi.fragment`
- `build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe.ko`
- `build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe.ko.sha256.txt`
- `build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe_test`
- `build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe_test.sha256.txt`
- `build/jpegpl-dma-probe-kernel-client/jpegpl_dma_probe_test_host.log`

## Decision

Next runtime step:

1. Import the HDF/bitstream that contains `axi_dma_0`.
2. Add the device-tree client node and rebuild `image.ub`.
3. Package/deploy the matching BOOT.BIN and image.ub.
4. Load `jpegpl_dma_probe.ko`.
5. Run `/tmp/jpegpl_dma_probe_test` and require `JPEGPL_DMA_PROBE_TEST_OK`.
6. Only after that, add a `jpegpldec` probe mode that calls the ioctl on real
   decoded frames and validates HDMI return.

## Rollback

Remove `software/kernel/jpegpl_dma_probe/` and
`software/petalinux/jpegpl-dma-probe/`. No board state changed.

## Third-Party Review

None.

## Residual Risks

- The device-tree `dmas = <&axi_dma_0 0>, <&axi_dma_0 1>` fragment is based on
  the expected Xilinx AXI DMA controller binding and still needs validation
  against the generated DT after HDF import.
- The current module copies between userspace and coherent buffers. That is
  acceptable for a correctness probe but not the final zero-copy performance
  target.
- Runtime DMAengine behavior is unproven until the matching bitstream and
  device tree are deployed together.
