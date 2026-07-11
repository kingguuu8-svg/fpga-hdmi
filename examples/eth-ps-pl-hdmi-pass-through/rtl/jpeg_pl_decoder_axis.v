`timescale 1ns/1ps
`default_nettype none

module jpeg_pl_decoder_axis (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:S_JPEG:M_CMD:M_DATA:S_STS, ASSOCIATED_RESET aresetn" *)
    input  wire         aclk,
    input  wire         aresetn,

    input  wire [5:0]   s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [5:0]   s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    input  wire [31:0]  s_jpeg_tdata,
    input  wire [3:0]   s_jpeg_tkeep,
    input  wire         s_jpeg_tlast,
    input  wire         s_jpeg_tvalid,
    output wire         s_jpeg_tready,

    output wire [71:0]  m_cmd_tdata,
    output wire         m_cmd_tvalid,
    input  wire         m_cmd_tready,
    output wire [31:0]  m_data_tdata,
    output wire [3:0]   m_data_tkeep,
    output wire         m_data_tlast,
    output wire         m_data_tvalid,
    input  wire         m_data_tready,
    input  wire [7:0]   s_sts_tdata,
    input  wire         s_sts_tvalid,
    output wire         s_sts_tready
);
    wire core_accept;
    wire core_valid;
    wire core_idle;
    wire [15:0] core_width;
    wire [15:0] core_height;
    wire [15:0] core_x;
    wire [15:0] core_y;
    wire [7:0] core_r;
    wire [7:0] core_g;
    wire [7:0] core_b;
    wire pixel_ready;
    wire decode_start;
    wire input_sink_mode;
    reg [31:0] input_bytes;

    wire jpeg_fire = s_jpeg_tvalid && s_jpeg_tready;
    wire [2:0] jpeg_keep_bytes =
        {2'd0, s_jpeg_tkeep[0]} + {2'd0, s_jpeg_tkeep[1]} +
        {2'd0, s_jpeg_tkeep[2]} + {2'd0, s_jpeg_tkeep[3]};

    assign s_jpeg_tready =
        aresetn && !decode_start && (input_sink_mode || core_accept);

    always @(posedge aclk) begin
        if (!aresetn || decode_start)
            input_bytes <= 32'd0;
        else if (jpeg_fire)
            input_bytes <= input_bytes + {29'd0, jpeg_keep_bytes};
    end

    jpeg_core #(
        .SUPPORT_WRITABLE_DHT(0)
    ) u_jpeg_core (
        .clk_i(aclk),
        .rst_i(!aresetn || decode_start || input_sink_mode),
        .inport_valid_i(s_jpeg_tvalid && !decode_start && !input_sink_mode),
        .inport_data_i(s_jpeg_tdata),
        .inport_strb_i(s_jpeg_tkeep),
        .inport_last_i(1'b0),
        .outport_accept_i(pixel_ready),
        .inport_accept_o(core_accept),
        .outport_valid_o(core_valid),
        .outport_width_o(core_width),
        .outport_height_o(core_height),
        .outport_pixel_x_o(core_x),
        .outport_pixel_y_o(core_y),
        .outport_pixel_r_o(core_r),
        .outport_pixel_g_o(core_g),
        .outport_pixel_b_o(core_b),
        .idle_o(core_idle)
    );

    jpeg_rgb_tile_writer u_writer (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .pixel_valid(core_valid),
        .pixel_ready(pixel_ready),
        .pixel_x(core_x),
        .pixel_y(core_y),
        .pixel_width(core_width),
        .pixel_height(core_height),
        .pixel_r(core_r),
        .pixel_g(core_g),
        .pixel_b(core_b),
        .decoder_idle(core_idle),
        .input_bytes(input_bytes),
        .m_axis_cmd_tdata(m_cmd_tdata),
        .m_axis_cmd_tvalid(m_cmd_tvalid),
        .m_axis_cmd_tready(m_cmd_tready),
        .m_axis_data_tdata(m_data_tdata),
        .m_axis_data_tkeep(m_data_tkeep),
        .m_axis_data_tlast(m_data_tlast),
        .m_axis_data_tvalid(m_data_tvalid),
        .m_axis_data_tready(m_data_tready),
        .s_axis_sts_tdata(s_sts_tdata),
        .s_axis_sts_tvalid(s_sts_tvalid),
        .s_axis_sts_tready(s_sts_tready),
        .input_sink_mode(input_sink_mode),
        .decode_start(decode_start)
    );

    wire unused_jpeg_tlast = s_jpeg_tlast;
endmodule

`default_nettype wire
