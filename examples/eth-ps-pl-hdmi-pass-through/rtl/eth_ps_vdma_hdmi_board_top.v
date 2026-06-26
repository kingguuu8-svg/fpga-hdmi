`timescale 1ns/1ps
`default_nettype none

module eth_ps_vdma_hdmi_board_top (
    input  wire        reset_n,

    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    output wire        MDIO_PHY_0_mdc,
    inout  wire        MDIO_PHY_0_mdio_io,
    output wire        ETH_RST,
    input  wire [3:0]  RGMII_0_rd,
    input  wire        RGMII_0_rx_ctl,
    input  wire        RGMII_0_rxc,
    output wire [3:0]  RGMII_0_td,
    output wire        RGMII_0_tx_ctl,
    output wire        RGMII_0_txc,
    input  wire        UART_0_0_rxd,
    output wire        UART_0_0_txd,

    output wire        hdmi_clk_p,
    output wire        hdmi_clk_n,
    output wire [2:0]  hdmi_d_p,
    output wire [2:0]  hdmi_d_n,
    output wire [1:0]  led
);

    wire idelay_ref_clk;
    wire gmii_rx_clk;
    wire gmii_rx_dv;
    wire gmii_rx_er;
    wire [7:0] gmii_rxd;
    wire gmii_tx_clk;
    wire gmii_tx_en;
    wire gmii_tx_er;
    wire [7:0] gmii_txd;
    wire mdio_phy_mdio_i;
    wire mdio_phy_mdio_o;
    wire mdio_phy_mdio_t;
    wire tmds_clk_b_p_unused;
    wire tmds_clk_b_n_unused;

    assign ETH_RST = reset_n;
    assign led = 2'b00;

    rgmii_gmii_bridge #(
        .IDELAY_VALUE(9)
    ) rgmii_bridge_i (
        .idelay_clk(idelay_ref_clk),
        .rgmii_rxc(RGMII_0_rxc),
        .rgmii_rx_ctl(RGMII_0_rx_ctl),
        .rgmii_rxd(RGMII_0_rd),
        .rgmii_txc(RGMII_0_txc),
        .rgmii_tx_ctl(RGMII_0_tx_ctl),
        .rgmii_txd(RGMII_0_td),
        .gmii_rx_clk(gmii_rx_clk),
        .gmii_rx_dv(gmii_rx_dv),
        .gmii_rx_er(gmii_rx_er),
        .gmii_rxd(gmii_rxd),
        .gmii_tx_clk(gmii_tx_clk),
        .gmii_tx_en(gmii_tx_en),
        .gmii_tx_er(gmii_tx_er),
        .gmii_txd(gmii_txd)
    );

    IOBUF mdio_phy_iobuf (
        .I(mdio_phy_mdio_o),
        .O(mdio_phy_mdio_i),
        .T(mdio_phy_mdio_t),
        .IO(MDIO_PHY_0_mdio_io)
    );

    ZYNQ_CORE_wrapper ps_vdma_i (
        .DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .GMII_ETHERNET_0_col(1'b0),
        .GMII_ETHERNET_0_crs(1'b0),
        .GMII_ETHERNET_0_rx_clk(gmii_rx_clk),
        .GMII_ETHERNET_0_rx_dv(gmii_rx_dv),
        .GMII_ETHERNET_0_rx_er(gmii_rx_er),
        .GMII_ETHERNET_0_rxd(gmii_rxd),
        .GMII_ETHERNET_0_tx_clk(gmii_tx_clk),
        .GMII_ETHERNET_0_tx_en(gmii_tx_en),
        .GMII_ETHERNET_0_tx_er(gmii_tx_er),
        .GMII_ETHERNET_0_txd(gmii_txd),
        .IDELAY_REF_CLK(idelay_ref_clk),
        .MDIO_ETHERNET_0_mdc(MDIO_PHY_0_mdc),
        .MDIO_ETHERNET_0_mdio_i(mdio_phy_mdio_i),
        .MDIO_ETHERNET_0_mdio_o(mdio_phy_mdio_o),
        .MDIO_ETHERNET_0_mdio_t(mdio_phy_mdio_t),
        .TMDS_0_clk_n(hdmi_clk_n),
        .TMDS_0_clk_p(hdmi_clk_p),
        .TMDS_0_data_n(hdmi_d_n),
        .TMDS_0_data_p(hdmi_d_p),
        .TMDS_Clk_b_n_0(tmds_clk_b_n_unused),
        .TMDS_Clk_b_p_0(tmds_clk_b_p_unused),
        .UART_0_0_rxd(UART_0_0_rxd),
        .UART_0_0_txd(UART_0_0_txd)
    );

endmodule

`default_nettype wire
