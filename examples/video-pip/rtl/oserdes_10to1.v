`timescale 1ns/1ps
`default_nettype none

module oserdes_10to1 (
    input  wire       pix_clk,
    input  wire       ser_clk,
    input  wire       reset,
    input  wire [9:0] data,
    output wire       serial
);

    wire shift1;
    wire shift2;

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"),
        .DATA_RATE_TQ("SDR"),
        .DATA_WIDTH(10),
        .INIT_OQ(1'b0),
        .INIT_TQ(1'b0),
        .SERDES_MODE("MASTER"),
        .SRVAL_OQ(1'b0),
        .SRVAL_TQ(1'b0),
        .TBYTE_CTL("FALSE"),
        .TBYTE_SRC("FALSE"),
        .TRISTATE_WIDTH(1)
    ) master_i (
        .OQ(serial),
        .OFB(),
        .TQ(),
        .TFB(),
        .TBYTEOUT(),
        .SHIFTOUT1(),
        .SHIFTOUT2(),
        .CLK(ser_clk),
        .CLKDIV(pix_clk),
        .D1(data[0]),
        .D2(data[1]),
        .D3(data[2]),
        .D4(data[3]),
        .D5(data[4]),
        .D6(data[5]),
        .D7(data[6]),
        .D8(data[7]),
        .OCE(1'b1),
        .RST(reset),
        .SHIFTIN1(shift1),
        .SHIFTIN2(shift2),
        .T1(1'b0),
        .T2(1'b0),
        .T3(1'b0),
        .T4(1'b0),
        .TBYTEIN(1'b0),
        .TCE(1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"),
        .DATA_RATE_TQ("SDR"),
        .DATA_WIDTH(10),
        .INIT_OQ(1'b0),
        .INIT_TQ(1'b0),
        .SERDES_MODE("SLAVE"),
        .SRVAL_OQ(1'b0),
        .SRVAL_TQ(1'b0),
        .TBYTE_CTL("FALSE"),
        .TBYTE_SRC("FALSE"),
        .TRISTATE_WIDTH(1)
    ) slave_i (
        .OQ(),
        .OFB(),
        .TQ(),
        .TFB(),
        .TBYTEOUT(),
        .SHIFTOUT1(shift1),
        .SHIFTOUT2(shift2),
        .CLK(ser_clk),
        .CLKDIV(pix_clk),
        .D1(1'b0),
        .D2(1'b0),
        .D3(data[8]),
        .D4(data[9]),
        .D5(1'b0),
        .D6(1'b0),
        .D7(1'b0),
        .D8(1'b0),
        .OCE(1'b1),
        .RST(reset),
        .SHIFTIN1(1'b0),
        .SHIFTIN2(1'b0),
        .T1(1'b0),
        .T2(1'b0),
        .T3(1'b0),
        .T4(1'b0),
        .TBYTEIN(1'b0),
        .TCE(1'b0)
    );

endmodule

`default_nettype wire
