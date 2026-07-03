`timescale 1ns/1ps
`default_nettype none

module axis_pip_overlay_core #(
    parameter integer FRAME_W = 800,
    parameter integer FRAME_H = 600,
    parameter integer PIP_X = 560,
    parameter integer PIP_Y = 420,
    parameter integer PIP_W = 200,
    parameter integer PIP_H = 150,
    parameter integer SCALE_X = 4,
    parameter integer SCALE_Y = 4,
    parameter integer BORDER = 2
) (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_MAIN:S_PIP:M_AXIS, ASSOCIATED_RESET aresetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    input  wire        aclk,
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    input  wire        aresetn,

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
    localparam [15:0] FRAME_W_L = FRAME_W;
    localparam [15:0] FRAME_H_LAST = FRAME_H - 1;
    localparam [15:0] PIP_X_L = PIP_X;
    localparam [15:0] PIP_Y_L = PIP_Y;
    localparam [15:0] PIP_X_END = PIP_X + PIP_W;
    localparam [15:0] PIP_Y_END = PIP_Y + PIP_H;
    localparam [15:0] PIP_W_L = PIP_W;
    localparam [15:0] PIP_H_L = PIP_H;
    localparam [15:0] BORDER_L = BORDER;
    localparam [15:0] SCALE_X_LAST = SCALE_X - 1;
    localparam [15:0] SCALE_Y_LAST = SCALE_Y - 1;
    localparam [15:0] PIP_X_BORDER_END = PIP_X + BORDER;
    localparam [15:0] PIP_Y_BORDER_END = PIP_Y + BORDER;
    localparam [15:0] PIP_W_BORDER_L = PIP_W - BORDER;
    localparam [15:0] PIP_H_BORDER_L = PIP_H - BORDER;
    localparam [15:0] PIP_X_BORDER_START = PIP_X + PIP_W - BORDER;
    localparam [15:0] PIP_Y_BORDER_START = PIP_Y + PIP_H - BORDER;

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

    (* ram_style = "block" *) reg [23:0] pip_mem [0:PIP_PIXELS-1];

    reg [23:0] pip_read_data_r;
    reg        stage_valid;
    reg [23:0] stage_main_data;
    reg        stage_tlast;
    reg        stage_tuser;
    reg        stage_in_pip;
    reg        stage_in_border;
    reg        stage_pip_frame_valid;
    reg [23:0] m_axis_tdata_r;
    reg        m_axis_tvalid_r;
    reg        m_axis_tlast_r;
    reg        m_axis_tuser_r;

    wire main_fire = s_main_tvalid && s_main_tready;
    wire pip_fire = s_pip_tvalid && s_pip_tready;
    wire output_ready = !m_axis_tvalid_r || m_axis_tready;

    wire [15:0] main_cur_x = s_main_tuser ? 16'd0 : main_x;
    wire [15:0] main_cur_y = s_main_tuser ? 16'd0 : main_y;
    wire [15:0] pip_cur_x = s_pip_tuser ? 16'd0 : pip_x;
    wire [15:0] pip_cur_y = s_pip_tuser ? 16'd0 : pip_y;

    wire in_pip_x = (main_cur_x >= PIP_X_L) && (main_cur_x < PIP_X_END);
    wire in_pip_y = (main_cur_y >= PIP_Y_L) && (main_cur_y < PIP_Y_END);
    wire in_pip = in_pip_x && in_pip_y;
    wire in_border = in_pip &&
        ((main_cur_x < PIP_X_BORDER_END) ||
         (main_cur_y < PIP_Y_BORDER_END) ||
         (main_cur_x >= PIP_X_BORDER_START) ||
         (main_cur_y >= PIP_Y_BORDER_START));
    wire [23:0] stage_overlay_data = stage_in_border ? 24'hffffff :
                                      (stage_in_pip && stage_pip_frame_valid) ? pip_read_data_r :
                                      stage_main_data;

    wire pip_start = s_pip_tuser;
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

    assign s_main_tready = output_ready;
    assign s_pip_tready = 1'b1;
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
            pip_read_data_r <= 24'd0;
            stage_valid <= 1'b0;
            stage_main_data <= 24'd0;
            stage_tlast <= 1'b0;
            stage_tuser <= 1'b0;
            stage_in_pip <= 1'b0;
            stage_in_border <= 1'b0;
            stage_pip_frame_valid <= 1'b0;
            m_axis_tdata_r <= 24'd0;
            m_axis_tvalid_r <= 1'b0;
            m_axis_tlast_r <= 1'b0;
            m_axis_tuser_r <= 1'b0;
            status_main_frames <= 32'd0;
            status_pip_frames <= 32'd0;
            status_overlay_pixels <= 32'd0;
        end else begin
            if (output_ready) begin
                if (stage_valid) begin
                    m_axis_tvalid_r <= 1'b1;
                    m_axis_tdata_r <= stage_overlay_data;
                    m_axis_tlast_r <= stage_tlast;
                    m_axis_tuser_r <= stage_tuser;
                    stage_valid <= 1'b0;
                end else begin
                    m_axis_tvalid_r <= 1'b0;
                    m_axis_tlast_r <= 1'b0;
                    m_axis_tuser_r <= 1'b0;
                end
            end

            if (main_fire) begin
                pip_read_data_r <= pip_mem[pip_read_addr_ctr];
                stage_valid <= 1'b1;
                stage_main_data <= s_main_tdata;
                stage_tlast <= s_main_tlast;
                stage_tuser <= s_main_tuser;
                stage_in_pip <= in_pip;
                stage_in_border <= in_border;
                stage_pip_frame_valid <= pip_frame_valid;

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
                    pip_read_addr_ctr <= pip_read_addr_ctr + 32'd1;
                    status_overlay_pixels <= status_overlay_pixels + 32'd1;
                end
            end

            if (pip_fire) begin
                if (s_pip_tlast) begin
                    pip_x <= 16'd0;
                    pip_y <= (pip_cur_y == FRAME_H_LAST) ? 16'd0 : pip_cur_y + 16'd1;
                end else begin
                    pip_x <= pip_cur_x + 16'd1;
                    pip_y <= pip_cur_y;
                end

                if (pip_sample_in_window) begin
                    pip_mem[pip_write_addr_cur] <= s_pip_tdata;
                end

                if (s_pip_tlast && (pip_cur_y == FRAME_H_LAST)) begin
                    pip_frame_valid <= 1'b1;
                    status_pip_frames <= status_pip_frames + 32'd1;
                    pip_mod_x <= 16'd0;
                    pip_mod_y <= 16'd0;
                    pip_scaled_x_ctr <= 16'd0;
                    pip_scaled_y_ctr <= 16'd0;
                    pip_write_addr_ctr <= 32'd0;
                    pip_write_row_base <= 32'd0;
                end else if (s_pip_tlast) begin
                    pip_mod_x <= 16'd0;
                    pip_scaled_x_ctr <= 16'd0;
                    if (pip_mod_y_cur == SCALE_Y_LAST) begin
                        pip_mod_y <= 16'd0;
                        pip_scaled_y_ctr <= pip_scaled_y_cur + 16'd1;
                        pip_write_row_base <= pip_write_row_base_cur + PIP_W;
                        pip_write_addr_ctr <= pip_write_row_base_cur + PIP_W;
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
                    if (pip_mod_x_cur == SCALE_X_LAST) begin
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
