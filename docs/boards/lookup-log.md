# Board Lookup Log

Purpose: keep a chronological record of every board-information source already
inspected, so later work starts from this file and
`docs/boards/hellofpga-smart-zynq-sl.md` instead of repeatedly re-reading web
pages, schematics, or downloaded examples.

## Use This First

Before opening a web page, schematic, downloaded Vivado project, or hardware
probe for board information:

1. Search this file for the source or interface name.
2. Search `docs/boards/hellofpga-smart-zynq-sl.md` for promoted stable facts.
3. Re-check the external source only if the needed fact is missing, stale,
   contradictory, or explicitly marked unverified.

After every lookup, add an entry in the current date section. Do not leave board
facts only in terminal output, browser history, ignored downloads, or memory.

## Source Index

Use this index to avoid rereading sources that have already been mined.

| Topic | Best current source | Status |
| --- | --- | --- |
| Board identity and official downloads | [Official Board Page](#official-board-page) | stable identity promoted |
| PL Ethernet and UART package pins | [Local Schematic Text Extraction](#local-schematic-text-extraction) | pin facts promoted |
| Connected PC interfaces | [Hardware Interface Probe](#hardware-interface-probe) | environment-dependent; re-probe before board run |
| PS-assisted Ethernet route | [Official EMIO Ethernet Article](#official-emio-ethernet-article) | route decision promoted |
| PS7 DDR, ENET0 EMIO, UART0 EMIO, GMII-to-RGMII settings | [Official EMIO Ethernet Project](#official-emio-ethernet-project) | key facts promoted |
| Official all-test package source reuse | [Official All-Test Package](#official-all-test-package) | not useful as source |
| Stage-1 Ethernet runtime direction split | [Stage-1 Ethernet Runtime Diagnostics](#stage-1-ethernet-runtime-diagnostics) | logged only; active blocker |
| Official VDMA HDMI hardware control | [Official VDMA HDMI Hardware Control](#official-vdma-hdmi-hardware-control) | passed on connected board |

## Per-Lookup Rule

Every new board lookup must end with one of these outcomes:

- `Promoted`: stable fact copied to
  `docs/boards/hellofpga-smart-zynq-sl.md`.
- `Logged only`: raw evidence kept here because it is not yet reusable.
- `Rejected`: source checked and found irrelevant, stale, or not trustworthy.

Do not rely on chat history for board facts. If a fact affects RTL, XDC, Tcl,
PS configuration, software, or a hardware test, it must be present in this file
or promoted to `docs/boards/hellofpga-smart-zynq-sl.md`.

## Update Rule

When board information is inspected, add one entry here with:

- date
- source path or URL
- question being answered
- extracted conclusion
- reusable search key
- implementation impact
- verification status
- promotion target
- remaining uncertainty

If the conclusion is stable and reusable, also promote the concise fact into
`docs/boards/hellofpga-smart-zynq-sl.md`. If it is only raw evidence, keep it
here and under `build/reports/` or `tools/downloads/`.

Use this template for new entries:

```markdown
### <Short Source Name>

| Field | Value |
| --- | --- |
| Source | `<URL or local path>` |
| Local copy | `<local path, if any>` |
| Question | <What exact board fact or decision this lookup answers.> |
| Reuse key | <Short searchable key, for example `ethernet-rgmii-pins`, `ps7-ddr`, `uart-emio`, `hdmi-capture`.> |
| Conclusion | <Extracted fact, not a narrative dump.> |
| Implementation impact | <Which RTL, XDC, Tcl, software, or test decision this affects.> |
| Verification status | `confirmed`, `inferred`, `environment-dependent`, `blocked`, or `rejected`. |
| Promoted to | `<document path>` or `This lookup log only.` |
| Remaining uncertainty | <What still cannot be safely assumed.> |
```

## 2026-06-25

### Official Board Page

| Field | Value |
| --- | --- |
| Source | `http://www.hellofpga.com/index.php/2023/05/10/smart-zynq-sl/` |
| Question | Confirm board family and locate official downloads/examples. |
| Conclusion | Board is HelloFPGA Smart ZYNQ SL; page links schematic, IO length file, datasheet package, all-test package, Linux package, and example pages. |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` evidence sources and board identity. |
| Remaining uncertainty | Latest downloadable schematic revision and exact useful example source still need selective extraction before hardware build. |

### Local Schematic Text Extraction

| Field | Value |
| --- | --- |
| Source | `build/reports/SmartZynq_SL_Schematic_V1d3_20241005.pdf` |
| Source | `build/reports/SmartZynq_SL_Schematic_V1d3_20241005-layout.txt` |
| Question | Identify PL-side Ethernet and UART package pins. |
| Conclusion | Ethernet PHY is RTL8211E-class RGMII on PL pins; UART is PL-side CH340 UART. Pin mappings for Ethernet reset/RX/TX/MDIO/MDC/INT and PL UART TX/RX were extracted. |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` Ethernet PHY and UART sections. |
| Remaining uncertainty | Ethernet/UART bank VCCIO, final I/O standard, RTL8211E delay/strap behavior. |

### Hardware Interface Probe

| Field | Value |
| --- | --- |
| Source | `build/reports/environment.json` |
| Source | `build/reports/hardware.yml` |
| Source | `build/reports/interface-check-2026-06-25.md` |
| Question | Confirm which connected PC interfaces are visible and usable. |
| Conclusion | JTAG previously saw APU and `xc7z020`; HDMI capture opened and read 640x480 frames; UART COM ports were observed; Ethernet physical link was observed at 1 Gbps with APIPA before static IP setup. |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` current interface baseline. |
| Remaining uncertainty | Runtime COM number and network adapter identity are environment-dependent and must be re-probed before each board run. |

### Official EMIO Ethernet Article

| Field | Value |
| --- | --- |
| Source | `http://www.hellofpga.com/index.php/2023/04/28/smart-zynq_net_test-2/` |
| Local copy | `tools/downloads/smart-zynq_net_test-2.html` |
| Question | Decide whether PS-assisted Ethernet over PL-side pins is an official and practical route. |
| Conclusion | The article uses PS ENET0 through EMIO to PL pins, MDIO through EMIO, GMII-to-RGMII IP for RTL8211, UART through EMIO for SDK debug, Vivado 2018.3, fallback IP `192.168.1.10`, and echo-test port `7`. This supports the chosen PS baremetal route over pure RTL UDP for MVP. |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` first-stage architecture rationale; pending deeper promotion after extracting BD/HDF facts. |
| Remaining uncertainty | Exact reusable PS7 configuration, BD wiring, and XDC details must be extracted from the official project before generating our deterministic Vivado build. |

### Official EMIO Ethernet Project

| Field | Value |
| --- | --- |
| Source | `http://www.hellofpga.com/wp-content/uploads/2023/04/10_PS_EMIO_NET_TEST.zip` |
| Local copy | `tools/downloads/10_PS_EMIO_NET_TEST.zip` |
| Expanded path | `tools/downloads/10_PS_EMIO_NET_TEST/10_PS_EMIO_NET_TEST/NET_TEST/` |
| Question | Find a working reference for PS7 DDR, ENET0 EMIO, GMII-to-RGMII, UART EMIO, and SDK/lwIP setup. |
| Conclusion | The archive contains a full Vivado/SDK project for `xc7z020clg484-1`, including `NET_TEST.srcs/constrs_1/new/ZYNQ.xdc`, `NET_TEST.srcs/sources_1/bd/ZYNQ/`, `NET_TEST.sdk/ZYNQ_wrapper.hdf`, `NET_TEST.sdk/NET_TEST/src/`, and `NA/ps7_summary.html`. |
| Extracted facts | Official XDC uses `LVCMOS33` for RGMII, MDIO, and UART EMIO pins; RGMII TX pins use `SLEW FAST`; `RGMII_0_rxc` has an 8 ns clock; PS ENET0 and MDIO are EMIO; UART0 is EMIO at 115200; FCLK0 is 200 MHz; DDR is enabled as DDR3, 16-bit UI part `MT41K256M16 RE-125`, effective PS DQ width 32, DDR frequency 533.333 MHz; DDR range is `0x00100000..0x1fffffff`; GMII-to-RGMII IP uses PHY address 8, internal IDELAY control enabled, support logic in core, TXC skew 0. |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` Ethernet, UART, and DDR/PS sections. |
| Remaining uncertainty | The official net-test BD does not include PL DDR readout; our HDMI pass-through design must enable a PS HP/ACP path or another DDR-to-PL path and verify it separately. Do not commit the downloaded Vivado project itself. |

### Official All-Test Package

| Field | Value |
| --- | --- |
| Source | `Smart_ZYNQ_SP2_SL_ALL_TEST_20240916.zip` from the official board page. |
| Local copy | `tools/downloads/Smart_ZYNQ_SP2_SL_ALL_TEST_20240916.zip` |
| Question | Check whether the all-test package contains reusable source. |
| Conclusion | The expanded package contains `BOOT.bin` only, so it is not useful as source for deterministic builds. |
| Promoted to | This lookup log only. |
| Remaining uncertainty | None for source reuse; it may still be useful as a black-box sanity image only if explicitly needed. |

### User-Provided Linux All-Test Image

| Field | Value |
| --- | --- |
| Source | `C:/Users/中二哲人/Downloads/Smart_ZYNQ_SP2_LINUX_ALL_TEST_20240906.zip` |
| Question | Check whether the user-provided TF-card Linux test firmware contains reusable Ethernet source or a useful black-box board sanity image. |
| Reuse key | `official-linux-all-test-tf-image` |
| Conclusion | The zip contains `BOOT.BIN` and `image.ub` only. It is not a reusable Vivado/SDK source project, but it can boot the vendor Linux image from TF card and act as a black-box Ethernet sanity test if a TF card is available. |
| Implementation impact | Do not replace the deterministic baremetal stage-1 build with this image. Use it only to isolate whether Ethernet RX works under the vendor Linux stack and official boot image. |
| Verification status | directory inspected only; not boot-tested |
| Promoted to | This lookup log only. |
| Remaining uncertainty | Whether this SP2 image matches the connected SL board variant closely enough for safe boot, and whether its Linux network configuration enables the same PL-side RTL8211E path without extra setup. |

### Official PL UDP Loopback Tutorial

| Field | Value |
| --- | --- |
| Source | `http://www.hellofpga.com/index.php/2025/12/22/udp_net_test/` |
| Local page copy | `build/udp_net_test_page_http.html` |
| Download | `http://www.hellofpga.com/wp-content/uploads/2025/12/17_PL_NET_TEST_Smart_ZYNQ_S.zip` |
| Local archive | `tools/downloads/17_PL_NET_TEST_Smart_ZYNQ_S.zip` |
| Expanded path | `tools/downloads/17_PL_NET_TEST_Smart_ZYNQ_S/17_NET_TEST/NET_TEST/` |
| Question | Does the official pure-PL UDP loopback design clarify the current PC-to-board Ethernet RX failure without using TF-card Linux? |
| Reuse key | `official-pl-udp-loopback-idelay9` |
| Extracted facts | The article says the experiment applies to Smart ZYNQ SP/SP2/SL. It was updated on 2026-03-02 to add RX-side IDELAY because Xilinx 7-series IOCLK lags IODATA through the BUFIO path. The downloaded Smart ZYNQ S project uses the same SL RGMII pins as this board, board IP `192.168.1.10`, UDP port `1234`, board MAC `00-11-22-33-44-55`, and a custom `rgmii_to_gmii` module with `IDELAY_VALUE = 9` on `rgmii_rx_ctl` and `rgmii_rxd[3:0]`. |
| User board note | The connected board is reported by the user to be from before the 2026-03-02 tutorial update. This does not by itself invalidate the IDELAY fix, because the tutorial attributes the need to Xilinx 7-series IO path behavior rather than a new board revision. |
| Hardware test | Programmed `NET_TEST.runs/impl_1/NET_TEST.bit` over XSCT after clearing the stale static ARP entry for `192.168.1.10`. A Python UDP probe bound to `192.168.1.2:1234` sent `WWW.HELLOFPGA.COM official-pl-udp-test #0` to `192.168.1.10:1234` and received the same payload back from `192.168.1.10:1234`. |
| Conclusion | The current direct PC-to-board physical Ethernet path and the RTL8211E/PL RGMII pins can receive and transmit UDP successfully when using the official pure-PL design with RX data/control IDELAY. The stage-1 failure is therefore more likely in our PS/GMII-to-RGMII/lwIP implementation, especially the current RX delay handling, than in the cable, PC adapter, RJ45, or PHY analog path. |
| Implementation impact | Stop treating the external physical Ethernet path as the primary blocker. The next implementation should remove the local forced `IDELAY_VALUE 0` override, align the RX RGMII sampling with the official `IDELAY_VALUE = 9` approach or an equivalent verified Xilinx GMII-to-RGMII configuration, then rerun the stage-1 PS UDP receiver. |
| Verification status | official pure-PL UDP loopback passed on connected hardware |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md`, `docs/current-cycle.md`, and `docs/reports/eth-ps-pl-hdmi-pass-through.md`. |
| Remaining uncertainty | Whether Xilinx `gmii_to_rgmii` in the PS EMIO design can be made equivalent to the official custom `rgmii_to_gmii` delay path, or whether the stage-1 design should replace that IP with a custom RGMII bridge before PS GEM. |

## 2026-06-26

### Official SL Board Page Refresh

| Field | Value |
| --- | --- |
| Source | `http://www.hellofpga.com/index.php/2023/05/10/smart-zynq-sl/` |
| Local copy | `build/smart_zynq_sl_page_20230510.html` |
| Question | Re-check the Smart ZYNQ SL resource index for official references useful to the current Ethernet-to-PS-to-DDR-to-HDMI first-stage pipeline. |
| Reuse key | `official-sl-resource-index-video-ethernet-ddr` |
| Extracted facts | The page is a resource index for Smart ZYNQ SL and links the latest visible SL schematic `SmartZynq_SL_Schematic_V1d3B_20260415.pdf`, older schematic links in comments, the IO length file, all-test packages, PL HDMI experiment, PS EMIO Ethernet experiment, PL UDP loopback experiment, PL/PS DDR interaction experiment, VDMA HDMI color-bar experiment, VDMA BMP-from-TF experiment, PS-provided PL clock experiment, and Linux/PetaLinux/Xillinux resources. |
| User board note | The connected board is reported by the user to be from before 2026-03-02, so do not replace the existing V1d3 20241005 schematic-derived constraints with the 20260415 schematic without comparing revisions. |
| Conclusion | The most useful next official references are not new board pins but reference designs: `pl_ddr_ps_test` for the PL read/write PS DDR path, `vdma_01` for VDMA-to-HDMI display structure, `smart-zynq_net_test-2` for PS ENET0 EMIO/lwIP baseline, and `udp_net_test` for the verified RGMII RX delay behavior. |
| Implementation impact | For the stage-1 MVP, use the official PL/PS DDR and VDMA HDMI examples to replace ad-hoc DDR/HDMI assumptions where possible; keep Ethernet work aligned with the already verified official PL UDP and PS EMIO examples. |
| Verification status | `confirmed resource index; individual reference projects still need selective extraction` |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` official reference index. |
| Remaining uncertainty | Whether each linked tutorial provides downloadable source that directly targets SL and whether the 20260415 schematic changes any pins relevant to the pre-2026 connected board. |

### Stage-1 Ethernet Runtime Diagnostics

| Field | Value |
| --- | --- |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_stage1_heartbeat.log` |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_100m_during_udp_probe.log` |
| Source | `tools/listen_stage1_heartbeat.py` |
| Source | `tools/run_stage1_udp_probe.ps1` |
| Question | Does the current stage-1 board image pass Ethernet in both directions before HDMI verification? |
| Reuse key | `stage1-ethernet-runtime-rx-fcs` |
| Conclusion | Board-to-PC UDP heartbeat from `192.168.1.10:49153` reaches the PC, proving board TX. PC-to-board video send reports `SEND_OK`, but concurrent UART/GEM diagnostics show `rx=0` and `rxfcs=419` during a 512-packet send at 100Mbps; no video frame reaches the UDP callback. |
| Implementation impact | Do not continue HDMI verification as if Ethernet RX works. Next implementation should debug PHY/RGMII RX path, cable/adapter receive direction, or GMII-to-RGMII RX sampling before DDR/HDMI pass-through can close. |
| Verification status | `blocked` |
| Promoted to | `docs/reports/eth-ps-pl-hdmi-pass-through.md` current blocker. |
| Remaining uncertainty | Whether RX corruption is caused by cable/adapter physical direction, RTL8211E strap/delay, GMII-to-RGMII RX timing, or another board-level receive-path issue. |

### Official PL/PS DDR Project

| Field | Value |
| --- | --- |
| Source | `http://www.hellofpga.com/index.php/2023/09/14/pl_ddr_ps_test/` |
| Local page copy | `tools/downloads/pl_ddr_ps_test.html` |
| Download | `http://www.hellofpga.com/wp-content/uploads/2023/09/14_PL_DDR_PS_TEST.zip` |
| Local archive | `tools/downloads/14_PL_DDR_PS_TEST.zip` |
| Expanded path | `tools/downloads/14_PL_DDR_PS_TEST/14_PL_DDR_PS_TEST/` |
| Question | What official reference proves PL access to PS DDR for the first-stage frame-buffer path? |
| Reuse key | `official-pl-ps-ddr-hp0` |
| Extracted facts | The tutorial targets Smart ZYNQ SP/SP2/SL and demonstrates PL reading/writing PS DDR through AXI. The block design enables `processing_system7_0/S_AXI_HP0`, connects custom `PL_DDR_RW_0/M00_AXI` through SmartConnect to HP0, and maps the PL master address space to `processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM`. The custom IP target base is `0x10000000`; the article explicitly avoids `0x00000000` because of OCM and PS stack/program usage. DDR must be initialized by PS code before PL-side access is reliable. |
| Implementation impact | Reuse HP0 + AXI master access as the source-backed model for any PL-side DDR read path, but do not use the sample `PL_DDR_RW` IP as the final video engine because it is only a write/read/compare tester. |
| Verification status | `confirmed reference extracted; not yet black-box programmed in this cycle` |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` DDR/PS and official reference sections. |
| Remaining uncertainty | Whether the current custom stage-1 design should keep a hand-written AXI reader or pivot completely to VDMA for DDR-to-HDMI. |

### Official VDMA HDMI Project

| Field | Value |
| --- | --- |
| Source | `http://www.hellofpga.com/index.php/2023/05/11/vdma_01/` |
| Local page copy | `tools/downloads/vdma_01.html` |
| Download | `http://www.hellofpga.com/wp-content/uploads/2023/05/19_VDMA_HDMI_TEST.zip` |
| Local archive | `tools/downloads/19_VDMA_HDMI_TEST.zip` |
| Expanded path | `tools/downloads/19_VDMA_HDMI_TEST/19_VDMA_HDMI_TEST/` |
| Question | What official reference provides a DDR frame-buffer to HDMI display path closest to the first-stage MVP? |
| Reuse key | `official-vdma-hdmi-framebuffer` |
| Extracted facts | The tutorial targets Smart ZYNQ SP/SP2/SL and uses PS software to write an RGB888 color-bar frame into PS DDR, then AXI VDMA MM2S reads DDR through `S_AXI_HP0` and drives `v_axi4s_vid_out -> rgb2dvi -> HDMI`. The block design uses AXI VDMA 6.3 with 24-bit MM2S stream width, Read Burst Size 64, FCLK0 50 MHz, FCLK1 150 MHz, a 40 MHz pixel clock and 200 MHz serial clock for 800x600 HDMI. The SDK framebuffer base is `XPAR_PS7_DDR_0_S_AXI_BASEADDR + 0x01000000`, with `WIDTH=800`, `DEPTH=600`, and `Xil_DCacheFlush()` after filling the buffer. The XDC drives HDMI data P pins M21/L21/J21 and exposes both N19 and N22 clock P pins for board-version compatibility. |
| Implementation impact | This is the shortest safe replacement for the current ad-hoc DDR-to-HDMI path: keep PS/lwIP as the network receiver, write received frames into the VDMA framebuffer, and let official VDMA/video-out/RGB2DVI structure own HDMI timing. First black-box step should be programming the official bit+ELF and checking HDMI capture for static color bars. |
| Verification status | `confirmed reference extracted; not yet black-box programmed in this cycle` |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` DDR/PS and official reference sections. |
| Remaining uncertainty | Whether the official bitstream's dual HDMI clock output is safe for the connected board revision without comparing board versions; current reference suggests it was designed for compatibility across V1.2 and V1.3. |

### Official VTC Fixed-Mode Timing Reinspection

| Field | Value |
| --- | --- |
| Source | `tools/downloads/19_VDMA_HDMI_TEST/19_VDMA_HDMI_TEST/VDMA_HDMI_TEST/VDMA_HDMI_TEST.srcs/sources_1/bd/ZYNQ_CORE/hw_handoff/ZYNQ_CORE_bd.tcl` |
| Question | What exact fixed mode must Linux advertise so its DRM framebuffer dimensions and refresh interval match the self-running VTC already in the programmed PL design? |
| Reuse key | `official-vdma-hdmi-fixed-vtc-mode` |
| Extracted facts | The official VTC uses a 40 MHz pixel clock. Horizontal timing is active 800, front porch 40, sync 128, back porch 88, total 1056. Vertical timing is active 600, front porch 1, sync 4, back porch 23, total 628. `HAS_AXI4_LITE=false`, so Linux cannot reprogram this VTC and must advertise the same fixed timing. |
| Implementation impact | `software/petalinux/hdmi-linux-display-stack/system-user.dtsi` must expose exactly this timing through the fixed HDMI connector. A different DRM mode could size the VDMA framebuffer incorrectly even though the physical VTC continues transmitting its original timing. |
| Verification status | `confirmed by direct reinspection of official Vivado 2018.3 BD Tcl` |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` HDMI / VDMA table. |
| Remaining uncertainty | The DT mode can describe the self-running timing, but only an on-board DRM/fbdev write plus HDMI capture can prove the Xilinx component graph accepts the added connector and scans the Linux buffer. |

### Official VDMA DDR Window Reinspection

| Field | Value |
| --- | --- |
| Source | `tools/downloads/19_VDMA_HDMI_TEST/19_VDMA_HDMI_TEST/VDMA_HDMI_TEST/VDMA_HDMI_TEST.srcs/sources_1/bd/ZYNQ_CORE/hw_handoff/ZYNQ_CORE_bd.tcl` |
| Question | Why does Linux VDMA MM2S report DMA decode error `0x40` even though the framebuffer address is valid system RAM? |
| Reuse key | `official-vdma-hdmi-ddr-window` |
| Extracted facts | The official block design connects VDMA MM2S through SmartConnect to PS `S_AXI_HP0`, but its MM2S address segment has offset `0x00000000` and range `0x10000000`. Linux allocated the DRM framebuffer from CMA at `0x1f100000`, outside that 256 MiB PL-visible window. VDMA registers otherwise held the expected height 600, horizontal size 2400, and stride 2400. |
| Implementation impact | Linux CMA used by DRM/VDMA must be reserved below `0x10000000`. `software/petalinux/hdmi-linux-display-stack/system-user.dtsi` fixes the default CMA region at `0x0e000000..0x0effffff`; no PL rebuild or userspace register ownership is required. |
| Verification status | `passed on connected hardware; corrected CMA placement removed decode errors and userspace framebuffer output passed HDMI capture` |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` HDMI / VDMA table and Linux allocation note. |
| Remaining uncertainty | None for the current fixed-mode framebuffer path. A future higher-resolution hardware design may need a larger VDMA DDR address segment or a differently sized CMA pool. |

### Official VDMA HDMI Hardware Control

| Field | Value |
| --- | --- |
| Source | `tools/downloads/19_VDMA_HDMI_TEST/19_VDMA_HDMI_TEST/VDMA_HDMI_TEST/` |
| Program log | `build/reports/vdma-official-program/OFFICIAL_VDMA_HDMI_PROGRAM_OK.log` |
| Capture report | `build/reports/vdma-hdmi-capture-device1-dshow/latest-validation.json` |
| Capture image | `build/reports/vdma-hdmi-capture-device1-dshow/latest.png` |
| Question | Does the official VDMA DDR-framebuffer-to-HDMI design work on the connected board and current HDMI capture path? |
| Reuse key | `official-vdma-hdmi-hardware-pass` |
| Hardware action | Programmed official `ZYNQ_CORE_wrapper.bit`, ran official `ps7_init.tcl`, downloaded and started official `VDMA_HDMI_TEST.elf` over XSCT. The first attempt hit `DAP status f0000021`; a DAP system reset recovered APU visibility, and the second program/run completed with `OFFICIAL_VDMA_HDMI_PROGRAM_OK`. |
| Captured result | HDMI capture on DirectShow device index 1 opened at 800x600 and captured a passing four-bar frame. Validation reported `status=pass`, `score=6`, frame mean `127.4`, and bar RGB means `[255,255,255]`, `[255,0,0]`, `[0,255,0]`, `[0,0,255]`. |
| Conclusion | The connected board, official PS DDR initialization, HP0/VDMA MM2S, `v_axi4s_vid_out`, RGB2DVI, HDMI output, HDMI cable/converter, and PC capture path can produce and capture a stable 800x600 framebuffer image. DDR-to-HDMI should therefore be implemented by reusing the official VDMA structure for stage 1. |
| Implementation impact | Stop treating DDR-to-HDMI as an unproven custom PL-reader problem. The remaining first-stage blocker is PC-to-board Ethernet RX into PS/lwIP, then writing received RGB data into the proven VDMA framebuffer and flushing DCache. |
| Verification status | `passed on connected hardware` |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md`, `docs/current-cycle.md`, and `docs/reports/eth-ps-pl-hdmi-pass-through.md`. |
| Remaining uncertainty | The official VDMA image is a static PS-generated color bar, not yet the project requirement of PC-sent frames over Ethernet. It verifies only the DDR framebuffer to HDMI output subchain. |

### Stage-1 Ethernet RX Follow-Up Diagnostics

| Field | Value |
| --- | --- |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_rtl8211e_rxdelay_startup.log` |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_rtl8211e_rxdelay_udp_probe.log` |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_broadcast_udp_probe.log` |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_broadcast_udp_probe_10ms.log` |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_official_net_test_program_echo_long.log` |
| Source | Linux Realtek PHY driver pattern for RTL8211E extension page `0xa4`, register `0x1c`, RX delay bit `0x0004`, TX delay bit `0x0002`: `https://chromium.googlesource.com/chromiumos/third_party/kernel/+/a7a9e8db25b32f1ab96135e8cf66bdf65b0ba2fe/drivers/net/phy/realtek.c` |
| Question | Is PC-to-board RX failure caused by missing RTL8211E RX delay, ARP/offload, packet rate, or our stage-1 app only? |
| Reuse key | `stage1-ethernet-rx-followup` |
| Conclusion | RTL8211E delay register already reported `before=0x8577 after=0x8577 rx_delay=1 tx_delay=1`, so missing PHY internal RX delay is not the root cause. The official NET_TEST bit/ELF starts and negotiates `link speed for phy address 1: 1000`, but TCP echo to ports `7` and `6001` timed out in the direct-PC setup. PC route and static ARP are correct for `以太网 2`; disabling EEE/offloads/flow-control did not make ping or a single ZVID chunk reach lwIP. Broadcast UDP can increment GEM broadcast/resource counters, but no video UDP callback is reached. |
| Implementation impact | Do not spend more time toggling RTL8211E RX/TX delay or Windows checksum offload as the primary fix. Next useful actions are physical receive-direction isolation with a different cable/adapter/switch, or a controlled PL-side RGMII/GMII capture/ILA to inspect PHY-to-FPGA RX data. |
| Verification status | `blocked` |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` Ethernet runtime notes and `docs/reports/eth-ps-pl-hdmi-pass-through.md`. |
| Remaining uncertainty | Whether the corruption is outside the FPGA on the PC-to-PHY receive direction, inside RTL8211E/board routing, or between the PHY RGMII RX outputs and the GMII-to-RGMII/PS GEM path. |

### Stage-1 PHY Local Loopback Probe

| Field | Value |
| --- | --- |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_phy_loopback_probe.log` |
| Question | Does the PHY-to-FPGA/GEM RX side show any activity when RTL8211E locally loops board TX back into RX? |
| Reuse key | `stage1-phy-local-loopback` |
| Conclusion | The diagnostic set PHY BMCR from `0x1140` to `0x5140` for 5 seconds, proving the standard loopback bit was asserted, then restored BMCR to `0x1140`. During the first loopback heartbeat, GEM reported `tx=1 txbc=1 rx=1 rxbc=1 rxfcs=1`. After restore, PC receipt of heartbeat was confirmed again. |
| Implementation impact | The RX side is not a completely dead digital path, because the GEM can count at least one locally looped broadcast frame. The simultaneous `rxfcs=1` means this does not prove clean RX timing. Next decisive test should be a PL ILA/RGMII capture or a physical Ethernet path swap rather than more software-only UDP changes. |
| Verification status | `diagnostic only` |
| Promoted to | `docs/reports/eth-ps-pl-hdmi-pass-through.md` and `docs/current-cycle.md`. |
| Remaining uncertainty | Whether the looped frame was corrupted by loopback mode timing, RGMII sampling, or normal counter behavior; whether PC-originated frames are bad before or after RTL8211E. |

## 2026-06-29

### Official Linux Network Ping Route Gate

| Field | Value |
| --- | --- |
| Source | `C:/Users/中二哲人/Downloads/Smart_ZYNQ_SP2_LINUX_ALL_TEST_20240906.zip` |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_linux_boot.log` |
| Source | `build/eth-ps-pl-hdmi-pass-through/hardware/reports/uart_com16_linux_setip.log` |
| Question | Does the official vendor Linux image bring up Ethernet over the PL-side RTL8211E path and respond to PC ping on the connected board? |
| Reuse key | `official-linux-network-ping-pass` |
| Conclusion | The official Linux image boots from a FAT32 TF card. U-Boot 2018.01 loads image.ub; Linux 4.14.0-xilinx-v2018.3 starts; `macb` driver binds `e000b000.ethernet eth0` at 1000/Full with RX errors=0 and TX errors=0. After setting a static IP (`ifconfig eth0 192.168.1.10/24`), PC ping returns 4/4 with 0% loss and <1ms latency. |
| Implementation impact | The physical Ethernet path (PC, cable, RTL8211E, RGMII pins, PS GEM) is confirmed fully functional in both directions under Linux. The baremetal hand-written RGMII bridge RX failure (rx=0, rxfcs rising) is therefore caused by the bridge implementation, not the physical layer. Retire the hand-written bridge; proceed on the Linux/socket route. |
| Verification status | `passed on connected hardware` |
| Promoted to | `docs/boards/hellofpga-smart-zynq-sl.md` Ethernet PHY section, `docs/current-cycle.md` Resolved Route Gate, `docs/reports/tf-card-linux-ping-2026-06-29.md`. |
| Remaining uncertainty | The Linux image MAC (00:0A:35:00:1E:53) differs from the baremetal default (00:0A:35:00:01:02); PC ARP must be cleared when switching images. HDMI output and VDMA framebuffer access under Linux are not yet verified. |
