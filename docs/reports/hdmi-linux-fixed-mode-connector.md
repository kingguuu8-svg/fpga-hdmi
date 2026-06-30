# HDMI Linux Fixed-Mode Connector

Date: 2026-06-30
Cycle ID: hdmi-linux-fixed-mode-connector

## Objective

Make the existing Linux DRM device expose a usable fixed-mode output for the
board's rgb2dvi HDMI chain, then prove that Linux userspace can change the HDMI
capture image.

## Scope

- Prefer an existing Linux 4.14/Xilinx 2018.3 DRM connector, bridge, or panel
  path that can be described through device tree.
- If no compatible path exists, add the smallest kernel-side fixed-mode output
  component required by the Xilinx DRM component graph.
- Do not use userspace `/dev/mem` register ownership.
- Do not change Vivado hardware unless the selected Linux path requires it.
- Update only TF-card boot files; do not write QSPI, NAND, eMMC, or other board
  nonvolatile storage.

## Verification Plan

```text
1. Inspect the local kernel source and bindings for a reusable fixed-mode path.
2. Record why the selected path is compatible with xlnx-pl-disp.
3. Build the PetaLinux image and verify kernel config, DT, and artifact hashes.
4. Boot the board and require a DRM connector/mode or /dev/fb0.
5. Run a minimal Linux userspace display test.
6. Capture HDMI and prove the Linux test changed the displayed frame.
```

## Results

Status: PASSED.

## Driver-Path Investigation

The local Xilinx 2018.3 kernel contains generic panel and DRM bridge drivers,
but they cannot be attached directly to this pipeline using only device tree:

```text
xlnx-pl-disp creates a logical xlnx-drm component master.
Every remote OF graph endpoint is added to the component match list.
panel-simple and generic bridge drivers register a panel/bridge only.
They do not call component_add(), so the xlnx-drm master would wait for a
component that never joins the component framework.
```

The selected minimum path is therefore a small Xilinx component driver:

```text
xlnx-pl-disp endpoint
  -> fpga-hdml,xlnx-fixed-hdmi component
  -> DRM TMDS encoder
  -> always-connected HDMI-A connector
  -> one display-timings mode
```

The driver has no MMIO and does not reprogram the PL. It only supplies the DRM
objects missing from the previous cycle. The physical timing remains generated
by the existing fixed VTC; exact timing facts are owned by
`docs/boards/hellofpga-smart-zynq-sl.md`, and the active resolution and pixel
format remain owned by `docs/project-roadmap.md`.

## First Board Probe And Root Cause

Kernel build `#10` successfully created the missing Linux display objects:

```text
xlnx-drm bound drm-pl-disp-drv
xlnx-fixed-hdmi bound with the configured mode
/dev/dri/card0 present
/dev/fb0 present
connector status connected
connector mode list contains the configured mode
```

The framebuffer did not yet affect HDMI. VDMA reported error `0x40`, which the
Xilinx DMA driver defines as `DMA_DEC_ERR`. Live registers showed the expected
height, byte width, and stride, but the framebuffer address was `0x1f100000`.
The official VDMA DDR window is recorded in
`docs/boards/hellofpga-smart-zynq-sl.md`; that Linux CMA allocation was outside
the PL master's decode window.

The corrective action is to reserve the default Linux CMA region inside the
official VDMA address map. This preserves kernel ownership of the display
pipeline.

## Implementation

- Added `CONFIG_DRM_XLNX_FIXED_HDMI=y`.
- Added a small Xilinx component driver that creates a TMDS encoder,
  always-connected HDMI-A connector, and one device-tree mode.
- Connected `xlnx-pl-disp` to the fixed HDMI component through OF graph
  endpoints.
- Reserved the default CMA pool inside the VDMA-visible DDR window.
- Extended `tools/capture_hdmi.py` with an `rgb-stripes` validation profile.

During the first kernel build, the new-file patch hunk declared fewer lines
than the file contained. `patch` accepted the hunk but omitted the platform
driver registration, producing an object without an initcall. The hunk length
was corrected, and the rebuilt kernel map contains the driver init, probe, and
platform-driver symbols. This intermediate image was not accepted as cycle
evidence.

## Build Verification

```text
PetaLinux build: 3065 tasks attempted, all succeeded
Kernel config: CONFIG_DRM_XLNX_FIXED_HDMI=y
checkpatch: 0 errors, 1 MAINTAINERS warning
Final image.ub:
  size 9986360 bytes
  SHA-256 206566d93db6d417b4912e223ea6cc3886bedad7e05e0781df89bd429d09cd46
Final system.dtb:
  size 15139 bytes
  SHA-256 6d07b7e4393afd561761d27ee40d91927eebd7870c051456647c579807f6635d
```

The decompiled final DT contains the fixed HDMI graph, the board mode owned by
`docs/boards/hellofpga-smart-zynq-sl.md`, and the fixed CMA reservation.

## Board Verification

The board downloaded the final `image.ub` over Ethernet, verified the same
SHA-256 before and after copying it to the TF-card FAT boot partition, retained
the previous image as a backup, and rebooted from TF card.

Final runtime evidence:

```text
DRM card: /dev/dri/card0
Framebuffer: /dev/fb0
Connector: connected
Mode list: matches docs/project-roadmap.md
Framebuffer format: 24 bits per pixel, 2400-byte stride
CMA pool: 0x0e000000, 16 MiB
VDMA MM2S start address: 0x0e100000
VDMA status before and after write: 0x00010000
VDMA decode errors: none
Atomic flip timeouts: none
```

Before the userspace write, HDMI capture showed the Linux framebuffer login
console. The board then downloaded a deterministic three-stripe raw frame,
verified its SHA-256, and wrote it to `/dev/fb0`. The HDMI capture changed to
blue, green, and red horizontal stripes.

Automated capture validation passed:

```text
profile: rgb-stripes
top blue RGB mean: [0.05, 0.05, 254.61]
middle green RGB mean: [0.0, 255.0, 0.0]
bottom red RGB mean: [255.0, 0.0, 0.0]
result: HDMI_CAPTURE_OK
```

## Evidence

- `build/hdmi-linux-fixed-mode-connector-cma-fix/petalinux-build.log`
- `build/hdmi-linux-fixed-mode-connector/sha256sum-cma-fix.txt`
- `build/hdmi-linux-fixed-mode-connector/uart-reboot-cma-fix.log`
- `build/hdmi-linux-fixed-mode-connector/uart-final-acceptance.log`
- `build/hdmi-linux-fixed-mode-connector/hdmi-cma-before-pattern/latest.png`
- `build/hdmi-linux-fixed-mode-connector/hdmi-cma-after-pattern-verified/latest-validation.json`
- `build/hdmi-linux-fixed-mode-connector/hdmi-cma-after-pattern-verified/latest.png`

## Result

The fixed rgb2dvi chain is now represented as a Linux DRM connector and mode,
and Linux userspace can change the physical HDMI output through `/dev/fb0`.
The next cycle can implement the Linux UDP frame receiver without revisiting
connector discovery, VTC ownership, or the VDMA DDR window.

Residual risks:

- The connector is intentionally always connected and does not read HDMI EDID
  or hot-plug state.
- The physical VTC remains fixed and cannot be changed by DRM.
- The framebuffer console can overwrite pixels; the video receiver should
  disable or avoid console rendering when it takes ownership.
