# HelloFPGA Smart ZYNQ SL 7020 profile.
#
# Evidence:
# - Connected JTAG cable reports "HelloFpga JTAG-JT2" and target "xc7z020".
# - Official SmartZynq SL schematic V1.3 page 10 lists:
#   50M CLOCK CLK=M19, KEY1=K21, KEY2=J20, LED1=P20, LED2=P21.
# - Official pin constraint reference page 11 lists:
#   clk_50=M19, LED1=P20, LED2=P21, all LVCMOS33.
# - Official LED circuit page 6 drives LED1/LED2 through 30R to ground, so the
#   LEDs are active-high.
# - Official KEY circuit page 6 shows KEY1/KEY2 pulled up to 3.3V and switched
#   to ground, so the keys are active-low.
# - https://github.com/hennichodernich/hellofpga-smartzynq-notes Makefile uses
#   PART = xc7z020clg484-1 for SmartZynq.
set board_name "hellofpga-smart-zynq-sl-7020"
set part "xc7z020clg484-1"
set clock_required 1
set clock_port "clk"
set clock_pin "M19"
set clock_period_ns 20.000
set clock_iostandard "LVCMOS33"
set led_port "led"
set led_pins {P20 P21}
set led_iostandard "LVCMOS33"
set led_active_low 0
set led_slew "SLOW"
set led_drive 4
set key_port "key"
set key_pins {K21 J20}
set key_iostandard "LVCMOS33"
set key_active_low 1
set hdmi_tmds_iostandard "TMDS_33"
set hdmi_output_iostandard "LVCMOS33"
set hdmi_clk_p_pin "N19"
set hdmi_d_p_pins {M21 L21 J21}
