# Ethernet Pass-Through Baremetal Software

This directory holds source files for the first-stage PS baremetal receiver.
The baremetal route is currently a fallback, not the main route while waiting
for the TF-card Linux ping gate.

Target flow:

```text
PS GEM/lwIP UDP callback
  -> video_udp_receiver_on_packet()
  -> inactive RGB888 DDR frame buffer
  -> publish complete frame
  -> PS copies complete frame to the VDMA DDR framebuffer and flushes DCache
  -> VDMA MM2S scans the framebuffer to HDMI
```

The SDK build script currently targets the VDMA hardware export:

```text
build/eth-ps-pl-hdmi-pass-through/vdma-board/reports/eth_ps_vdma_hdmi_stage1_board.hdf
```

Do not treat the hand-written RGMII bridge as the preferred route. If Linux is
not usable after the TF-card gate, the baremetal fallback should restore the
official Xilinx `gmii_to_rgmii` IP before further receive-path work.

A valid baremetal SDK application requires:

```text
1. PS7 DDR configuration verified for the Smart ZYNQ SL board.
2. PS GEM connected through EMIO to the RTL8211E RGMII pins.
3. UART stdout available through PS UART0 over EMIO on the PL-side CH340 pins.
```

The protocol is defined in:

```text
docs/protocols/video-udp.md
```
