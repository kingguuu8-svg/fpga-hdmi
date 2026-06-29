# Current Cycle

Status: paused. The petalinux-wsl-install-2018.3 cycle is blocked on the
PetaLinux installer download, which requires an AMD/Xilinx account browser
login. The user is remote and cannot perform the login. WSL proxy access has
been fixed (172.27.96.1:7890). When the user returns and downloads
petalinux-v2018.3-final-installer.run, resume this cycle using the steps in
docs/reports/petalinux-wsl-install-2018.3-2026-06-29.md.

## Rule

Open a cycle here before starting implementation work that should end in a
commit. A cycle must have a concrete objective, verification plan, and closure
criteria.

## Cycle Template

```text
Cycle ID:
Objective:
Scope:
Verification plan:
Board action:
Evidence target:
Closure criteria:
Highest-risk assumption this cycle falsifies:
Cheapest alternative way to falsify the same assumption:
```

The last two fields are the human review gate for opening a cycle. They force
the cycle author to state, before any work begins, which assumption is the
riskiest one being tested and whether a cheaper experiment could falsify the
same assumption. If the "cheapest alternative" line names a much shorter path
than the planned scope, the cycle direction should be reconsidered before
approval, not after debugging. These two lines exist to be read by a human at
cycle open time; they are not a self-audit checklist for cycle close.

## Active Cycle

```text
Cycle ID: petalinux-wsl-install-2018.3
Status: PAUSED — blocked on installer download (requires browser login).
Objective: install PetaLinux 2018.3 in WSL Ubuntu 22.04 so `petalinux`
  commands run and match the existing Vivado/SDK 2018.3 toolchain.
Scope: obtain the Linux `.run` installer, install it into WSL, source the
  settings script with `HOME=/root`, verify `petalinux --version` reports
  2018.3. Do not use the existing Windows installer under
  `/opt/xilinx-installer-2018.3` (it is Windows DLLs, not Linux PetaLinux).
Verification plan: run the installer in WSL, source settings, capture
  `petalinux --version` output.
Board action: none. This cycle changes host tooling only.
Evidence target: docs/reports/petalinux-wsl-install-2018.3-2026-06-29.md
  and docs/cycle-log.md.
Closure criteria:
  1. `petalinux` exists in WSL after sourcing the installed settings script.
  2. `petalinux --version` reports 2018.3.
  3. Report records install path, proxy/HOME handling, verification output.
Highest-risk assumption this cycle falsifies:
  PetaLinux 2018.3 can be installed and run inside WSL Ubuntu 22.04/root
  despite the tool's old host-OS expectations.
Cheapest alternative way to falsify the same assumption:
  Before downloading the full installer, use WSL shell checks to verify OS,
  HOME=/root, proxy reachability, and whether any existing /opt PetaLinux
  settings script already provides petalinux. (Done: none found.)
```

### Resume procedure

The cycle is paused because the PetaLinux installer download requires a
browser AMD/Xilinx account login. The investigation and environment checks
are complete. To resume:

1. Download `petalinux-v2018.3-final-installer.run` (~2-3GB) via one of:
   - AMD official (browser login):
     `https://account.amd.com/en/forms/downloads/xef.html?filename=petalinux-v2018.3-final-installer.run`
   - Baidu pan mirror (unverified, community-shared):
     `https://pan.baidu.com/s/1sLCRru2YJeAMLTd6sKFXeQ` extraction code `gp0x`
   Save to `C:\Users\中二哲人\Downloads\` or `E:\tmp\`.

2. In WSL, install:
   ```bash
   export HOME=/root
   export http_proxy=http://172.27.96.1:7890
   export https_proxy=http://172.27.96.1:7890
   cp /mnt/c/Users/中二哲人/Downloads/petalinux-v2018.3-final-installer.run /root/
   cd /root && chmod +x petalinux-v2018.3-final-installer.run
   ./petalinux-v2018.3-final-installer.run /opt/petalinux-v2018.3
   source /opt/petalinux-v2018.3/settings.sh
   petalinux --version
   ```

3. Verify `petalinux --version` prints 2018.3, then close this cycle and
   open the next: PetaLinux project build from the VDMA HDMI hardware design.

### Environment facts already confirmed

```text
WSL: Ubuntu 22.04.5 LTS, root, 908GB free
WSL proxy: http://172.27.96.1:7890 (Clash allow-lan, verified google=302)
Vivado/SDK 2018.3: present in /opt/Xilinx (not PetaLinux)
/opt/xilinx-installer-2018.3: Windows DLLs, do not use for PetaLinux
TF card: partitioned for PetaLinux dual-boot (1GB FAT32 D: + 57GB rootfs F:)
  ext4 format of rootfs partition happens at burn time, not now.
```

## Recently Closed Cycle

```text
Cycle ID: baseline-checkpoint
Commit: bef3299
Result: committed the eth-ps-pl-hdmi-pass-through work surface (52 files) into
  git; working tree is clean; route-pivot documents no longer dangle-reference
  untracked files. See docs/cycle-log.md for the full entry.
```

## Resolved Route Gate

The TF-card Linux ping route gate PASSED on 2026-06-29. The paused cycle's
closure criterion is met: official Linux responds to ping, selecting the
Linux/socket route.

```text
Cycle ID: eth-ps-pl-hdmi-pass-through (route-gate phase)
Result: PASSED. Official Linux boots from TF card, eth0 link up at 1000/Full,
  PC ping 192.168.1.10 = 4/4 received, 0% loss.
Evidence: docs/reports/tf-card-linux-ping-2026-06-29.md
Decision: Outcome A — proceed on Linux/socket route, retire hand-written
  baremetal RGMII bridge.
```

## Current Decision

The active implementation route is now confirmed by hardware evidence:

```text
PC UDP RGB888 frame -> Linux userspace socket receiver -> DDR framebuffer
-> VDMA MM2S -> v_axi4s_vid_out -> rgb2dvi -> HDMI
```

The hand-written baremetal RGMII bridge + lwIP route is retired. It was
verified as a dead end: the same physical path that fails under the hand-written
bridge works perfectly under Linux + official macb driver (RX errors=0, ping
0% loss). The bridge code remains in the repo as negative evidence only.

## Current Evidence

Known-good subchains:

```text
Official VDMA HDMI image passed on connected board and PC HDMI capture.
Official pure-PL UDP loopback passed over the same PC/RJ45/RTL8211E path.
Official Linux boots from TF card, eth0 1000/Full, RX errors=0, ping 0% loss.  [NEW 2026-06-29]
Project baremetal board-to-PC UDP heartbeat works (but PC-to-board RX does not).
```

Retired dead end:

```text
Project baremetal PC-to-board UDP RX through the hand-written RGMII bridge:
rx=0, rxfcs rising, no frames reach lwIP. Root cause confirmed by the Linux
ping result as the hand-written bridge BUFIO/BUFG crossing, not the physical
layer. Do not resume this work.
```

Next cycle direction:

```text
Implement the Linux/socket video receiver: PC UDP -> Linux socket -> DDR
framebuffer write -> VDMA HDMI output. Start at the smallest frame size that
proves the loop, then scale up.
```
