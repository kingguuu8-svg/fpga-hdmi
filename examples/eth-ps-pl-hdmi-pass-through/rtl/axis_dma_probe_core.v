`timescale 1ns/1ps
`default_nettype none

module axis_dma_probe_core #(
    parameter integer DATA_WIDTH = 32,
    parameter integer KEEP_WIDTH = DATA_WIDTH / 8,
    parameter [31:0]  DEFAULT_MARKER_XOR = 32'h00000000
) (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    input  wire                      aclk,
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    input  wire                      aresetn,

    (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 6" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [5:0]                s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                      s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output reg                       s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]               s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                      s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg                       s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]                s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg                       s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                      s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [5:0]                s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                      s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg                       s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg  [31:0]               s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]                s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg                       s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                      s_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [DATA_WIDTH-1:0]     s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *)
    input  wire [KEEP_WIDTH-1:0]     s_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire                      s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire                      s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input  wire                      s_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [DATA_WIDTH-1:0]     m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [KEEP_WIDTH-1:0]     m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire                      m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire                      m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire                      m_axis_tlast,

    output reg  [31:0]               status_frames,
    output reg  [31:0]               status_beats,
    output reg  [31:0]               status_bytes,
    output reg  [31:0]               status_input_checksum,
    output reg  [31:0]               status_output_checksum
);

    localparam [5:0] REG_CONTROL = 6'h00;
    localparam [5:0] REG_MARKER_XOR = 6'h04;
    localparam [5:0] REG_FRAMES = 6'h10;
    localparam [5:0] REG_BEATS = 6'h14;
    localparam [5:0] REG_BYTES = 6'h18;
    localparam [5:0] REG_INPUT_CHECKSUM = 6'h1c;
    localparam [5:0] REG_OUTPUT_CHECKSUM = 6'h20;
    localparam [5:0] REG_LAST_FRAME_BYTES = 6'h24;

    reg        ctrl_enable;
    reg        ctrl_marker_enable;
    reg [31:0] marker_xor;
    reg [31:0] frame_bytes;
    reg [31:0] last_frame_bytes;

    wire axi_write_fire = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    wire axi_read_fire = s_axi_arvalid && !s_axi_rvalid;
    wire stream_fire = s_axis_tvalid && s_axis_tready;
    wire [31:0] data_in = s_axis_tdata[31:0];
    wire [31:0] marker_mask = ctrl_marker_enable ? marker_xor : 32'd0;
    wire [31:0] data_out = ctrl_enable ? (data_in ^ marker_mask) : data_in;
    wire [2:0] keep_bytes =
        {2'd0, s_axis_tkeep[0]} +
        {2'd0, s_axis_tkeep[1]} +
        {2'd0, s_axis_tkeep[2]} +
        {2'd0, s_axis_tkeep[3]};

    assign s_axis_tready = m_axis_tready;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tdata = data_out;
    assign m_axis_tkeep = s_axis_tkeep;
    assign m_axis_tlast = s_axis_tlast;
    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rvalid <= 1'b0;
            ctrl_enable <= 1'b1;
            ctrl_marker_enable <= 1'b0;
            marker_xor <= DEFAULT_MARKER_XOR;
            frame_bytes <= 32'd0;
            last_frame_bytes <= 32'd0;
            status_frames <= 32'd0;
            status_beats <= 32'd0;
            status_bytes <= 32'd0;
            status_input_checksum <= 32'd0;
            status_output_checksum <= 32'd0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_arready <= 1'b0;

            if (axi_write_fire) begin
                s_axi_awready <= 1'b1;
                s_axi_wready <= 1'b1;
                s_axi_bvalid <= 1'b1;
                case (s_axi_awaddr[5:0])
                    REG_CONTROL: begin
                        if (s_axi_wstrb[0]) begin
                            ctrl_enable <= s_axi_wdata[0];
                            ctrl_marker_enable <= s_axi_wdata[1];
                            if (s_axi_wdata[2]) begin
                                frame_bytes <= 32'd0;
                                last_frame_bytes <= 32'd0;
                                status_frames <= 32'd0;
                                status_beats <= 32'd0;
                                status_bytes <= 32'd0;
                                status_input_checksum <= 32'd0;
                                status_output_checksum <= 32'd0;
                            end
                        end
                    end
                    REG_MARKER_XOR: begin
                        if (s_axi_wstrb[0]) marker_xor[7:0] <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) marker_xor[15:8] <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) marker_xor[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) marker_xor[31:24] <= s_axi_wdata[31:24];
                    end
                    default: begin
                    end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (axi_read_fire) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid <= 1'b1;
                case (s_axi_araddr[5:0])
                    REG_CONTROL: s_axi_rdata <= {29'd0, 1'b0, ctrl_marker_enable, ctrl_enable};
                    REG_MARKER_XOR: s_axi_rdata <= marker_xor;
                    REG_FRAMES: s_axi_rdata <= status_frames;
                    REG_BEATS: s_axi_rdata <= status_beats;
                    REG_BYTES: s_axi_rdata <= status_bytes;
                    REG_INPUT_CHECKSUM: s_axi_rdata <= status_input_checksum;
                    REG_OUTPUT_CHECKSUM: s_axi_rdata <= status_output_checksum;
                    REG_LAST_FRAME_BYTES: s_axi_rdata <= last_frame_bytes;
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            if (stream_fire) begin
                status_beats <= status_beats + 32'd1;
                status_bytes <= status_bytes + {29'd0, keep_bytes};
                status_input_checksum <= status_input_checksum + data_in + {29'd0, keep_bytes};
                status_output_checksum <= status_output_checksum + data_out + {29'd0, keep_bytes};

                if (s_axis_tlast) begin
                    status_frames <= status_frames + 32'd1;
                    last_frame_bytes <= frame_bytes + {29'd0, keep_bytes};
                    frame_bytes <= 32'd0;
                end else begin
                    frame_bytes <= frame_bytes + {29'd0, keep_bytes};
                end
            end
        end
    end

endmodule

`default_nettype wire
