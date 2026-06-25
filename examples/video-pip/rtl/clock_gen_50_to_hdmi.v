`timescale 1ns/1ps
`default_nettype none

module clock_gen_50_to_hdmi (
    input  wire clk_50,
    input  wire reset,
    output wire pix_clk,
    output wire ser_clk,
    output wire locked
);

    wire clkfb;
    wire clkfb_buf;
    wire pix_clk_raw;
    wire ser_clk_raw;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(20.000),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(20.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(40.000),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT1_DIVIDE(8),
        .CLKOUT1_PHASE(0.000),
        .CLKOUT1_DUTY_CYCLE(0.500),
        .STARTUP_WAIT("FALSE")
    ) mmcm_i (
        .CLKIN1(clk_50),
        .CLKFBIN(clkfb_buf),
        .CLKFBOUT(clkfb),
        .CLKFBOUTB(),
        .CLKOUT0(pix_clk_raw),
        .CLKOUT0B(),
        .CLKOUT1(ser_clk_raw),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(locked),
        .PWRDWN(1'b0),
        .RST(reset)
    );

    BUFG clkfb_buf_i (.I(clkfb), .O(clkfb_buf));
    BUFG pix_buf_i (.I(pix_clk_raw), .O(pix_clk));
    BUFG ser_buf_i (.I(ser_clk_raw), .O(ser_clk));

endmodule

`default_nettype wire
