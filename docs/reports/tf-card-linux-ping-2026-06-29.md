# TF-Card Linux Ping Route Gate Result

Date: 2026-06-29

## Outcome

**PASSED.** The official vendor Linux image boots from TF card on the connected
HelloFPGA Smart ZYNQ SL board, Ethernet comes up over the PL-side RTL8211E
path, and the PC can ping the board with 0% loss.

This is route gate Outcome A per `docs/reports/tf-card-linux-resume-2026-06-26.md`.
The project should proceed on the Linux/socket route and retire the hand-written
baremetal RGMII bridge as the primary network path.

## Experiment

### TF card preparation

```text
Source: C:/Users/中二哲人/Downloads/Smart_ZYNQ_SP2_LINUX_ALL_TEST_20240906.zip
Contents: BOOT.BIN (14663700 bytes) + image.ub (10003028 bytes)
Card: SanDisk 64GB, formatted as 1GB FAT32 partition (label ZYNQBOOT)
Reason for 1GB partition: Windows format does not offer FAT32 above 32GB;
Zynq boot ROM only reads the first primary partition, 1GB is sufficient.
```

### Boot sequence

1. SD card inserted, board boot mode set to SD via DIP switch, POR RST pressed.
2. U-Boot 2018.01 loaded image.ub from SD (10003028 bytes, 16.9 MiB/s).
3. Linux 4.14.0-xilinx-v2018.3 kernel booted, SMP, both Cortex-A9 CPUs up.
4. `macb` driver bound `e000b000.ethernet eth0`, link up at 1000/Full.
5. udhcpc tried DHCP (no DHCP server on direct link), no lease obtained.
6. Linux userspace reached login prompt; Dropbear SSH started.

### IP configuration

Logged in as root via UART (no password). Set static IP manually:

```text
ifconfig eth0 192.168.1.10 netmask 255.255.255.0 up
```

Result:

```text
eth0: inet addr:192.168.1.10  Bcast:192.168.1.255  Mask:255.255.255.0
      UP BROADCAST RUNNING MULTICAST
      RX packets:24 errors:0 dropped:0 overruns:0 frame:0
      TX packets:17 errors:0 dropped:0 overruns:0 carrier:0
      MAC: 00:0A:35:00:1E:53
```

### Ping test (route gate)

PC command:

```text
arp -d 192.168.1.10   (clear stale ARP, MAC changed from baremetal image)
ping -n 4 192.168.1.10
```

Result:

```text
来自 192.168.1.10 的回复: 字节=32 时间=1ms TTL=64
来自 192.168.1.10 的回复: 字节=32 时间<1ms TTL=64
来自 192.168.1.10 的回复: 字节=32 时间<1ms TTL=64
来自 192.168.1.10 的回复: 字节=32 时间<1ms TTL=64
数据包: 已发送 = 4，已接收 = 4，丢失 = 0 (0% 丢失)
往返行程: 最短 = 0ms，最长 = 1ms，平均 = 0ms
```

## Evidence

Raw logs (gitignored under build/):

```text
build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_linux_boot.log     (498 lines, full boot)
build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_linux_setip.log    (32 lines, login + IP)
```

Key facts extracted from the boot log:

```text
U-Boot 2018.01, Zynq ZC702, Silicon v3.1, DRAM 512 MiB
Linux 4.14.0-xilinx-v2018.3, SMP PREEMPT, 2 CPUs
macb e000b000.ethernet eth0: link up (1000/Full)
eth0 RX packets:24 errors:0  TX packets:17 errors:0
ping 192.168.1.10: 4/4 received, 0% loss, <1ms
```

## What this proves

1. The physical Ethernet path (PC cable, Realtek adapter, RJ45, RTL8211E PHY,
   RGMII pins, PS GEM) is fully functional in both directions under Linux.
2. The months-long baremetal RX failure (rx=0, rxfcs rising, no frames reaching
   lwIP) was caused by the hand-written RGMII bridge implementation
   (BUFIO/BUFG clock domain crossing), not by the physical layer, PHY, cable,
   or PS GEM hardware.
3. The Linux/socket route is viable for the full-network goal. Ethernet works
   at the Linux kernel + driver level with zero errors.

## Decision

Per the tf-card-linux-resume plan, Outcome A applies:

```text
Proceed with Linux/socket MVP:
PC UDP/TCP sender -> Linux userspace receiver -> DDR/framebuffer write
-> VDMA HDMI output.
Retire the hand-written baremetal RGMII bridge as a debug-only dead end.
```

The hand-written baremetal RGMII bridge work is formally retired. It remains
in the repository as historical/negative evidence per the AGENTS.md
skill-dynamic-optimization rule: paths that were attempted but failed must not
be recorded as skill entry points; they belong in reports as negative evidence.

## Residual notes

- The Linux image MAC (00:0A:35:00:1E:53) differs from the baremetal default
  (00:0A:35:00:01:02). The PC ARP table was cleared before ping to avoid a
  stale-entry failure.
- The Linux image uses DHCP by default; on a direct link with no DHCP server,
  a static IP must be set manually after boot. A future production setup would
  either run a DHCP server on the PC or bake a static IP into the Linux
  rootfs.
- This experiment verified Ethernet only. It did not verify HDMI output under
  Linux or VDMA framebuffer access from Linux userspace. Those are the next
  milestones on the Linux/socket route.
