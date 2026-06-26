`timescale 1ns/1ps
`default_nettype none

module eth_ps_pl_hdmi_board_top (
    input  wire        clk,
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

    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [63:0] m_axi_wdata;
    wire [7:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [31:0] video_unused_awaddr;
    wire [7:0]  video_unused_awlen;
    wire [2:0]  video_unused_awsize;
    wire [1:0]  video_unused_awburst;
    wire        video_unused_awvalid;
    wire [63:0] video_unused_wdata;
    wire [7:0]  video_unused_wstrb;
    wire        video_unused_wlast;
    wire        video_unused_wvalid;
    wire        video_unused_bready;
    wire [63:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rvalid;
    wire        m_axi_rready;
    wire        m_axi_rlast;
    wire        underflow;
    wire        axi_error;
    wire        rgmii_probe_write_error;
    wire        axi_clk;
    wire        idelay_ref_clk;
    wire        gmii_rx_clk;
    wire        gmii_rx_dv;
    wire        gmii_rx_er;
    wire [7:0]  gmii_rxd;
    wire        gmii_tx_clk;
    wire        gmii_tx_en;
    wire        gmii_tx_er;
    wire [7:0]  gmii_txd;
    wire        mdio_phy_mdio_i;
    wire        mdio_phy_mdio_o;
    wire        mdio_phy_mdio_t;

    assign ETH_RST = reset_n;
    assign led[0] = underflow;
    assign led[1] = axi_error | rgmii_probe_write_error;

    eth_ps_pl_hdmi_top video_i (
        .clk(clk),
        .reset_n(reset_n),
        .axi_clk(axi_clk),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_awaddr(video_unused_awaddr),
        .m_axi_awlen(video_unused_awlen),
        .m_axi_awsize(video_unused_awsize),
        .m_axi_awburst(video_unused_awburst),
        .m_axi_awvalid(video_unused_awvalid),
        .m_axi_awready(1'b0),
        .m_axi_wdata(video_unused_wdata),
        .m_axi_wstrb(video_unused_wstrb),
        .m_axi_wlast(video_unused_wlast),
        .m_axi_wvalid(video_unused_wvalid),
        .m_axi_wready(1'b0),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(1'b0),
        .m_axi_bready(video_unused_bready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_rlast(m_axi_rlast),
        .hdmi_clk_p(hdmi_clk_p),
        .hdmi_clk_n(hdmi_clk_n),
        .hdmi_d_p(hdmi_d_p),
        .hdmi_d_n(hdmi_d_n),
        .underflow(underflow),
        .axi_error(axi_error)
    );

    rgmii_rx_activity_axi_writer rgmii_rx_probe_i (
        .reset_n(reset_n),
        .rgmii_rxc(RGMII_0_rxc),
        .rgmii_rx_ctl(RGMII_0_rx_ctl),
        .rgmii_rd(RGMII_0_rd),
        .axi_clk(axi_clk),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .write_error(rgmii_probe_write_error)
    );

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

    ZYNQ_wrapper ps_i (
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
        .FCLK_CLK0(idelay_ref_clk),
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
        .MDIO_ETHERNET_0_mdc(MDIO_PHY_0_mdc),
        .MDIO_ETHERNET_0_mdio_i(mdio_phy_mdio_i),
        .MDIO_ETHERNET_0_mdio_o(mdio_phy_mdio_o),
        .MDIO_ETHERNET_0_mdio_t(mdio_phy_mdio_t),
        .S_AXI_HP0_0_araddr(m_axi_araddr),
        .S_AXI_HP0_0_arburst(m_axi_arburst),
        .S_AXI_HP0_0_arcache(4'b0011),
        .S_AXI_HP0_0_arid(6'd0),
        .S_AXI_HP0_0_arlen(m_axi_arlen[3:0]),
        .S_AXI_HP0_0_arlock(2'b00),
        .S_AXI_HP0_0_arprot(3'b000),
        .S_AXI_HP0_0_arqos(4'd0),
        .S_AXI_HP0_0_arready(m_axi_arready),
        .S_AXI_HP0_0_arsize(m_axi_arsize),
        .S_AXI_HP0_0_arvalid(m_axi_arvalid),
        .S_AXI_HP0_0_awaddr(m_axi_awaddr),
        .S_AXI_HP0_0_awburst(m_axi_awburst),
        .S_AXI_HP0_0_awcache(4'b0011),
        .S_AXI_HP0_0_awid(6'd0),
        .S_AXI_HP0_0_awlen(m_axi_awlen[3:0]),
        .S_AXI_HP0_0_awlock(2'b00),
        .S_AXI_HP0_0_awprot(3'b000),
        .S_AXI_HP0_0_awqos(4'd0),
        .S_AXI_HP0_0_awready(m_axi_awready),
        .S_AXI_HP0_0_awsize(m_axi_awsize),
        .S_AXI_HP0_0_awvalid(m_axi_awvalid),
        .S_AXI_HP0_0_bid(),
        .S_AXI_HP0_0_bready(m_axi_bready),
        .S_AXI_HP0_0_bresp(m_axi_bresp),
        .S_AXI_HP0_0_bvalid(m_axi_bvalid),
        .S_AXI_HP0_0_rdata(m_axi_rdata),
        .S_AXI_HP0_0_rid(),
        .S_AXI_HP0_0_rlast(m_axi_rlast),
        .S_AXI_HP0_0_rready(m_axi_rready),
        .S_AXI_HP0_0_rresp(m_axi_rresp),
        .S_AXI_HP0_0_rvalid(m_axi_rvalid),
        .S_AXI_HP0_0_wdata(m_axi_wdata),
        .S_AXI_HP0_0_wid(6'd0),
        .S_AXI_HP0_0_wlast(m_axi_wlast),
        .S_AXI_HP0_0_wready(m_axi_wready),
        .S_AXI_HP0_0_wstrb(m_axi_wstrb),
        .S_AXI_HP0_0_wvalid(m_axi_wvalid),
        .S_AXI_HP0_ACLK_0(axi_clk),
        .UART_0_0_rxd(UART_0_0_rxd),
        .UART_0_0_txd(UART_0_0_txd)
    );

endmodule

`default_nettype wire
