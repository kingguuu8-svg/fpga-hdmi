`timescale 1ns/1ps
`default_nettype none

module eth_ps_pl_hdmi_video_out #(
    parameter integer FRAME_BASE_ADDR = 32'h1000_0000,
    parameter integer STRIDE_BYTES = 1280
) (
    input  wire        pix_clk,
    input  wire        ser_clk,
    input  wire        reset,
    input  wire        frame_enable,

    output wire [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    input  wire [63:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,
    input  wire        m_axi_rlast,

    output wire        hdmi_clk_p,
    output wire        hdmi_clk_n,
    output wire [2:0]  hdmi_d_p,
    output wire [2:0]  hdmi_d_n,
    output wire        underflow,
    output wire        axi_error
);

    wire [10:0] x;
    wire [9:0] y;
    wire active;
    wire hsync;
    wire vsync;
    wire frame_start;
    wire line_start;
    wire [7:0] red;
    wire [7:0] green;
    wire [7:0] blue;
    wire pixel_valid;
    wire [9:0] tmds_red;
    wire [9:0] tmds_green;
    wire [9:0] tmds_blue;

    assign m_axi_awaddr = 32'd0;
    assign m_axi_awlen = 8'd0;
    assign m_axi_awsize = 3'b011;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = 1'b0;
    assign m_axi_wdata = 64'd0;
    assign m_axi_wstrb = 8'd0;
    assign m_axi_wlast = 1'b1;
    assign m_axi_wvalid = 1'b0;
    assign m_axi_bready = 1'b1;

    video_timing_640x480 timing_i (
        .pix_clk(pix_clk),
        .reset(reset),
        .x(x),
        .y(y),
        .active(active),
        .hsync(hsync),
        .vsync(vsync),
        .frame_start(frame_start),
        .line_start(line_start)
    );

    axi_framebuffer_line_reader #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(64),
        .H_ACTIVE(640),
        .V_ACTIVE(480)
    ) reader_i (
        .clk(pix_clk),
        .reset(reset),
        .enable(frame_enable),
        .frame_base_addr(FRAME_BASE_ADDR[31:0]),
        .stride_bytes(STRIDE_BYTES[15:0]),
        .x(x),
        .y(y),
        .active(active),
        .red(red),
        .green(green),
        .blue(blue),
        .pixel_valid(pixel_valid),
        .underflow(underflow),
        .axi_error(axi_error),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_rlast(m_axi_rlast)
    );

    tmds_encoder enc_blue_i (
        .clk(pix_clk),
        .reset(reset),
        .din(blue),
        .c0(hsync),
        .c1(vsync),
        .de(pixel_valid),
        .dout(tmds_blue)
    );

    tmds_encoder enc_green_i (
        .clk(pix_clk),
        .reset(reset),
        .din(green),
        .c0(1'b0),
        .c1(1'b0),
        .de(pixel_valid),
        .dout(tmds_green)
    );

    tmds_encoder enc_red_i (
        .clk(pix_clk),
        .reset(reset),
        .din(red),
        .c0(1'b0),
        .c1(1'b0),
        .de(pixel_valid),
        .dout(tmds_red)
    );

    hdmi_phy_7series phy_i (
        .pix_clk(pix_clk),
        .ser_clk(ser_clk),
        .reset(reset),
        .tmds_red(tmds_red),
        .tmds_green(tmds_green),
        .tmds_blue(tmds_blue),
        .hdmi_clk_p(hdmi_clk_p),
        .hdmi_clk_n(hdmi_clk_n),
        .hdmi_d_p(hdmi_d_p),
        .hdmi_d_n(hdmi_d_n)
    );

endmodule

`default_nettype wire
