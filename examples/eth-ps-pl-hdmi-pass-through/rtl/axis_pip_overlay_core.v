`timescale 1ns/1ps
`default_nettype none

module axis_pip_overlay_core #(
    parameter integer FRAME_W = 1280,
    parameter integer FRAME_H = 720,
    parameter integer PIP_X = 1088,
    parameter integer PIP_Y = 598,
    parameter integer PIP_W = 320,
    parameter integer PIP_H = 180,
    parameter integer SCALE_X = 4,
    parameter integer SCALE_Y = 4,
    parameter integer BORDER = 2
) (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:S_MAIN:S_PIP:M_AXIS, ASSOCIATED_RESET aresetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    input  wire        aclk,
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    input  wire        aresetn,

    (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 6" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [5:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output reg         s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg         s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg         s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [5:0]  s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg         s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg  [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg         s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire        s_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_MAIN TDATA" *)
    input  wire [23:0] s_main_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_MAIN TVALID" *)
    input  wire        s_main_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_MAIN TREADY" *)
    output wire        s_main_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_MAIN TLAST" *)
    input  wire        s_main_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_MAIN TUSER" *)
    input  wire        s_main_tuser,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_PIP TDATA" *)
    input  wire [23:0] s_pip_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_PIP TVALID" *)
    input  wire        s_pip_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_PIP TREADY" *)
    output wire        s_pip_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_PIP TLAST" *)
    input  wire        s_pip_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_PIP TUSER" *)
    input  wire        s_pip_tuser,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [23:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire        m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire        m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire        m_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TUSER" *)
    output wire        m_axis_tuser,

    output reg  [31:0] status_main_frames,
    output reg  [31:0] status_pip_frames,
    output reg  [31:0] status_overlay_pixels
);

    localparam integer PIP_PIXELS = PIP_W * PIP_H;
    localparam integer PIP_ADDR_WIDTH = (PIP_PIXELS <= 2) ? 1 : $clog2(PIP_PIXELS);
    localparam [15:0] FRAME_W_L = FRAME_W;
    localparam [15:0] FRAME_H_LAST = FRAME_H - 1;
    localparam [15:0] PIP_W_L = PIP_W;
    localparam [15:0] PIP_H_L = PIP_H;
    localparam [15:0] BORDER_L = BORDER;

    localparam [5:0] REG_CONTROL = 6'h00;
    localparam [5:0] REG_X = 6'h04;
    localparam [5:0] REG_Y = 6'h08;
    localparam [5:0] REG_STATUS = 6'h0c;
    localparam [5:0] REG_MAIN_FRAMES = 6'h10;
    localparam [5:0] REG_PIP_FRAMES = 6'h14;
    localparam [5:0] REG_OVERLAY_PIXELS = 6'h18;

    localparam [1:0] SCALE_HALF = 2'd0;
    localparam [1:0] SCALE_QUARTER = 2'd1;
    localparam [1:0] EFFECT_NORMAL = 2'd0;
    localparam [1:0] EFFECT_INVERT = 2'd1;
    localparam [1:0] EFFECT_GRAYSCALE = 2'd2;

    reg        ctrl_enable;
    reg        ctrl_border_enable;
    reg [1:0]  ctrl_scale_mode;
    reg [1:0]  ctrl_effect_mode;
    reg [15:0] ctrl_pip_x;
    reg [15:0] ctrl_pip_y;

    reg [15:0] main_x;
    reg [15:0] main_y;
    reg [15:0] pip_x;
    reg [15:0] pip_y;
    reg [15:0] pip_mod_x;
    reg [15:0] pip_mod_y;
    reg [15:0] pip_scaled_x_ctr;
    reg [15:0] pip_scaled_y_ctr;
    reg [31:0] pip_read_addr_ctr;
    reg [31:0] pip_write_addr_ctr;
    reg [31:0] pip_write_row_base;
    reg        pip_frame_valid;
    reg        pip_read_bank;
    reg        pip_write_bank;
    reg        pip_in_valid;
    reg [23:0] pip_in_data;
    reg        pip_in_tlast;
    reg        pip_in_tuser;
    // Keep the write-side pipeline as a real boundary before the frame RAM.
    (* KEEP = "true", DONT_TOUCH = "true" *) reg        pip_ram_wr_en_r;
    (* KEEP = "true", DONT_TOUCH = "true" *) reg        pip_ram_wr_bank_r;
    (* KEEP = "true", DONT_TOUCH = "true" *) reg [PIP_ADDR_WIDTH-1:0] pip_ram_wr_addr_r;
    (* KEEP = "true", DONT_TOUCH = "true" *) reg [23:0] pip_ram_wr_data_r;
    reg        pip_frame_commit_pending;
    reg        input_valid;
    reg [23:0] input_main_data;
    reg        input_tlast;
    reg        input_tuser;
    reg        input_in_pip;
    reg        input_in_border;
    reg        input_pip_frame_valid;
    reg        input_pip_read_bank;
    reg [PIP_ADDR_WIDTH-1:0] input_pip_read_addr;

    reg        stage_pip_read_bank;
    reg        stage_valid;
    reg [23:0] stage_main_data;
    reg        stage_tlast;
    reg        stage_tuser;
    reg        stage_in_pip;
    reg        stage_in_border;
    reg        stage_pip_frame_valid;
    reg        stage_effect_valid;
    reg [23:0] stage_effect_main_data;
    reg [23:0] stage_effect_pip_data;
    reg        stage_effect_in_pip;
    reg        stage_effect_in_border;
    reg        stage_effect_pip_frame_valid;
    reg        stage_effect_tlast;
    reg        stage_effect_tuser;
    reg [23:0] m_axis_tdata_r;
    reg        m_axis_tvalid_r;
    reg        m_axis_tlast_r;
    reg        m_axis_tuser_r;

    wire axi_write_fire = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    wire axi_read_fire = s_axi_arvalid && !s_axi_rvalid;

    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

    wire main_fire = s_main_tvalid && s_main_tready;
    wire pip_fire = pip_in_valid;
    wire output_ready = !m_axis_tvalid_r || m_axis_tready;

    wire [15:0] main_cur_x = s_main_tuser ? 16'd0 : main_x;
    wire [15:0] main_cur_y = s_main_tuser ? 16'd0 : main_y;
    wire [15:0] pip_cur_x = pip_in_tuser ? 16'd0 : pip_x;
    wire [15:0] pip_cur_y = pip_in_tuser ? 16'd0 : pip_y;

    wire scale_half = (ctrl_scale_mode == SCALE_HALF);
    wire [15:0] active_pip_w = scale_half ? PIP_W_L : {1'b0, PIP_W_L[15:1]};
    wire [15:0] active_pip_h = scale_half ? PIP_H_L : {1'b0, PIP_H_L[15:1]};
    localparam [15:0] CAPTURE_X_LAST = SCALE_X - 1;
    localparam [15:0] CAPTURE_Y_LAST = SCALE_Y - 1;
    wire [16:0] pip_x_end = {1'b0, ctrl_pip_x} + {1'b0, active_pip_w};
    wire [16:0] pip_y_end = {1'b0, ctrl_pip_y} + {1'b0, active_pip_h};
    wire [15:0] main_local_x = main_cur_x - ctrl_pip_x;
    wire [15:0] main_local_y = main_cur_y - ctrl_pip_y;
    wire [15:0] border_x_start = active_pip_w - BORDER_L;
    wire [15:0] border_y_start = active_pip_h - BORDER_L;
    wire in_pip_x = (main_cur_x >= ctrl_pip_x) && ({1'b0, main_cur_x} < pip_x_end);
    wire in_pip_y = (main_cur_y >= ctrl_pip_y) && ({1'b0, main_cur_y} < pip_y_end);
    wire in_pip = ctrl_enable && in_pip_x && in_pip_y;
    wire in_border = ctrl_border_enable && in_pip &&
        ((main_local_x < BORDER_L) ||
         (main_local_y < BORDER_L) ||
         (main_local_x >= border_x_start) ||
         (main_local_y >= border_y_start));
    wire [7:0] pip_gray = stage_effect_pip_data[15:8];
    wire [23:0] pip_effect_data = (ctrl_effect_mode == EFFECT_INVERT) ? ~stage_effect_pip_data :
                                  (ctrl_effect_mode == EFFECT_GRAYSCALE) ? {pip_gray, pip_gray, pip_gray} :
                                  stage_effect_pip_data;
    wire [23:0] stage_overlay_data = stage_effect_in_border ? 24'hffffff :
                                      (stage_effect_in_pip && stage_effect_pip_frame_valid) ? pip_effect_data :
                                      stage_effect_main_data;

    wire pip_start = pip_in_tuser;
    wire [15:0] pip_mod_x_cur = pip_start ? 16'd0 : pip_mod_x;
    wire [15:0] pip_mod_y_cur = pip_start ? 16'd0 : pip_mod_y;
    wire [15:0] pip_scaled_x_cur = pip_start ? 16'd0 : pip_scaled_x_ctr;
    wire [15:0] pip_scaled_y_cur = pip_start ? 16'd0 : pip_scaled_y_ctr;
    wire [31:0] pip_write_row_base_cur = pip_start ? 32'd0 : pip_write_row_base;
    wire [31:0] pip_write_addr_cur = pip_start ? 32'd0 : pip_write_addr_ctr;
    wire pip_sample_x = (pip_cur_x < FRAME_W_L) && (pip_mod_x_cur == 16'd0);
    wire pip_sample_y = (pip_cur_y <= FRAME_H_LAST) && (pip_mod_y_cur == 16'd0);
    wire pip_sample_in_window = pip_sample_x && pip_sample_y &&
        (pip_scaled_x_cur < PIP_W_L) && (pip_scaled_y_cur < PIP_H_L);

    // Both banks have the same geometry. A completed frame can therefore be
    // displayed while the next frame is being sampled without mixed sizes.
    wire [23:0] pip_mem_a_rd_data;
    wire [23:0] pip_mem_b_rd_data;
    // Register the read decision and address before driving the frame RAM.
    // This keeps control geometry out of the 150 MHz BRAM enable path.
    wire        pip_ram_rd_en = input_valid && input_in_pip;
    wire        pip_ram_a_wr_en = pip_ram_wr_en_r && !pip_ram_wr_bank_r;
    wire        pip_ram_b_wr_en = pip_ram_wr_en_r && pip_ram_wr_bank_r;

    axis_pip_frame_ram #(
        .DEPTH(PIP_PIXELS),
        .ADDR_WIDTH(PIP_ADDR_WIDTH)
    ) pip_frame_ram_a (
        .clk(aclk),
        .wr_en(pip_ram_a_wr_en),
        .wr_addr(pip_ram_wr_addr_r),
        .wr_data(pip_ram_wr_data_r),
        .rd_en(pip_ram_rd_en && !input_pip_read_bank),
        .rd_addr(input_pip_read_addr),
        .rd_data(pip_mem_a_rd_data)
    );

    axis_pip_frame_ram #(
        .DEPTH(PIP_PIXELS),
        .ADDR_WIDTH(PIP_ADDR_WIDTH)
    ) pip_frame_ram_b (
        .clk(aclk),
        .wr_en(pip_ram_b_wr_en),
        .wr_addr(pip_ram_wr_addr_r),
        .wr_data(pip_ram_wr_data_r),
        .rd_en(pip_ram_rd_en && input_pip_read_bank),
        .rd_addr(input_pip_read_addr),
        .rd_data(pip_mem_b_rd_data)
    );

    assign s_main_tready = output_ready;
    assign s_pip_tready = output_ready;
    assign m_axis_tvalid = m_axis_tvalid_r;
    assign m_axis_tdata = m_axis_tdata_r;
    assign m_axis_tlast = m_axis_tlast_r;
    assign m_axis_tuser = m_axis_tuser_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            main_x <= 16'd0;
            main_y <= 16'd0;
            pip_x <= 16'd0;
            pip_y <= 16'd0;
            pip_mod_x <= 16'd0;
            pip_mod_y <= 16'd0;
            pip_scaled_x_ctr <= 16'd0;
            pip_scaled_y_ctr <= 16'd0;
            pip_read_addr_ctr <= 32'd0;
            pip_write_addr_ctr <= 32'd0;
            pip_write_row_base <= 32'd0;
            pip_frame_valid <= 1'b0;
            pip_read_bank <= 1'b0;
            pip_write_bank <= 1'b1;
            pip_in_valid <= 1'b0;
            pip_in_data <= 24'd0;
            pip_in_tlast <= 1'b0;
            pip_in_tuser <= 1'b0;
            pip_ram_wr_en_r <= 1'b0;
            pip_ram_wr_bank_r <= 1'b0;
            pip_ram_wr_addr_r <= {PIP_ADDR_WIDTH{1'b0}};
            pip_ram_wr_data_r <= 24'd0;
            pip_frame_commit_pending <= 1'b0;
            input_valid <= 1'b0;
            input_main_data <= 24'd0;
            input_tlast <= 1'b0;
            input_tuser <= 1'b0;
            input_in_pip <= 1'b0;
            input_in_border <= 1'b0;
            input_pip_frame_valid <= 1'b0;
            input_pip_read_bank <= 1'b0;
            input_pip_read_addr <= {PIP_ADDR_WIDTH{1'b0}};
            stage_valid <= 1'b0;
            stage_main_data <= 24'd0;
            stage_tlast <= 1'b0;
            stage_tuser <= 1'b0;
            stage_in_pip <= 1'b0;
            stage_in_border <= 1'b0;
            stage_pip_frame_valid <= 1'b0;
            stage_pip_read_bank <= 1'b0;
            stage_effect_valid <= 1'b0;
            stage_effect_main_data <= 24'd0;
            stage_effect_pip_data <= 24'd0;
            stage_effect_in_pip <= 1'b0;
            stage_effect_in_border <= 1'b0;
            stage_effect_pip_frame_valid <= 1'b0;
            stage_effect_tlast <= 1'b0;
            stage_effect_tuser <= 1'b0;
            m_axis_tdata_r <= 24'd0;
            m_axis_tvalid_r <= 1'b0;
            m_axis_tlast_r <= 1'b0;
            m_axis_tuser_r <= 1'b0;
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rvalid <= 1'b0;
            ctrl_enable <= 1'b1;
            ctrl_border_enable <= 1'b1;
            ctrl_scale_mode <= SCALE_QUARTER;
            ctrl_effect_mode <= EFFECT_NORMAL;
            ctrl_pip_x <= PIP_X[15:0];
            ctrl_pip_y <= PIP_Y[15:0];
            status_main_frames <= 32'd0;
            status_pip_frames <= 32'd0;
            status_overlay_pixels <= 32'd0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_arready <= 1'b0;

            pip_in_valid <= s_pip_tvalid && s_pip_tready;
            pip_in_data <= s_pip_tdata;
            pip_in_tlast <= s_pip_tlast;
            pip_in_tuser <= s_pip_tuser;
            pip_ram_wr_en_r <= pip_fire && pip_sample_in_window;
            pip_ram_wr_bank_r <= pip_write_bank;
            pip_ram_wr_addr_r <= pip_write_addr_cur[PIP_ADDR_WIDTH-1:0];
            pip_ram_wr_data_r <= pip_in_data;

            if (pip_frame_commit_pending) begin
                pip_frame_valid <= 1'b1;
                pip_frame_commit_pending <= 1'b0;
            end

            if (axi_write_fire) begin
                s_axi_awready <= 1'b1;
                s_axi_wready <= 1'b1;
                s_axi_bvalid <= 1'b1;
                case (s_axi_awaddr[5:0])
                    REG_CONTROL: begin
                        if (s_axi_wstrb[0]) begin
                            ctrl_enable <= s_axi_wdata[0];
                            ctrl_border_enable <= s_axi_wdata[1];
                            ctrl_scale_mode <= s_axi_wdata[3:2];
                            ctrl_effect_mode <= s_axi_wdata[5:4];
                        end
                    end
                    REG_X: begin
                        if (s_axi_wstrb[0]) ctrl_pip_x[7:0] <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) ctrl_pip_x[15:8] <= s_axi_wdata[15:8];
                    end
                    REG_Y: begin
                        if (s_axi_wstrb[0]) ctrl_pip_y[7:0] <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) ctrl_pip_y[15:8] <= s_axi_wdata[15:8];
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
                    REG_CONTROL: s_axi_rdata <= {26'd0, ctrl_effect_mode, ctrl_scale_mode, ctrl_border_enable, ctrl_enable};
                    REG_X: s_axi_rdata <= {16'd0, ctrl_pip_x};
                    REG_Y: s_axi_rdata <= {16'd0, ctrl_pip_y};
                    REG_STATUS: s_axi_rdata <= {active_pip_h, active_pip_w};
                    REG_MAIN_FRAMES: s_axi_rdata <= status_main_frames;
                    REG_PIP_FRAMES: s_axi_rdata <= status_pip_frames;
                    REG_OVERLAY_PIXELS: s_axi_rdata <= status_overlay_pixels;
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            if (output_ready) begin
                m_axis_tvalid_r <= stage_effect_valid;
                m_axis_tdata_r <= stage_overlay_data;
                m_axis_tlast_r <= stage_effect_valid ? stage_effect_tlast : 1'b0;
                m_axis_tuser_r <= stage_effect_valid ? stage_effect_tuser : 1'b0;

                stage_effect_valid <= stage_valid;
                if (stage_valid) begin
                    stage_effect_main_data <= stage_main_data;
                    stage_effect_pip_data <= stage_pip_read_bank ?
                        pip_mem_b_rd_data : pip_mem_a_rd_data;
                    stage_effect_in_pip <= stage_in_pip;
                    stage_effect_in_border <= stage_in_border;
                    stage_effect_pip_frame_valid <= stage_pip_frame_valid;
                    stage_effect_tlast <= stage_tlast;
                    stage_effect_tuser <= stage_tuser;
                end else begin
                    stage_effect_in_pip <= 1'b0;
                    stage_effect_in_border <= 1'b0;
                    stage_effect_pip_frame_valid <= 1'b0;
                    stage_effect_tlast <= 1'b0;
                    stage_effect_tuser <= 1'b0;
                end

                input_valid <= 1'b0;
                stage_valid <= input_valid;
                if (input_valid) begin
                    stage_main_data <= input_main_data;
                    stage_in_pip <= input_in_pip;
                    stage_in_border <= input_in_border;
                    stage_pip_frame_valid <= input_pip_frame_valid;
                    stage_pip_read_bank <= input_pip_read_bank;
                    stage_tlast <= input_tlast;
                    stage_tuser <= input_tuser;
                end else begin
                    stage_in_pip <= 1'b0;
                    stage_in_border <= 1'b0;
                    stage_pip_frame_valid <= 1'b0;
                    stage_tlast <= 1'b0;
                    stage_tuser <= 1'b0;
                end
            end

            if (main_fire) begin
                input_valid <= 1'b1;
                input_main_data <= s_main_tdata;
                input_tlast <= s_main_tlast;
                input_tuser <= s_main_tuser;
                input_in_pip <= in_pip;
                input_in_border <= in_border;
                input_pip_frame_valid <= pip_frame_valid;
                input_pip_read_bank <= pip_read_bank;
                input_pip_read_addr <= pip_read_addr_ctr[PIP_ADDR_WIDTH-1:0];

                if (s_main_tuser) begin
                    status_main_frames <= status_main_frames + 32'd1;
                    pip_read_addr_ctr <= 32'd0;
                end

                if (s_main_tlast) begin
                    main_x <= 16'd0;
                    main_y <= (main_cur_y == FRAME_H_LAST) ? 16'd0 : main_cur_y + 16'd1;
                end else begin
                    main_x <= main_cur_x + 16'd1;
                    main_y <= main_cur_y;
                end

                if (in_pip) begin
                    if (scale_half) begin
                        pip_read_addr_ctr <= pip_read_addr_ctr + 32'd1;
                    end else if (main_local_x == active_pip_w - 16'd1) begin
                        pip_read_addr_ctr <= pip_read_addr_ctr + PIP_W + 32'd2;
                    end else begin
                        pip_read_addr_ctr <= pip_read_addr_ctr + 32'd2;
                    end
                    status_overlay_pixels <= status_overlay_pixels + 32'd1;
                end
            end

            if (pip_fire) begin
                if (pip_in_tlast) begin
                    pip_x <= 16'd0;
                    pip_y <= (pip_cur_y == FRAME_H_LAST) ? 16'd0 : pip_cur_y + 16'd1;
                end else begin
                    pip_x <= pip_cur_x + 16'd1;
                    pip_y <= pip_cur_y;
                end

                if (pip_in_tlast && (pip_cur_y == FRAME_H_LAST)) begin
                    pip_frame_commit_pending <= 1'b1;
                    status_pip_frames <= status_pip_frames + 32'd1;
                    pip_read_bank <= pip_write_bank;
                    pip_write_bank <= ~pip_write_bank;
                    pip_mod_x <= 16'd0;
                    pip_mod_y <= 16'd0;
                    pip_scaled_x_ctr <= 16'd0;
                    pip_scaled_y_ctr <= 16'd0;
                    pip_write_addr_ctr <= 32'd0;
                    pip_write_row_base <= 32'd0;
                end else if (pip_in_tlast) begin
                    pip_mod_x <= 16'd0;
                    pip_scaled_x_ctr <= 16'd0;
                    if (pip_mod_y_cur == CAPTURE_Y_LAST) begin
                        pip_mod_y <= 16'd0;
                        pip_scaled_y_ctr <= pip_scaled_y_cur + 16'd1;
                        pip_write_row_base <= pip_write_row_base_cur + PIP_W_L;
                        pip_write_addr_ctr <= pip_write_row_base_cur + PIP_W_L;
                    end else begin
                        pip_mod_y <= pip_mod_y_cur + 16'd1;
                        pip_scaled_y_ctr <= pip_scaled_y_cur;
                        pip_write_row_base <= pip_write_row_base_cur;
                        pip_write_addr_ctr <= pip_write_row_base_cur;
                    end
                end else begin
                    pip_mod_y <= pip_mod_y_cur;
                    pip_scaled_y_ctr <= pip_scaled_y_cur;
                    pip_write_row_base <= pip_write_row_base_cur;
                    if (pip_mod_x_cur == CAPTURE_X_LAST) begin
                        pip_mod_x <= 16'd0;
                        pip_scaled_x_ctr <= pip_scaled_x_cur + 16'd1;
                        pip_write_addr_ctr <= pip_write_addr_cur + 32'd1;
                    end else begin
                        pip_mod_x <= pip_mod_x_cur + 16'd1;
                        pip_scaled_x_ctr <= pip_scaled_x_cur;
                        pip_write_addr_ctr <= pip_write_addr_cur;
                    end
                end

            end
        end
    end

endmodule

`default_nettype wire
