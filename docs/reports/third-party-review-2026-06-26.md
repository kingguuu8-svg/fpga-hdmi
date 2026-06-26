# Third-Party Review Report

Date: 2026-06-26
Reviewer: external review (no changes made to the repository)
Scope: whole-repo audit of path, code, and project management

## Purpose

An external reviewer examined this repository without making any changes.
This document records the findings and recommendations so the main thread can
act on them. Findings are ordered by severity. Each item names the concrete
files so it can be checked independently.

The reviewer was asked to challenge the route as well as the code. The route
challenge is recorded in the "Route Question" section; it is the highest-value
finding.

## TL;DR

1. The active cycle's video path is self-contradictory end-to-end. Even after
   Ethernet RX is fixed, the image would not come out correctly because PS
   software and the documented PL build disagree on resolution, pixel format,
   framebuffer address, and HDMI mechanism. Two mutually exclusive HDMI
   implementations coexist in the repo.
2. The documented "next fix" for the Ethernet RX blocker (apply IDELAY=9 to
   replace the Xilinx IP) has already been applied in code, yet the blocker
   narrative was not updated. The actual RX root cause is a BUFIO/BUFG clock
   domain crossing that the replaced Xilinx IP used to handle internally.
3. The entire active cycle is untracked in git. Months of hardware work can be
   lost to a working-tree mistake.
4. The RX debugging the main thread is doing right now is a "golden-plating"
   trap: it is solving a one-time, throwaway implementation detail (hand-written
   RGMII bridge + bare-metal lwIP) that will be discarded when the project
   moves to Linux for the full-network goal. The route is sound; this
   implementation sub-route is not.

## Route Question (highest value)

The project goal is a network video effects system, with a post-MVP direction
toward full network-unified control (Linux, FPGA Manager, LAN control). The
reviewer was asked whether the current RX攻坚 is useful for that goal.

Conclusion: the route is reasonable, but the current implementation sub-route
is attacking the wrong layer. The hard problem being solved now (hand-written
RGMII RX clock-domain crossing for PS EMIO) is a problem that the official
Xilinx `gmii_to_rgmii` IP already solves internally, and that Linux + official
drivers never expose to the developer. Solving it by hand is both harder than
the intended "upper" implementation and useless to it.

Risk is not uniform across the route. The table below shows where the risk
actually lives:

```text
Link segment                                  Risk    Status
PL HDMI output stable                         low     proved (official 19)
DDR as framebuffer, PL reads it               low     proved (official 19)
PC -> DDR -> HDMI end-to-end                  medium  depends on the two below
PS bare-metal lwIP receives UDP video         high    BLOCKED now (EMIO RX timing)
PS Linux + official IP + network stack        high    not attempted, but has official backing
```

The critical observation: the last row is likely easier than the row above it,
because the last row stands on official ecosystem (Xilinx IP handles the RGMII
crossing; Linux kernel TCP/IP is mature; debug is at the application layer with
dmesg/tcpdump/ping/ethtool). The current sub-route voluntarily re-opens the
hardest, most-ecologically-thin layer (hand-written RGMII + PS EMIO) that the
official stack has already absorbed.

There is one unverified assumption under the "Linux is easier" claim: whether
the official Linux image even brings up the network on this exact board. That
assumption is the cheapest thing to falsify and is currently untested.

### Recommended pivot

Stop the hand-written RGMII bridge timing work. Run one cheap experiment that
decides the whole sub-route:

```text
Burn the official Smart_ZYNQ_SP2_LINUX_ALL_TEST image (BOOT.BIN/image.ub,
already on disk per lookup-log) to a TF card, boot, ping the board.
```

Outcome A (ping works): the full-network physical + driver layer is confirmed.
Drop the bare-metal hand-written bridge entirely. Build the upper
implementation on Linux with sockets + VDMA/HDMI. The RX timing problem
vanishes permanently because it lives inside the official IP.

Outcome B (ping fails): this is the real root cause and is more worth
investigating than RX timing, because it points at board/PHY hardware, not at
the implementation choice. Only then does an ILA RGMII capture become worth
the cost.

Either outcome is reached in roughly half an hour and either way is more
useful than another hand-written-bridge iteration.

If the main thread is unwilling to pivot to Linux yet, the second-best path is:
restore the Xilinx `gmii_to_rgmii` IP (the one official project 10 already
proved RX on), run the official echo app to confirm PS EMIO RX can echo one
packet on this board, then layer video back on at the smallest possible spec
(64x64 RGB565, not 800x600 RGB888). Close the loop before tuning quality.

## Severity 1: End-to-end video path is self-contradictory

The video path is inconsistent on four axes at once: resolution, pixel format,
framebuffer address, and HDMI mechanism. The PS software only matches one of
the two PL builds, and that build is not the one documented as programmed.

Per-layer actual values:

```text
Layer                    File                                          Resolution  Pixel    FB addr      HDMI
PC sender                tools/send_video_udp.py:101-102               800x600     RGB888   -            -
Protocol header          software/.../video_udp_protocol.h:16-20       800x600     RGB888   -            -
PS receive/reassemble    software/.../video_udp_receiver.c:65-69       800x600 only RGB888  -            -
PS app -> display        software/.../video_udp_app.c:22,89-91         800x600     RGB888   0x01100000   VDMA MM2S + rgb2dvi
VDMA BD                  examples/.../tcl/create_ps_emio_vdma_hdmi_bd  -           -        -            VDMA + rgb2dvi
Custom PL reader         rtl/axi_framebuffer_line_reader.v:38          640x480     RGB565   0x10000000   custom AXI reader + TMDS
                         rtl/eth_ps_pl_hdmi_video_out.v:5-6
Documented stage1 build  tcl/build_stage1_board.tcl:33 (top=)          640x480     RGB565   0x10000000   custom reader (no VDMA IP)
```

Two hard contradictions follow:

1. The PS app depends on VDMA, but the documented build has no VDMA IP.
   `video_udp_app.c` calls `XAxiVdma_LookupConfig(XPAR_AXIVDMA_0_DEVICE_ID)`
   at `:76` and starts the read channel at `:114`; on lookup failure it prints
   "VDMA initialization failed" and `return -4` at `:677-680`, which exits
   before creating the UDP/heartbeat PCBs. But
   `create_ps_emio_hp0_bd.tcl:61-65` only enables `S_AXI_HP0`; there is no
   VDMA IP. So the report's "Full Board Build / JTAG Program" section
   (`docs/reports/eth-ps-pl-hdmi-pass-through.md:299-313,427-439`) and its
   heartbeat receipt claim (`:459-470`) cannot both be true for that bit+ELF
   combination.

2. The report says the payload is "RGB565 little-endian" at `:228`, which
   contradicts the protocol header, the protocol doc, the sender, and the app,
   all of which use RGB888. The report was written under an earlier
   architecture and was not back-filled after the switch to VDMA/RGB888.

Action: pick one HDMI path and delete the other. Per the code facts (PS app,
protocol, sender are all 800x600 RGB888 VDMA), the VDMA path is the survivor.
Explicitly retire `eth_ps_pl_hdmi_board_top.v`, `axi_framebuffer_line_reader.v`,
`build_stage1_board.tcl`, and `create_ps_emio_hp0_bd.tcl`, then align the
report, build scripts, top-level, and sim to the VDMA path.

## Severity 1: Documented RX "next fix" is already applied; blocker narrative is stale

`docs/current-cycle.md:92-96`, the report (`:611-655`), and the board reference
all attribute the blocker to "stage-1 XDC forces the Xilinx GMII-to-RGMII RX
IDELAY cells to 0; next, apply the official IDELAY_VALUE=9." But the code
already did this:

```text
create_ps_emio_hp0_bd.tcl:25-27   deletes gmii_to_rgmii_0
eth_ps_pl_hdmi_board_top.v:165    instantiates rgmii_gmii_bridge #(.IDELAY_VALUE(9))
stage1_board.xdc:75-77            comment: "Do not constrain removed gmii_to_rgmii IP"
```

So the "apply IDELAY=9" next-action listed as a fix is already in the code,
and RX still fails (FCS=419, rx=0 per the report). The narrative has not caught
up. A future reader following the docs would re-do an already-done, ineffective
fix.

The more likely root cause, which the docs do not mention, is a BUFIO/BUFG
clock domain crossing in `rgmii_gmii_bridge.v`:

```text
IDDR ... .C(rgmii_rxc_bufio)   captures RXD in the BUFIO domain  (rgmii_gmii_bridge.v:88,125)
gmii_rx_clk = rgmii_rxc_bufg    is the BUFG domain clock fed to PS GEM  (rgmii_gmii_bridge.v:36,47)
gmii_rxd is driven straight from IDDR output to GEM with no BUFG-domain resync
```

BUFIO and BUFG have a fixed skew of a few nanoseconds. The PS GEM samples
BUFIO-domain data with a BUFG-domain clock; once the skew pushes the sample
point outside the ~2.5-4ns RGMII data window, every byte is corrupted and FCS
errors follow. This is exactly the crossing that the Xilinx `gmii_to_rgmii` IP
handles internally, which is why official project 10 (which uses that IP) has
working RX and the hand-written bridge does not. The main thread has already
reached this same suspicion independently and is testing a one-stage BUFG
resync; that is the right direction, but it may not be enough depending on the
actual PHY data window vs BUFG skew.

Action: rewrite the blocker narrative in `current-cycle.md` and the report to
state that the IDELAY=9 custom bridge is already live and RX still fails, and
that the active suspect is the BUFIO/BUFG crossing. Stop framing IDELAY tuning
as the next step.

## Severity 1: The active cycle is not in git

`git status --short` shows `examples/eth-ps-pl-hdmi-pass-through/`, `software/`,
`docs/protocols/`, `docs/boards/lookup-log.md`,
`docs/reports/eth-ps-pl-hdmi-pass-through.md`, and ~10 `tools/*.{ps1,py,tcl}`
as untracked, plus `AGENTS.md`, `.gitignore`,
`docs/boards/hellofpga-smart-zynq-sl.md`, `docs/current-cycle.md`, and
`skills/zynq7020-vivado/scripts/sim.tcl` as modified-uncommitted. This violates
the project's own rules: `docs/project-start-standard.md:18-19` requires a
clean `git status`, and `AGENTS.md` requires one commit per completed cycle.
Commit `8a0acc3` in the cycle log claims "Added current boards, examples,
skills, and tools as the initial source baseline," but that baseline did not
include the eth example or the software, so the claim is false against fact.
None of the milestones described in `current-cycle.md` (sim, BD, build, SDK,
program, heartbeat, VDMA control) appear in `docs/cycle-log.md`.

Hardware debug is the workflow that most needs rollback. Every bridge edit
should be a checkpoint so a regression can be `git diff`'d and reverted.

Action: with user authorization, make one checkpoint commit staging only the
current cycle's files before the next board program. Then backfill
`cycle-log.md` with the completed milestones and move the debug narrative out
of `current-cycle.md` back to its short objective/verification/closure form.

## Severity 2: Reproducibility depends on gitignored downloads

`.gitignore:5` ignores `/tools/downloads/`, but the deterministic build
scripts depend on it:

```text
create_ps_emio_hp0_bd.tcl:9-16      sources tools/downloads/10_PS_EMIO_NET_TEST/.../ZYNQ_bd.tcl
create_ps_emio_vdma_hdmi_bd.tcl:8-19 needs tools/downloads/19_VDMA_HDMI_TEST/... and its rgb2dvi IP repo
```

A clean clone cannot build. This conflicts with AGENTS.md "Run Vivado in batch
mode from checked-in Tcl" and "Do not commit downloads." The report itself
acknowledges the debt at `:194-202` ("a later cleanup should replace that
dependency"), but that cleanup is the reproducibility gap itself and should
not be deferred indefinitely.

Action: either commit the rgb2dvi IP and the minimal official BD fragments in
a tracked form, or state the required downloads explicitly in the README so a
clean clone knows what to fetch before building.

## Severity 2: Three competing MVP definitions

```text
docs/project-roadmap.md:14-34       PC->ETH->PS->DDR->PL->HDMI, 320x240 RGB565 in, needs PS software
README.md:52-62                     examples/video-pip PL-only HDMI effects, 640x480, internally generated
skills/zynq7020-pipeline/SKILL.md:13-17,37  led/video-pip PL-only loop first; "Do not add PS software"
```

AGENTS.md forbids scattered competing roadmaps, yet that is the current state.
The orchestrator skill has no entry point for `eth-ps-pl-hdmi-pass-through`, so
the active cycle is invisible to the skill system. The roadmap's 320x240 input
spec was abandoned by the implementation (now 800x600) but never updated.

Action: update the roadmap to the actually-targeted 800x600 RGB888 VDMA path;
add the eth-ps-pl entry point to the pipeline skill and drop the "first MVP
forbids PS software" wording; demote video-pip in the README to a "PL-only
side demo" rather than the MVP.

## Severity 3: Code-level issues

1. Hidden cross-example dependency. `build_stage1_board.tcl:26-29` globs
   `examples/video-pip/rtl/*.v` into the stage1 build because
   `eth_ps_pl_hdmi_video_out.v` instantiates `video_timing_640x480`,
   `tmds_encoder`, `hdmi_phy_7series`, and `clock_gen_50_to_hdmi`, which all
   live in `examples/video-pip/rtl/`. The eth example has a hard dependency on
   video-pip with no local copy and no documentation. Touching video-pip breaks
   stage1.

2. TX clock sourced from RX clock. `rgmii_gmii_bridge.v:37-38` drives
   `gmii_tx_clk = gmii_rx_clk` (BUFG of rgmii_rxc) into `rgmii_txc`. This is a
   looped-clock TX; if the link partner stops providing RX clock, TX also
   stops. It explains why heartbeat works (PHY link up provides RX clock) but
   is fragile. Prefer an independent TX clock or an MMCM.

3. `gmii_rx_er` forced to 0. `rgmii_gmii_bridge.v:43` hard-wires RX_ER to 0
   with a comment that driving RX_ER into PS GEM caused frame drops on edge
   noise. Masking the signal hides the symptom; real RX_ER noise would itself
   indicate a sampling-timing problem, consistent with the BUFIO/BUFG
   suspicion.

4. `axi_framebuffer_line_reader` AXI efficiency and the testbench's value.
   `axi_framebuffer_line_reader.v:91` uses `arlen=0` (single-beat reads, 160
   AR per line) with no burst and no backpressure handling. The testbench
   `tb_axi_framebuffer_line_reader.v` uses 16x4 toy dimensions, `arready=1`
   constant, immediate `rvalid`, and tests the module that the VDMA path has
   already retired. The "PL reader xsim PASSED" claim in the report carries
   almost no proof value for the actual delivery.

5. Per-frame 1.44MB memcpy in the PS app. `video_udp_app.c:142` copies a full
   800x600 RGB888 frame then flushes DCache, inside the main loop
   synchronously. This costs tens of ms per frame and blocks lwIP receive.
   Acceptable for MVP but should be recorded as a known bottleneck; the fix is
   to land the receive buffer directly in the VDMA framebuffer or rotate VDMA
   framestores, removing the CPU copy.

6. Shared HP0 R/W between the RGMII probe and the video reader
   (`eth_ps_pl_hdmi_board_top.v:142-163` vs `:105-140`), both with ID 0. AXI
   permits separate read/write masters, but this is unusual and exists only in
   the custom-reader path, not the VDMA path, which is another asymmetry
   between the two retired/surviving designs.

## Severity 3: Stale documentation

- `docs/protocols/video-udp.md` correctly says 800x600 RGB888, but the roadmap
  still says 320x240 input.
- `docs/current-cycle.md` "Current State" is a long debug stream-of-consciousness
  (PHY loopback, ARP, Windows offload, broadcast UDP). That material belongs in
  the lookup log or a dedicated report; the cycle file should return to short
  objective/verification/closure form.
- `README.md` "Video PIP Stage 1/2" and "Recording Demo Script" describe an
  unrelated PL-only demo and list `build/reports/...` gitignored paths as
  "latest evidence," pointing readers at files that are not tracked.
- Root `NA/ps7_summary.html` is a stray official export hidden by
  `.gitignore:7` `/NA/` rather than deleted.

## Suggested action order

This order is a suggestion only; the reviewer made no changes.

1. Checkpoint commit first (with user authorization): stage the eth example,
   software, tools, protocols, lookup-log, report, and the modified files.
   Then split into proper cycles.
2. Pick one HDMI path. Per code facts, keep VDMA/RGB888/800x600 and retire the
   custom-reader path and its build script. Align report/build/top/sim.
3. Run the route-deciding experiment: burn the official Linux image and ping
   the board. Half an hour, decides the whole sub-route.
4. Rewrite the RX blocker narrative: IDELAY=9 bridge is live and failed;
   suspect is BUFIO/BUFG crossing; next is either restore the Xilinx IP or an
   ILA capture, not more IDELAY tuning.
5. Unify the MVP definition across roadmap, README, and pipeline skill.
6. Backfill `cycle-log.md`; move debug narrative out of `current-cycle.md`.
7. Fix reproducibility: commit or document the required downloads.
8. Decouple the eth example from video-pip by giving it its own copy of the
   shared RTL or by extracting the shared modules.

## Reviewer note

The route is sound. The specific implementation sub-route under attack now
(hand-written RGMII bridge + bare-metal lwIP) is the part that is both harder
than the intended upper implementation and throwaway under the full-network
goal. The cheapest way to confirm or refute the whole sub-route is the Linux
ping experiment in step 3, not further bridge timing tuning.
