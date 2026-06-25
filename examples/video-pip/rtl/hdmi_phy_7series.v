`timescale 1ns/1ps
`default_nettype none

module hdmi_phy_7series (
    input  wire       pix_clk,
    input  wire       ser_clk,
    input  wire       reset,
    input  wire [9:0] tmds_red,
    input  wire [9:0] tmds_green,
    input  wire [9:0] tmds_blue,
    output wire       hdmi_clk_p,
    output wire       hdmi_clk_n,
    output wire [2:0] hdmi_d_p,
    output wire [2:0] hdmi_d_n
);

    wire clk_serial;
    wire red_serial;
    wire green_serial;
    wire blue_serial;

    oserdes_10to1 clk_ser_i (
        .pix_clk(pix_clk),
        .ser_clk(ser_clk),
        .reset(reset),
        .data(10'b0000011111),
        .serial(clk_serial)
    );

    oserdes_10to1 blue_ser_i (
        .pix_clk(pix_clk),
        .ser_clk(ser_clk),
        .reset(reset),
        .data(tmds_blue),
        .serial(blue_serial)
    );

    oserdes_10to1 green_ser_i (
        .pix_clk(pix_clk),
        .ser_clk(ser_clk),
        .reset(reset),
        .data(tmds_green),
        .serial(green_serial)
    );

    oserdes_10to1 red_ser_i (
        .pix_clk(pix_clk),
        .ser_clk(ser_clk),
        .reset(reset),
        .data(tmds_red),
        .serial(red_serial)
    );

    OBUFDS #(.IOSTANDARD("TMDS_33")) clk_obuf_i (
        .I(clk_serial),
        .O(hdmi_clk_p),
        .OB(hdmi_clk_n)
    );
    OBUFDS #(.IOSTANDARD("TMDS_33")) blue_obuf_i (
        .I(blue_serial),
        .O(hdmi_d_p[0]),
        .OB(hdmi_d_n[0])
    );
    OBUFDS #(.IOSTANDARD("TMDS_33")) green_obuf_i (
        .I(green_serial),
        .O(hdmi_d_p[1]),
        .OB(hdmi_d_n[1])
    );
    OBUFDS #(.IOSTANDARD("TMDS_33")) red_obuf_i (
        .I(red_serial),
        .O(hdmi_d_p[2]),
        .OB(hdmi_d_n[2])
    );

endmodule

`default_nettype wire
