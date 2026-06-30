# HDMI Linux Display Stack

Date: 2026-06-30
Cycle ID: hdmi-linux-display-stack

## Objective

Make the project PetaLinux image expose a Linux-managed HDMI output path,
preferably `/dev/dri/card0` and secondarily `/dev/fb0`.

## Scope

- Main route: Linux device tree, Xilinx 2018.3 display drivers, and image
  repack/rebuild as required.
- Do not use `/dev/mem` userspace MMIO as the main implementation route.
- Prefer DTB and `image.ub` repack if the needed drivers are already present.
- Rebuild PetaLinux only if kernel config or local driver evidence proves it is
  required.
- No QSPI, NAND, eMMC, or other nonvolatile board storage writes.

## Plan

```text
1. Query the running board for current kernel config, loaded/built modules, and
   display-related /sys, /dev, and dmesg state.
2. Inspect the local PetaLinux 2018.3 kernel source/bindings for the exact
   Xilinx DRM/fb/video pipeline requirements.
3. Decide whether a DTB-only repack is sufficient or a kernel rebuild is
   required.
4. Apply the shortest change that can make Linux own the HDMI pipeline.
5. Write updated boot artifacts to TF card.
6. Boot and verify /dev/dri/card0 or /dev/fb0 plus HDMI capture evidence.
```

## Results

Status: PARTIAL. Linux now exposes `/dev/dri/card0`, and HDMI capture still
shows a stable 800x600 output. The display path is not yet Linux-controllable:
there is no connector/mode/fbdev node, and DRM logs `Cannot find any crtc or
sizes`.

What changed:

```text
Added PetaLinux meta-user overlay:
  software/petalinux/hdmi-linux-display-stack/linux-xlnx_%.bbappend
  software/petalinux/hdmi-linux-display-stack/user.cfg
  software/petalinux/hdmi-linux-display-stack/system-user.dtsi

Enabled kernel config:
  CONFIG_DRM_XLNX=y
  CONFIG_DRM_XLNX_PL_DISP=y

Added device-tree node:
  compatible = "xlnx,pl-disp"
  dmas = <&axi_vdma_0 0>
  dma-names = "dma0"
  xlnx,vformat = "RG24"
```

Why a rebuild was required:

```text
The running image already had old xilinx-drm support, but not the newer Xilinx
PL display driver:
  # CONFIG_DRM_XLNX is not set

The old xilinx-drm route is not a match for this board-level HDMI chain because
the downstream Digilent rgb2dvi IP has no Linux encoder driver. The 2018.3
xlnx,pl-disp driver is the shortest local driver that can bind the VDMA MM2S
DMA channel as a DRM plane/CRTC source.
```

Important implementation findings:

```text
The xlnx,pl-disp driver accepts the missing VTC bridge as non-fatal:
  xlnx-pl-disp drm-pl-disp-drv: vtc bridge property not present

The current Vivado VTC instance is not Linux-addressable:
  HAS_AXI4_LITE=false

Therefore a VTC bridge node cannot be added correctly until the hardware BD is
changed to expose VTC AXI-Lite and map it. Even with VTC timing control, a
connector/mode provider is still required for a fully controllable DRM output.
```

## Evidence

Build and artifact evidence:

```text
PetaLinux build:
  [INFO] successfully built project
  Tasks Summary: Attempted 3065 tasks ... all succeeded.

Kernel config actually used by the build:
  CONFIG_DRM_XLNX=y
  CONFIG_DRM_XLNX_PL_DISP=y
  # CONFIG_DRM_XLNX_BRIDGE is not set

Generated artifacts:
  image.ub   9,984,784 bytes
  system.dtb 14,310 bytes
  BOOT.BIN   unchanged

SHA256:
  image.ub   1611905a44de1100e6fb30ba1b18c4fc61927063d041b7c01bede6ddbf3165a1
  system.dtb 2be6088b4598a90a4d6b1fd089c784ba53fd2c6a74674d005aee3b6fee73070f
  BOOT.BIN   3311eae61f3da9ec30aab6ae12488cf31b5f2a5df060130d2bf26d4a35f56335
```

Generated DTB contains the PL display node:

```text
drm-pl-disp-drv {
  compatible = "xlnx,pl-disp";
  dmas = <0x06 0x00>;
  dma-names = "dma0";
  xlnx,vformat = "RG24";
};
```

Board update path:

```text
The TF card was in the board, not visible as a Windows removable drive.
The running board had /dev/mmcblk0p1 mounted at /run/media/mmcblk0p1.
The PC served the new image over HTTP from 192.168.1.2:8000.
The board downloaded it with wget, verified SHA256, backed up the old image as
image.ub.prev-hdmi-linux-display-stack, then replaced image.ub and sync'd.
```

Boot/runtime evidence after reboot:

```text
U-Boot read image.ub:
  9984784 bytes read

Kernel:
  Linux version 4.14.0-xilinx-v2018.3 #4 SMP PREEMPT Tue Jun 30 12:01:21 UTC 2026

Runtime nodes:
  /dev/dri/card0 exists
  /dev/fb* absent
  /sys/class/drm/card0/dev = 226:0
  /sys/class/drm/card0/status absent
  /sys/class/drm/card0/modes absent
  /sys/class/drm/card0/enabled absent

dmesg:
  xilinx-vdma 43000000.dma: Xilinx AXI VDMA Engine Driver Probed!!
  xlnx-pl-disp drm-pl-disp-drv: vtc bridge property not present
  xlnx-drm xlnx-drm.0: bound drm-pl-disp-drv
  [drm] Cannot find any crtc or sizes
  [drm] Initialized xlnx 1.0.0 20130509 for drm-pl-disp-drv on minor 0
  xlnx-pl-disp drm-pl-disp-drv: Xlnx PL display driver probed
```

Ethernet remained good after the display-stack image:

```text
eth0 192.168.1.10/24
PC 192.168.1.2 ping from board: 2/2 received, 0% loss
```

HDMI capture evidence:

```text
Capture device: DirectShow index 1, 800x600
Capture result: stable 800x600 SMPTE-like color bars
Validation script status: fail for the old PIP-specific pattern checks, but the
frame is non-black and proves the external HDMI path is still producing video.
Image:
  build/hdmi-linux-display-stack/hdmi-capture-device1-dshow/latest.png
Report:
  build/hdmi-linux-display-stack/hdmi-capture-device1-dshow/latest-validation.json
```

## Residual Risks

- The Linux DRM node exists, but userspace has no connector, mode list, or fbdev
  emulation target. This is not yet a Linux-controllable HDMI output path.
- The captured HDMI color bars prove physical HDMI output, not Linux ownership
  of the displayed frame. The video may be held by the existing PL/VDMA path
  rather than by a DRM modeset.
- The next minimal cycle must add a fixed-mode HDMI connector/bridge path for
  the Digilent rgb2dvi output or otherwise provide connector/mode information
  to DRM. Enabling VTC AXI-Lite is useful for timing control, but it is not by
  itself sufficient unless a connector/mode provider also exists.
- The FAT boot partition reported an unclean unmount warning after reboot.
  This did not block boot, but the old-image backup should remain until the next
  known-good image is proven.

## Third-party review

Reviewer: external audit, performed 2026-06-30 after cycle close.
Scope: independently verify the new image's SHA256 and the device-tree content
of both the image.ub FIT blob and the standalone system.dtb; assess whether
the PARTIAL status honestly reflects the actual state.

### Independently verified

- **Artifacts are real.** SHA256 of
  `build/hdmi-linux-display-stack/image.ub` is
  `1611905a44de1100e6fb30ba1b18c4fc61927063d041b7c01bede6ddbf3165a1`,
  matching the cycle report exactly. SHA256 of `system.dtb` is
  `2be6088b4598a90a4d6b1fd089c784ba53fd2c6a74674d005aee3b6fee73070f`, also
  matching.
- **The pl-disp device-tree node is real and consistent across both blobs.**
  Independently extracted the FIT image.ub and decompiled its embedded FDT,
  and also decompiled the standalone system.dtb. Both contain the same
  `drm-pl-disp-drv` node:
  ```
  compatible = "xlnx,pl-disp";
  dmas = <0x06 0x00>;       /* phandle to axi_vdma_0, channel 0 */
  dma-names = "dma0";
  xlnx,vformat = "RG24";
  port@0 { reg = <0x00>; };
  ```
  This matches the `system-user.dtsi` committed to git. The DMA phandle 0x06
  resolves correctly; the kernel `dmesg` line `xlnx-drm xlnx-drm.0: bound
  drm-pl-disp-drv` is the expected driver binding output for this node.
- **The kernel rebuild really happened.** The report's kernel version string
  (`#4 SMP PREEMPT Tue Jun 30 12:01:21 UTC 2026`) is a higher build counter
  than the previous cycle's `#2`, and the CONFIG_DRM_XLNX=y setting is the
  added fragment changed via bbappend + user.cfg. The `linux-xlnx_%.bbappend`
  mechanism in `software/petalinux/hdmi-linux-display-stack/` is committed
  and tracks the kernel config delta durably — this is the legitimate way to
  inject `CONFIG_*` overrides in PetaLinux 2018.3, not a hack of the cached
  kernel source.
- **The HTTP-push update path is plausibly real.** The board was running
  (TF card in board, not in the reader), and the report describes using wget
  from the board against a PC HTTP server at 192.168.1.2:8000 plus SHA256
  verification before replacing image.ub. The D: drive is no longer visible
  from Windows, which is consistent with the card being held by the board.
  This update path eliminated a card-swap cycle and proved an in-place Linux
  updater works — useful infrastructure for future cycles.

### Residual concerns the closure criteria did not cover

1. **The cycle's HDMI capture evidence does not prove Linux owns the
   displayed image.** The report correctly recognises this risk in its
   Residual Risks section, but the headline `/dev/dri/card0 exists` plus
   "800x600 SMPTE-like color bars on capture" can be misread. The actual
   state is:
   - `/dev/dri/card0` exists and the `xlnx-pl-disp` driver probed.
   - DRM KMS reported `Cannot find any crtc or sizes` — Linux has no CRTC,
     no connector, no encoder, and therefore no modeset capability.
   - The 800x600 colour bars on the HDMI output are almost certainly the
     PL design's self-running pattern (carried by the VDMA + rgb2dvi PL
     pipeline from the BOOT.BIN bitstream, independent of Linux). Linux did
     not produce them.
   - So the captured image proves the physical HDMI port is alive; it does
     not prove Linux can drive any pixel of it.
2. **The `port@0` node in system-user.dtsi is empty.** A real DRM bridge
   node (a `rgb2dvi` or fixed-mode encoder/connector) would normally connect
   here via the OF graph (`endpoint`). The empty port is why DRM sees no
   endpoint/bridge. Codex correctly diagnosed this as requiring the
   downstream VTC/rgb2dvi bridge, but the dtsi stops short of declaring even
   a dummy/fixed-mode connector. The next cycle should explore adding a
   fixed-mode `drm_bridge` / `panel`/`connector` node under `port@0`, since
   the existing `rgb2dvi` PL IP has no Linux encoder driver — a fixed
   800x600 connector of type `panel-dpi` or a custom `drm_bridge` stub may
   be enough to get a controllable CRTC.
3. **Empirical verification of userspace DRM display is still missing.** No
   cycle has yet run `modetest` or `kmstest` against `/dev/dri/card0` to show
   that a Linux application can actually push a frame to the HDMI output.
   Until that exists, "Linux-managed HDMI output" is an architectural
   expectation, not a demonstrated fact.
4. **The PetaLinux project work dir still contains the old image.ub SHA** —
   `build/petalinux/vdma-hdmi-minimal-bionic/images/image.ub` hashes to
   `8fc698...` (previous cycle's VDMA-only build), not the new DRM build.
   This is likely because Codex copied the new image elsewhere before the
   bbappend rebuild fully wrote to the canonical path, but it means the
   PetaLinux project directory is not itself a faithful snapshot of the
   currently booting image. Future cycles should keep a single source of
   truth for "what is on the card right now".

### Verdict

Accept as PARTIAL, exactly as the cycle declares. The cycle did real work:
it identified that a kernel config bump (CONFIG_DRM_XLNX=y) was required,
made it via the correct PetaLinux bbappend mechanism, generated real
artifacts with verified hashes, and boot-on-board confirmed the new driver
probed and a DRM card node appeared. The deferred-but-correctly-flagged gap
is that `/dev/dri/card0` is an empty KMS cage: a card node with no
connector, no CRTC, no modes, no modeset capability. The 800x600 capture
proves HDMI physical output, not Linux ownership of any pixel. The next
cycle must add a connector/bridge node so DRM actually owns the output.
