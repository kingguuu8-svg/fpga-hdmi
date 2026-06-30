# PetaLinux VDMA HDMI Minimal Project

Date: 2026-06-30
Cycle ID: petalinux-vdma-hdmi-minimal-project

## Objective

Create and build a minimal PetaLinux 2018.3 project from the existing VDMA HDMI
hardware description, then prepare the TF-card boot partition with generated
boot artifacts.

## Inputs

Hardware description:

```text
build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/eth_ps_vdma_hdmi_stage1_board.hdf
```

Bitstream:

```text
build/eth-ps-pl-hdmi-pass-through/vdma-board/eth_ps_vdma_hdmi_stage1_board.bit
```

Toolchain:

```text
PetaLinux 2018.3 at /opt/petalinux-v2018.3
Build host: Ubuntu 18.04 chroot under WSL Ubuntu-22.04
Linux user petalinux
```

## Plan

```text
1. Verify PetaLinux command environment.
2. Verify HDF and bitstream inputs.
3. Create PetaLinux project under build/petalinux/.
4. Import hardware description.
5. Build image.ub.
6. Package BOOT.BIN.
7. Copy BOOT.BIN and image.ub to D:\ if generated artifacts are valid.
```

## Results

Status: PASSED.

The first full build attempt exposed a real hardware-description defect: the
VDMA interrupt outputs were not connected to the PS interrupt controller. The
fix was made in the Vivado BD generator before continuing the PetaLinux build:

```text
axi_vdma_0/mm2s_introut -> vdma_irq_concat/In0
axi_vdma_0/s2mm_introut -> vdma_irq_concat/In1
vdma_irq_concat/dout    -> processing_system7_0/IRQ_F2P[15:0]
unused IRQ_F2P bits     -> xlconstant 0
```

The corrected hardware design rebuilt successfully:

```text
Command:
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1

Marker:
STAGE1_VDMA_BOARD_BUILD_OK

Timing:
WNS = 0.347 ns

DRC:
0 errors, 0 critical warnings
```

The corrected HDF contains the required Linux-visible IRQ path:

```text
PCW_IRQ_F2P_INTR = 1
C_NUM_F2P_INTR_INPUTS = 16
processing_system7_0/IRQ_F2P -> vdma_irq_concat/dout
axi_vdma_0/mm2s_introut -> vdma_irq_concat/In0
axi_vdma_0/s2mm_introut -> vdma_irq_concat/In1
```

PetaLinux then built successfully in the Ubuntu 18.04 chroot:

```text
petalinux-config --get-hw-description /mnt/e/main/fpga-hdml/build/eth-ps-pl-hdmi-pass-through/vdma-board/reports --oldconfig
petalinux-build

Result:
[INFO] successfully built project
Tasks Summary: Attempted 3065 tasks ... all succeeded.
```

Boot artifacts were generated and copied to the TF-card boot partition:

```text
BOOT.BIN  4,577,736 bytes
image.ub  9,980,104 bytes
TF card:  D:\, label ZYNQBOOT, FAT32, removable, 1GB partition
```

SHA256 verification:

```text
BOOT.BIN:
3311eae61f3da9ec30aab6ae12488cf31b5f2a5df060130d2bf26d4a35f56335

image.ub:
8fc698d3d823f9797f2cef6c598b88af4e3b8d5bd82cedcb04911b4286828cc3
```

The hashes matched across all three locations:

```text
PetaLinux project output:
\\wsl$\Ubuntu-22.04\home\petalinux\fpga-hdml-build\petalinux\vdma-hdmi-minimal-bionic\images\linux\

Repo artifact snapshot:
build\petalinux\vdma-hdmi-minimal-bionic\images\

TF-card boot partition:
D:\
```

## Evidence

Key command evidence:

```text
Vivado build marker:
STAGE1_VDMA_BOARD_BUILD_OK bitstream=...eth_ps_vdma_hdmi_stage1_board.bit wns=0.347

PetaLinux build marker:
[INFO] successfully built project

Bootgen marker:
INFO: Binary is ready.

TF-card volume:
DriveLetter: D
FileSystemLabel: ZYNQBOOT
FileSystem: FAT32
DriveType: Removable
```

Verification boundaries:

```text
Simulation:
Not run. The change is a Vivado BD interrupt-topology fix for Linux
device-tree generation. The automated gate used here is Vivado BD validation,
synthesis, implementation, timing, DRC, HDF inspection, and PetaLinux
device-tree generation.

Board programming / boot:
Not run. This cycle's board action is limited to writing the TF-card boot
partition. Booting the generated image is the next cycle.
```

Important negative evidence:

```text
Direct PetaLinux 2018.3 builds on Ubuntu 22.04 are not the shortest stable path.
They reached a compatibility patch treadmill in native Yocto tools. The working
route is the Ubuntu 18.04 chroot at /opt/chroots/ubuntu18-petalinux2018.

The original HDF failed device-tree generation:
ERROR: axi_vdma_0: mm2s_introut port is not connected
ERROR: axi_vdma_0: s2mm_introut port is not connected
```

## Residual Risks

- The generated image has not yet been booted on the board. This cycle only
  validates build/package/write-card.
- The project image may not preserve the known-good official Linux Ethernet
  behavior until the next boot-verification cycle proves UART login, eth0 link,
  static IP, and ping.
- HDMI/VDMA Linux runtime behavior is not verified yet. The next cycle must
  inspect kernel logs and device-tree status after boot.
- The Ubuntu 18.04 chroot bind mounts are runtime state. If WSL restarts, mount
  `/opt/petalinux-v2018.3`, `/home`, `/mnt/e`, `/proc`, `/sys`, `/dev`, and a
  tmpfs `/dev/shm` before running PetaLinux again.

## Third-party review

Reviewer: external audit, performed 2026-06-30 after cycle close.
Scope: independently verify physical artifacts and inspect the generated FIT
image's device tree and kernel content, rather than trusting the report's
PASSED claim.

### Independently verified (claims hold up)

- TF-card D: artifacts present: BOOT.BIN (4577736 bytes), image.ub (9980104
  bytes). SHA256 of both files matches the hash in the cycle report exactly.
- Ubuntu 18.04 chroot at `/opt/chroots/ubuntu18-petalinux2018` is a real
  directory tree, not a stub. PetaLinux project directory exists with real
  build output under images/.
- The BD Tcl interrupt fix in `create_ps_emio_vdma_hdmi_bd.tcl` is the standard
  Zynq fabric interrupt topology: `PCW_IRQ_F2P_INTR=1` + `PCW_USE_FABRIC_INTERRUPT=1` on PS7, an
  xlconcat (16 ports) aggregating `axi_vdma_0/mm2s_introut` and `s2mm_introut`
  into `IRQ_F2P`, and an xlconstant=0 feeding the remaining 14 unused IRQ slots.
  This is the textbook solution and the right fix for the device-tree generator
  rejecting unconnected VDMA interrupt ports.
- Extracted the new image.ub FIT blob and decompiled its device tree: the VDMA
  node is correct and complete.
  - `reg = <0x43000000 0x10000>` matches the HDF address map.
  - `compatible = "xlnx,axi-vdma-6.3\0xlnx,axi-vdma-1.00.a"` — full compatible
    string present.
  - `interrupts = <0x00 0x1d 0x04 0x00 0x1e 0x04>` — IRQ 29 / 30, with the two
    `dma-channel@` sub-nodes carrying matching per-channel IRQ lines.
  - Clocks, `xlnx,num-fstores`, address-width all populated.
- The GEM/ethernet node is intact: `ethernet@e000b000 status="okay"
  phy-mode="gmii"`. Route-gate networking capability is preserved in the new
  device tree.
- Kernel strings search confirms VDMA driver is compiled in: "Xilinx AXI VDMA
  Engine Driver Probed!!" and the `xilinx-vdma` symbols are present. An
  unexpected bonus: "Xilinx DRM KMS support for Xilinx" is also in the kernel
  — the PetaLinux default defconfig enabled Xilinx DRM KMS, which the original
  all-test image did not surface. HDMI output may therefore have a real Linux
  display stack to attach to, not just a raw VDMA node.

### Residual concerns the closure criteria did not cover

1. **HDMI output chain is not in the device tree.** `grep -iE "hdmi|dvi|rgb"`
   on the decompiled dtb returns zero matches. The `rgb2dvi_0` IP and any
   `v_axi4s_vid_out` / video-timing-controller IP from the Vivado BD have no
   device-tree nodes. The Xilinx device-tree generator does not produce nodes
   for the Digilent rgb2dvi IP. Consequence: VDMA will probe and be usable as a
   DMA engine from userspace, but the downstream HDMI video pipeline is invisible
   to Linux — HDMI output will not work by simply booting this image. The
   VDMA-probe milestone and the HDMI-output milestone are two separate gates;
   the cycle report bundles them into one unverified "HDMI/VDMA Linux runtime
   behavior" line, which understates the gap.
2. **No board boot yet.** The whole verification chain is offline artifact
   inspection plus PetaLinux's own build-pass marker. The dmesg "VDMA Engine
   Driver Probed" string being in the kernel binary only proves the driver was
   compiled in; the actual probe requires the running kernel to match the
   device-tree node to the driver and reach `->probe()`. A boot test is the
   only way to confirm a real `/dev/dri/card0` or `/dev/fb*` entry appears.
3. **The chroot bind-mount state is genuinely fragile.** If WSL is restarted
   the mounts must be re-established before any incremental build. This is an
   operational hazard for future cycles, not a defect in the artifacts already
   committed.

### Reviewer's suggested next cycle split

To avoid bundling two gates, the reviewer suggests splitting the natural next
step into two cycles rather than one:

- `vdma-boot-probe-verify`: insert the card, set SD boot, POR RST, capture
  UART, confirm Linux boots, confirm `dmesg` shows the VDMA probe line, confirm
  `eth0` still links and pings, list `/dev/dri` or `/dev/fb*`. Trims the cheapest
  possible falsification of "VDMA works under Linux on this board".
- `hdmi-dtb-patch`: only opened if the first cycle's VDMA probe succeeds but
  HDMI does not output. Hand-author the rgb2dvi / v_axi4s_vid_out / VTC
  device-tree fragment (these are generic MIPI / DRM / video-out nodes, no
  Vivado BD re-edit required), dtc-compile back into the dtb, mkimage-repack
  the image.ub, re-boot and capture HDMI on the PC capture device.

### Verdict

Accept the cycle as PASSED for the build/package/write-card scope it declared.
The artifacts are real, the BD fix is correct, the device tree's VDMA node is
complete. Be aware that the headline "build PetaLinux VDMA HDMI TF image"
implies more HDMI-readiness than the device tree actually delivers — HDMI
output is the next but one milestone, not this one.
