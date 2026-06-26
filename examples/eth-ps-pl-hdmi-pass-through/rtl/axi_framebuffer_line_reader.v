`timescale 1ns/1ps
`default_nettype none

module axi_framebuffer_line_reader #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 64,
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480
) (
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  enable,
    input  wire [ADDR_WIDTH-1:0] frame_base_addr,
    input  wire [15:0]           stride_bytes,
    input  wire [10:0]           x,
    input  wire [9:0]            y,
    input  wire                  active,
    output reg  [7:0]            red,
    output reg  [7:0]            green,
    output reg  [7:0]            blue,
    output reg                   pixel_valid,
    output reg                   underflow,
    output reg                   axi_error,

    output wire [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output reg                   m_axi_arvalid,
    input  wire                  m_axi_arready,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready,
    input  wire                  m_axi_rlast
);

    localparam integer PIXEL_BITS = 16;
    localparam integer PIXELS_PER_BEAT = DATA_WIDTH / PIXEL_BITS;
    localparam integer BEAT_BYTES = DATA_WIDTH / 8;
    localparam integer BEATS_PER_LINE = H_ACTIVE / PIXELS_PER_BEAT;
    localparam [ADDR_WIDTH-1:0] BEAT_BYTES_W = BEAT_BYTES;

    initial begin
        if (DATA_WIDTH != 64) begin
            $error("axi_framebuffer_line_reader currently expects DATA_WIDTH=64.");
        end
        if ((H_ACTIVE % PIXELS_PER_BEAT) != 0) begin
            $error("H_ACTIVE must be divisible by DATA_WIDTH/16.");
        end
    end

    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] line0 [0:BEATS_PER_LINE-1];
    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] line1 [0:BEATS_PER_LINE-1];

    reg        buf0_valid;
    reg        buf1_valid;
    reg [9:0]  buf0_line;
    reg [9:0]  buf1_line;

    reg        filling;
    reg        wait_r;
    reg        fill_sel;
    reg [9:0]  fill_line;
    reg [9:0]  fill_beat;

    reg        start_fill;
    reg        start_sel;
    reg [9:0]  start_line;

    wire current_loaded = (buf0_valid && (buf0_line == y)) ||
                          (buf1_valid && (buf1_line == y));
    wire next_in_range = (y < (V_ACTIVE - 1));
    wire [9:0] next_line = y + 10'd1;
    wire next_loaded = (buf0_valid && (buf0_line == next_line)) ||
                       (buf1_valid && (buf1_line == next_line));
    wire line0_loaded = (buf0_valid && (buf0_line == 10'd0)) ||
                        (buf1_valid && (buf1_line == 10'd0));
    wire line1_loaded = (buf0_valid && (buf0_line == 10'd1)) ||
                        (buf1_valid && (buf1_line == 10'd1));

    wire display_uses_buf0 = active && buf0_valid && (buf0_line == y);
    wire display_uses_buf1 = active && buf1_valid && (buf1_line == y);

    wire [ADDR_WIDTH-1:0] line_offset =
        {{(ADDR_WIDTH-10){1'b0}}, fill_line} * {{(ADDR_WIDTH-16){1'b0}}, stride_bytes};
    wire [ADDR_WIDTH-1:0] beat_offset =
        {{(ADDR_WIDTH-10){1'b0}}, fill_beat} * BEAT_BYTES_W;

    assign m_axi_araddr = frame_base_addr + line_offset + beat_offset;
    assign m_axi_arlen = 8'd0;
    assign m_axi_arsize = 3'b011;
    assign m_axi_arburst = 2'b01;
    assign m_axi_rready = filling && wait_r;

    function [7:0] rgb565_to_rgb888_red;
        input [15:0] pixel;
        begin
            rgb565_to_rgb888_red = {pixel[15:11], pixel[15:13]};
        end
    endfunction

    function [7:0] rgb565_to_rgb888_green;
        input [15:0] pixel;
        begin
            rgb565_to_rgb888_green = {pixel[10:5], pixel[10:9]};
        end
    endfunction

    function [7:0] rgb565_to_rgb888_blue;
        input [15:0] pixel;
        begin
            rgb565_to_rgb888_blue = {pixel[4:0], pixel[4:2]};
        end
    endfunction

    reg [15:0] pixel_rgb565;
    reg [DATA_WIDTH-1:0] pixel_word;
    wire [7:0] display_beat = x[10:2];
    wire [1:0] display_pixel = x[1:0];

    always @* begin
        start_fill = 1'b0;
        start_sel = 1'b0;
        start_line = 10'd0;

        if (!filling && enable) begin
            if (active && current_loaded && next_in_range && !next_loaded) begin
                start_fill = 1'b1;
                start_line = next_line;
            end else if (!active && (y >= V_ACTIVE) && !line0_loaded) begin
                start_fill = 1'b1;
                start_line = 10'd0;
            end else if (!active && (y >= V_ACTIVE) && !line1_loaded) begin
                start_fill = 1'b1;
                start_line = 10'd1;
            end

            if (start_fill) begin
                if (active && display_uses_buf0) begin
                    start_sel = 1'b1;
                end else if (active && display_uses_buf1) begin
                    start_sel = 1'b0;
                end else if (!active && (start_line == 10'd1) && buf0_valid && (buf0_line == 10'd0)) begin
                    start_sel = 1'b1;
                end else if (!active && (start_line == 10'd1) && buf1_valid && (buf1_line == 10'd0)) begin
                    start_sel = 1'b0;
                end else if (!active && (start_line == 10'd0) && buf0_valid && (buf0_line == 10'd1)) begin
                    start_sel = 1'b1;
                end else if (!active && (start_line == 10'd0) && buf1_valid && (buf1_line == 10'd1)) begin
                    start_sel = 1'b0;
                end else if (!buf0_valid) begin
                    start_sel = 1'b0;
                end else begin
                    start_sel = 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            underflow <= 1'b0;
            axi_error <= 1'b0;
            buf0_valid <= 1'b0;
            buf1_valid <= 1'b0;
            buf0_line <= 10'd0;
            buf1_line <= 10'd0;
            filling <= 1'b0;
            wait_r <= 1'b0;
            fill_sel <= 1'b0;
            fill_line <= 10'd0;
            fill_beat <= 10'd0;
            m_axi_arvalid <= 1'b0;
        end else begin
            if (active && enable && !current_loaded) begin
                underflow <= 1'b1;
            end

            if (start_fill) begin
                filling <= 1'b1;
                wait_r <= 1'b0;
                fill_sel <= start_sel;
                fill_line <= start_line;
                fill_beat <= 10'd0;
                m_axi_arvalid <= 1'b1;
                if (start_sel) begin
                    buf1_valid <= 1'b0;
                end else begin
                    buf0_valid <= 1'b0;
                end
            end else if (filling) begin
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    wait_r <= 1'b1;
                end

                if (wait_r && m_axi_rvalid) begin
                    if (m_axi_rresp != 2'b00 || !m_axi_rlast) begin
                        axi_error <= 1'b1;
                    end

                    if (fill_sel) begin
                        line1[fill_beat[7:0]] <= m_axi_rdata;
                    end else begin
                        line0[fill_beat[7:0]] <= m_axi_rdata;
                    end

                    wait_r <= 1'b0;
                    if (fill_beat == BEATS_PER_LINE - 1) begin
                        filling <= 1'b0;
                        if (fill_sel) begin
                            buf1_valid <= 1'b1;
                            buf1_line <= fill_line;
                        end else begin
                            buf0_valid <= 1'b1;
                            buf0_line <= fill_line;
                        end
                    end else begin
                        fill_beat <= fill_beat + 10'd1;
                        m_axi_arvalid <= 1'b1;
                    end
                end
            end
        end
    end

    always @* begin
        red = 8'd0;
        green = 8'd0;
        blue = 8'd0;
        pixel_valid = 1'b0;
        pixel_rgb565 = 16'd0;
        pixel_word = {DATA_WIDTH{1'b0}};

        if (active && enable && (x < H_ACTIVE)) begin
            if (buf0_valid && (buf0_line == y)) begin
                pixel_word = line0[display_beat];
                pixel_rgb565 = pixel_word[(display_pixel * PIXEL_BITS) +: PIXEL_BITS];
                red = rgb565_to_rgb888_red(pixel_rgb565);
                green = rgb565_to_rgb888_green(pixel_rgb565);
                blue = rgb565_to_rgb888_blue(pixel_rgb565);
                pixel_valid = 1'b1;
            end else if (buf1_valid && (buf1_line == y)) begin
                pixel_word = line1[display_beat];
                pixel_rgb565 = pixel_word[(display_pixel * PIXEL_BITS) +: PIXEL_BITS];
                red = rgb565_to_rgb888_red(pixel_rgb565);
                green = rgb565_to_rgb888_green(pixel_rgb565);
                blue = rgb565_to_rgb888_blue(pixel_rgb565);
                pixel_valid = 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
