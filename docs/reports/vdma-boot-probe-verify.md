# VDMA Boot Probe Verify

Date: 2026-06-30
Cycle ID: vdma-boot-probe-verify

## Objective

Boot the generated project TF-card image and verify the shortest Linux runtime
gate: UART login, Ethernet ping, VDMA probe evidence, and Linux display device
nodes.

## Scope

- Boot from the already-prepared TF card.
- Capture UART boot evidence.
- Configure Ethernet only at runtime if DHCP is absent.
- Inspect kernel/device-node evidence for VDMA, DRM, framebuffer, and video
  output.
- Do not rebuild PetaLinux, patch the device tree, or debug HDMI output in this
  cycle.

## Plan

```text
1. Confirm UART COM port and TF-card artifacts are present.
2. Capture boot log while the board boots from TF card.
3. Log in as root on UART.
4. Configure eth0 static IP if needed.
5. Ping board from PC.
6. Collect dmesg and /dev evidence for macb, VDMA, DRM, framebuffer, HDMI/DVI,
   and video nodes.
7. Decide whether the next cycle is HDMI dtb patching or lower-level boot
   repair.
```

## Results

Status: PASSED for the boot/probe gate.

The project-built TF-card image boots to userspace on the connected board. The
login credentials for this generated PetaLinux image are:

```text
user: root
password: root
```

Runtime kernel identity:

```text
Linux vdma-hdmi-minimal-bionic 4.14.0-xilinx-v2018.3 #2 SMP PREEMPT Tue Jun 30 09:10:30 UTC 2026 armv7l GNU/Linux
console=ttyPS0,115200 earlyprintk
```

Ethernet result:

```text
eth0 MAC: 00:0A:35:00:1E:53
eth0 runtime IP: 192.168.1.10/24
eth0 link: 1000/Full
PC ping 192.168.1.10: 4 sent, 4 received, 0% loss
```

VDMA result:

```text
dmesg:
xilinx-vdma 43000000.dma: Xilinx AXI VDMA Engine Driver Probed!!

sysfs:
/sys/bus/platform/devices/43000000.dma -> ../../../devices/soc0/amba_pl/43000000.dma
/sys/bus/platform/devices/43000000.dma/driver -> ../../../../bus/platform/drivers/xilinx-vdma

compatible:
xlnx,axi-vdma-6.3
xlnx,axi-vdma-1.00.a

interrupts:
00 00 00 00 00 00 00 1d 00 00 00 04
00 00 00 00 00 00 00 1e 00 00 00 04
```

Display-device result:

```text
ls: /dev/dri: No such file or directory
ls: /dev/fb*: No such file or directory
```

Conclusion:

```text
The base project image boots, Ethernet works, and the VDMA device-tree node
probes under Linux. HDMI/display output is not ready yet because no DRM or
framebuffer device node appears. The next cycle should be an HDMI device-tree
patch/repack cycle, not a lower-level boot or Vivado interrupt repair cycle.
```

## Evidence

Raw evidence under `build/vdma-boot-probe-verify/`:

```text
uart_newline_probe.log
uart_probe_session_root_root.log
uart_sysfs_vdma_probe_session.log
```

Command evidence:

```text
COM ports:
COM4, COM8, COM3, COM10, COM9, COM16, COM13

Board UART:
USB-SERIAL CH340 (COM16)

PC ping:
Reply from 192.168.1.10: bytes=32 time=1ms TTL=64
Reply from 192.168.1.10: bytes=32 time<1ms TTL=64
Reply from 192.168.1.10: bytes=32 time<1ms TTL=64
Reply from 192.168.1.10: bytes=32 time<1ms TTL=64
Packets: Sent = 4, Received = 4, Lost = 0 (0% loss)
```

## Residual Risks

- A full cold-boot UART log was not captured because the board was already at
  the login prompt when probed. This is acceptable for this cycle because
  userspace login, kernel identity, Ethernet, and VDMA probe were captured.
- HDMI output is not expected to work from Linux yet. The running image has no
  `/dev/dri` or `/dev/fb*` node, matching the third-party review concern that
  the downstream rgb2dvi / v_axi4s_vid_out / VTC chain is not represented as a
  Linux display pipeline.
- The static IP is runtime-only. It must be set again after each boot until a
  later image bakes in networking configuration.

## Third-party review

Reviewer: external audit, performed 2026-06-30 after cycle close.
Scope: cross-check the report's PASSED claim against the artifacts the cycle
left behind and verify the conclusions follow from the evidence presented.

### Verified against artifacts

- The kernel identity string in the report (`Linux vdma-hdmi-minimal-bionic
  4.14.0-xilinx-v2018.3 #2 ... Tue Jun 30 09:10:30 UTC 2026`) is consistent
  with the PetaLinux project's first build pass described by the previous
  cycle (`#2` build counter, same date prefix). The board really ran this
  image; this is not a boot-log fabrication.
- Reported `eth0 MAC 00:0A:35:00:1E:53` matches the MAC observed in the prior
  tf-card-linux-ping cycle, and `192.168.1.10/24` is the documented static IP
  for this Linux image. PC ping "4 sent 4 received 0%" matches the established
  route-gate behaviour — the GEM node in the PetaLinux-generated device tree
  produced a usable `macb` link at 1000/Full.
- `sysfs/devices/.../43000000.dma/driver -> xilinx-vdma` and the dmesg line
  `xilinx-vdma 43000000.dma: Xilinx AXI VDMA Engine Driver Probed!!` are the
  canonical probe evidence and match the decompiled device-tree VDMA node
  reviewed in the previous cycle (`reg = <0x43000000 0x10000>`, IRQ 29/30).
  The driver bind did happen, not just the kernel string presence.
- The honest "/dev/dri and /dev/fb* absent" findings are internally consistent
  with the prior review's residual concern about the missing downstream
  display chain. The cycle explicitly cites the third-party review when it
  says `HDMI/display output is not ready yet because no DRM or framebuffer
  device node appears`, which closes the loop on the deferred concern.

### Residual concerns not gated by closure criteria

1. **No cold-boot UART log was captured.** The report acknowledges this. It
   is acceptable for the scoped gate (login + ping + VDMA probe), but it
   means nobody has confirmed the early U-Boot → kernel handoff actually
   prints cleanly on a cold start. If a future boot fails, the absence of a
   cold-boot log will be a debugging gap.
2. **The displayed HDMI image during this cycle is not characterised.** This
   cycle did not capture or inspect what was on the HDMI port at boot. The
   next cycle later established that the colour bars seen on HDMI were a
   self-running PL pattern, not evidence of Linux-controlled output. This
   cycle's report did not claim HDMI evidence either way, which is honest,
   but the headline "boot and probe" might be read as carrying rough HDMI
   readiness that it should not.
3. **Static IP remains manual.** Acceptable for verification cycles, but a
   production-path image needs the network configuration baked in, otherwise
   the operator must UART-login after every cold boot to reach the board over
   Ethernet.

### Verdict

Accept as PASSED for the gate it declared. The boot/probe verification is
real and well-evidenced. The deliberate deferral of HDMI work to the next
cycle (matching the reviewer's earlier suggestion to split the two gates)
is the right call.
