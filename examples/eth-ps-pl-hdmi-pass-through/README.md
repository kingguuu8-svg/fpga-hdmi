# eth-ps-pl-hdmi-pass-through

Status: paused pending TF-card Linux route gate.

## Active Target

```text
PC UDP RGB888 800x600
-> PS/Linux or PS fallback receiver
-> DDR VDMA framebuffer at 0x01100000
-> VDMA MM2S -> v_axi4s_vid_out -> rgb2dvi -> HDMI
```

The output path is based on the official HelloFPGA VDMA HDMI example and has
passed as a black-box DDR-framebuffer-to-HDMI control image on the connected
board.

## Next Required Gate

Do not continue tuning the hand-written baremetal RGMII bridge while no TF card
is available. When a TF card arrives, follow:

```text
docs/reports/tf-card-linux-resume-2026-06-26.md
```

## Active Baremetal Fallback Entry Points

Use only if the Linux route gate fails or the user explicitly asks for the
baremetal fallback:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\eth-ps-pl-hdmi-pass-through\tcl\build-stage1-vdma-board-wsl.ps1
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\software\eth_pass_through\scripts\build-sdk-app-wsl.ps1
```

## Retired Entry Points

Do not use these as current-stage evidence:

```text
tcl/build-stage1-board-wsl.ps1
tcl/build_stage1_board.tcl
tcl/build-stage1-scaffold-wsl.ps1
tcl/build_stage1_scaffold.tcl
tcl/create_ps_emio_hp0_bd.tcl
rtl/axi_framebuffer_line_reader.v
rtl/eth_ps_pl_hdmi_board_top.v
rtl/eth_ps_pl_hdmi_top.v
rtl/eth_ps_pl_hdmi_video_out.v
sim/tb_axi_framebuffer_line_reader.v
xdc/stage1_board.xdc
```

Those files describe the old 640x480 RGB565 custom-reader path. They are
retained only for audit history until the next cleanup removes or archives
them.
