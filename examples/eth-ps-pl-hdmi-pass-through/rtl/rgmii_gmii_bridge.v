`timescale 1ns/1ps
`default_nettype none

// RGMII <-> GMII bridge adapted from the official HelloFPGA Smart ZYNQ
// pure-PL UDP loopback project. The important board-specific behavior is the
// fixed RX-side IDELAY on data/control, which matched the verified official
// Ethernet loopback on the connected board.
module rgmii_gmii_bridge #(
    parameter integer IDELAY_VALUE = 9
) (
    input  wire        idelay_clk,

    input  wire        rgmii_rxc,
    input  wire        rgmii_rx_ctl,
    input  wire [3:0]  rgmii_rxd,
    output wire        rgmii_txc,
    output wire        rgmii_tx_ctl,
    output wire [3:0]  rgmii_txd,

    output wire        gmii_rx_clk,
    output wire        gmii_rx_dv,
    output wire        gmii_rx_er,
    output wire [7:0]  gmii_rxd,
    output wire        gmii_tx_clk,
    input  wire        gmii_tx_en,
    input  wire        gmii_tx_er,
    input  wire [7:0]  gmii_txd
);

    wire        rgmii_rxc_bufg;
    wire        rgmii_rxc_bufio;
    wire [1:0]  rx_ctl_ddr;
    wire [3:0]  rgmii_rxd_delay;
    wire        rgmii_rx_ctl_delay;

    assign gmii_rx_clk = rgmii_rxc_bufg;
    assign gmii_tx_clk = gmii_rx_clk;
    assign rgmii_txc = gmii_tx_clk;
    assign gmii_rx_dv = rx_ctl_ddr[0] & rx_ctl_ddr[1];
    // Match the official HelloFPGA PL UDP bridge: only RX_DV is consumed by
    // downstream logic. Driving a marginal RX_ER into PS GEM causes frame
    // drops when RX_CTL has edge noise near packet boundaries.
    assign gmii_rx_er = 1'b0;

    BUFG rx_clk_bufg_i (
        .I(rgmii_rxc),
        .O(rgmii_rxc_bufg)
    );

    BUFIO rx_clk_bufio_i (
        .I(rgmii_rxc),
        .O(rgmii_rxc_bufio)
    );

    IDELAYCTRL idelayctrl_i (
        .RDY(),
        .REFCLK(idelay_clk),
        .RST(1'b0)
    );

    IDELAYE2 #(
        .IDELAY_TYPE("FIXED"),
        .IDELAY_VALUE(IDELAY_VALUE),
        .REFCLK_FREQUENCY(200.0)
    ) delay_rx_ctl_i (
        .CNTVALUEOUT(),
        .DATAOUT(rgmii_rx_ctl_delay),
        .C(1'b0),
        .CE(1'b0),
        .CINVCTRL(1'b0),
        .CNTVALUEIN(5'b0),
        .DATAIN(1'b0),
        .IDATAIN(rgmii_rx_ctl),
        .INC(1'b0),
        .LD(1'b0),
        .LDPIPEEN(1'b0),
        .REGRST(1'b0)
    );

    IDDR #(
        .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
        .INIT_Q1(1'b0),
        .INIT_Q2(1'b0),
        .SRTYPE("SYNC")
    ) iddr_rx_ctl_i (
        .Q1(rx_ctl_ddr[0]),
        .Q2(rx_ctl_ddr[1]),
        .C(rgmii_rxc_bufio),
        .CE(1'b1),
        .D(rgmii_rx_ctl_delay),
        .R(1'b0),
        .S(1'b0)
    );

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_rx_data
            IDELAYE2 #(
                .IDELAY_TYPE("FIXED"),
                .IDELAY_VALUE(IDELAY_VALUE),
                .REFCLK_FREQUENCY(200.0)
            ) delay_rxd_i (
                .CNTVALUEOUT(),
                .DATAOUT(rgmii_rxd_delay[i]),
                .C(1'b0),
                .CE(1'b0),
                .CINVCTRL(1'b0),
                .CNTVALUEIN(5'b0),
                .DATAIN(1'b0),
                .IDATAIN(rgmii_rxd[i]),
                .INC(1'b0),
                .LD(1'b0),
                .LDPIPEEN(1'b0),
                .REGRST(1'b0)
            );

            IDDR #(
                .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
                .INIT_Q1(1'b0),
                .INIT_Q2(1'b0),
                .SRTYPE("SYNC")
            ) iddr_rxd_i (
                .Q1(gmii_rxd[i]),
                .Q2(gmii_rxd[4 + i]),
                .C(rgmii_rxc_bufio),
                .CE(1'b1),
                .D(rgmii_rxd_delay[i]),
                .R(1'b0),
                .S(1'b0)
            );
        end
    endgenerate

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) oddr_tx_ctl_i (
        .Q(rgmii_tx_ctl),
        .C(gmii_tx_clk),
        .CE(1'b1),
        .D1(gmii_tx_en),
        .D2(gmii_tx_en),
        .R(1'b0),
        .S(1'b0)
    );

    genvar j;
    generate
        for (j = 0; j < 4; j = j + 1) begin : g_tx_data
            ODDR #(
                .DDR_CLK_EDGE("SAME_EDGE"),
                .INIT(1'b0),
                .SRTYPE("SYNC")
            ) oddr_txd_i (
                .Q(rgmii_txd[j]),
                .C(gmii_tx_clk),
                .CE(1'b1),
                .D1(gmii_txd[j]),
                .D2(gmii_txd[4 + j]),
                .R(1'b0),
                .S(1'b0)
            );
        end
    endgenerate

endmodule

`default_nettype wire
