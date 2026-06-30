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
