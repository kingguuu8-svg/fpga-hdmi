`timescale 1ns/1ps
`default_nettype none

module jpeg_rgb_tile_writer (
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
    output reg          s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [5:0]   s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output reg  [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output reg          s_axi_rvalid,
    input  wire         s_axi_rready,

    input  wire         pixel_valid,
    output wire         pixel_ready,
    input  wire [15:0]  pixel_x,
    input  wire [15:0]  pixel_y,
    input  wire [15:0]  pixel_width,
    input  wire [15:0]  pixel_height,
    input  wire [7:0]   pixel_r,
    input  wire [7:0]   pixel_g,
    input  wire [7:0]   pixel_b,
    input  wire         decoder_idle,
    input  wire [31:0]  input_bytes,

    output wire [71:0]  m_axis_cmd_tdata,
    output wire         m_axis_cmd_tvalid,
    input  wire         m_axis_cmd_tready,
    output reg  [31:0]  m_axis_data_tdata,
    output wire [3:0]   m_axis_data_tkeep,
    output wire         m_axis_data_tlast,
    output wire         m_axis_data_tvalid,
    input  wire         m_axis_data_tready,
    input  wire [7:0]   s_axis_sts_tdata,
    input  wire         s_axis_sts_tvalid,
    output wire         s_axis_sts_tready,

    output wire         input_sink_mode,
    output reg          decode_start
);
    localparam integer BLOCK_SIZE = 16;
    localparam integer BLOCK_PIXELS = BLOCK_SIZE * BLOCK_SIZE;
    localparam [22:0] BLOCK_ROW_BYTES = 23'd48;
    localparam [5:0] REG_CONTROL = 6'h00;
    localparam [5:0] REG_DST_BASE = 6'h04;
    localparam [5:0] REG_STRIDE = 6'h08;
    localparam [5:0] REG_DIMENSIONS = 6'h0c;
    localparam [5:0] REG_EXPECTED_PIXELS = 6'h10;
    localparam [5:0] REG_STATUS = 6'h14;
    localparam [5:0] REG_PIXELS = 6'h18;
    localparam [5:0] REG_CYCLES = 6'h1c;
    localparam [5:0] REG_COMMANDS = 6'h20;
    localparam [5:0] REG_RESPONSES = 6'h24;
    localparam [5:0] REG_OUTPUT_BYTES = 6'h28;
    localparam [5:0] REG_STALL_CYCLES = 6'h2c;
    localparam [5:0] REG_ERROR_FLAGS = 6'h30;
    localparam [5:0] REG_INPUT_BYTES = 6'h34;
    localparam [5:0] REG_LAST_ADDRESS = 6'h38;
    localparam [5:0] REG_VERSION = 6'h3c;
    localparam [31:0] VERSION = 32'h4a504c31;

    localparam [1:0] SEND_IDLE = 2'd0;
    localparam [1:0] SEND_COMMAND = 2'd1;
    localparam [1:0] SEND_DATA = 2'd2;

    reg [31:0] cfg_dst_base;
    reg [31:0] cfg_stride;
    reg [15:0] cfg_width;
    reg [15:0] cfg_height;
    reg [31:0] cfg_expected_pixels;

    reg        busy;
    reg        done;
    reg        cfg_count_only;
    reg        cfg_input_sink;
    reg [31:0] status_pixels;
    reg [31:0] status_cycles;
    reg [31:0] status_commands;
    reg [31:0] status_responses;
    reg [31:0] status_output_bytes;
    reg [31:0] status_stall_cycles;
    reg [31:0] status_error_flags;
    reg [31:0] status_last_address;

    reg [23:0] block_buffer [0:(2*BLOCK_PIXELS)-1];
    reg [11:0] block_x [0:1];
    reg [11:0] block_y [0:1];
    reg [1:0]  block_active;
    reg [1:0]  block_full;
    reg        capture_bank;
    reg        flush_bank;
    reg [3:0]  flush_line;
    reg [3:0]  send_word;
    reg [1:0]  send_state;
    reg [3:0]  command_tag;

    reg [5:0]  axi_awaddr_latched;
    reg [31:0] axi_wdata_latched;
    reg [3:0]  axi_wstrb_latched;
    reg        axi_aw_pending;
    reg        axi_w_pending;

    wire axi_aw_take = s_axi_awvalid && s_axi_awready;
    wire axi_w_take = s_axi_wvalid && s_axi_wready;
    wire axi_write_fire =
        !s_axi_bvalid && (axi_aw_pending || axi_aw_take) &&
        (axi_w_pending || axi_w_take);
    wire [5:0] axi_write_addr =
        axi_aw_pending ? axi_awaddr_latched : s_axi_awaddr;
    wire [31:0] axi_write_data =
        axi_w_pending ? axi_wdata_latched : s_axi_wdata;
    wire [3:0] axi_write_strb =
        axi_w_pending ? axi_wstrb_latched : s_axi_wstrb;
    wire axi_start_fire =
        axi_write_fire && axi_write_addr == REG_CONTROL &&
        axi_write_strb[0] && axi_write_data[0];
    wire axi_read_fire = s_axi_arvalid && s_axi_arready;
    wire pixel_fire = pixel_valid && pixel_ready;
    wire cmd_fire = m_axis_cmd_tvalid && m_axis_cmd_tready;
    wire data_fire = m_axis_data_tvalid && m_axis_data_tready;
    wire sts_fire = s_axis_sts_tvalid && s_axis_sts_tready;
    wire [11:0] pixel_block_x = pixel_x[15:4];
    wire [11:0] pixel_block_y = pixel_y[15:4];
    wire [7:0] pixel_block_index = {pixel_y[3:0], pixel_x[3:0]};
    wire capture_same_block = block_active[capture_bank] &&
        pixel_block_x == block_x[capture_bank] &&
        pixel_block_y == block_y[capture_bank];
    wire other_bank_available =
        !block_active[~capture_bank] && !block_full[~capture_bank];
    wire [31:0] block_base_x = {16'd0, block_x[flush_bank], 4'd0};
    wire [31:0] block_base_y = {16'd0, block_y[flush_bank], 4'd0};
    wire [31:0] flush_y = block_base_y + {28'd0, flush_line};
    wire [31:0] flush_address =
        cfg_dst_base + (flush_y * cfg_stride) + (block_base_x * 32'd3);
    wire line_last_word = send_word == 4'd11;

    function [7:0] block_byte;
        input bank;
        input [3:0] line;
        input [5:0] byte_offset;
        reg [7:0] pixel_index;
        reg [23:0] pixel_value;
        begin
            pixel_index = {line, 4'd0} + (byte_offset / 3);
            pixel_value = block_buffer[{bank, pixel_index}];
            case (byte_offset % 3)
                0: block_byte = pixel_value[23:16];
                1: block_byte = pixel_value[15:8];
                default: block_byte = pixel_value[7:0];
            endcase
        end
    endfunction

    function [31:0] block_word;
        input bank;
        input [3:0] line;
        input [3:0] word;
        reg [5:0] byte_offset;
        begin
            byte_offset = {word, 2'b00};
            block_word = {
                block_byte(bank, line, byte_offset + 6'd3),
                block_byte(bank, line, byte_offset + 6'd2),
                block_byte(bank, line, byte_offset + 6'd1),
                block_byte(bank, line, byte_offset)
            };
        end
    endfunction

    assign pixel_ready =
        busy && status_error_flags == 0 &&
        (cfg_count_only || !block_active[capture_bank] ||
         (capture_same_block && !block_full[capture_bank]) ||
         (!capture_same_block && other_bank_available));
    assign m_axis_cmd_tvalid = send_state == SEND_COMMAND;
    // DataMover Full command: RSVD, TAG, SADDR, DRR, EOF, DSA, TYPE, BTT.
    assign m_axis_cmd_tdata =
        {4'b0000, command_tag, flush_address, 1'b0, 1'b1,
         6'b000000, 1'b1, BLOCK_ROW_BYTES};
    assign m_axis_data_tvalid = send_state == SEND_DATA;
    assign m_axis_data_tkeep = 4'hf;
    assign m_axis_data_tlast = send_state == SEND_DATA && line_last_word;
    assign s_axis_sts_tready = 1'b1;
    assign s_axi_awready = aresetn && !s_axi_bvalid && !axi_aw_pending;
    assign s_axi_wready = aresetn && !s_axi_bvalid && !axi_w_pending;
    assign s_axi_arready = aresetn && !s_axi_rvalid;
    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;
    assign input_sink_mode = cfg_input_sink;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rvalid <= 1'b0;
            axi_awaddr_latched <= 6'd0;
            axi_wdata_latched <= 32'd0;
            axi_wstrb_latched <= 4'd0;
            axi_aw_pending <= 1'b0;
            axi_w_pending <= 1'b0;
            decode_start <= 1'b0;
            cfg_dst_base <= 32'd0;
            cfg_stride <= 32'd0;
            cfg_width <= 16'd0;
            cfg_height <= 16'd0;
            cfg_expected_pixels <= 32'd0;
            cfg_count_only <= 1'b0;
            cfg_input_sink <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            status_pixels <= 32'd0;
            status_cycles <= 32'd0;
            status_commands <= 32'd0;
            status_responses <= 32'd0;
            status_output_bytes <= 32'd0;
            status_stall_cycles <= 32'd0;
            status_error_flags <= 32'd0;
            status_last_address <= 32'd0;
            block_x[0] <= 12'd0;
            block_x[1] <= 12'd0;
            block_y[0] <= 12'd0;
            block_y[1] <= 12'd0;
            block_active <= 2'b00;
            block_full <= 2'b00;
            capture_bank <= 1'b0;
            flush_bank <= 1'b0;
            flush_line <= 4'd0;
            send_word <= 4'd0;
            send_state <= SEND_IDLE;
            command_tag <= 4'd0;
            m_axis_data_tdata <= 32'd0;
        end else begin
            decode_start <= 1'b0;

            if (axi_aw_take) begin
                axi_awaddr_latched <= s_axi_awaddr;
                axi_aw_pending <= 1'b1;
            end
            if (axi_w_take) begin
                axi_wdata_latched <= s_axi_wdata;
                axi_wstrb_latched <= s_axi_wstrb;
                axi_w_pending <= 1'b1;
            end

            if (axi_write_fire) begin
                s_axi_bvalid <= 1'b1;
                axi_aw_pending <= 1'b0;
                axi_w_pending <= 1'b0;
                case (axi_write_addr)
                    REG_CONTROL: begin
                        if (axi_start_fire) begin
                            decode_start <= 1'b1;
                            busy <= 1'b1;
                            done <= 1'b0;
                            cfg_count_only <= axi_write_data[1];
                            cfg_input_sink <= axi_write_data[2];
                            status_pixels <= 32'd0;
                            status_cycles <= 32'd0;
                            status_commands <= 32'd0;
                            status_responses <= 32'd0;
                            status_output_bytes <= 32'd0;
                            status_stall_cycles <= 32'd0;
                            status_error_flags <= 32'd0;
                            status_last_address <= cfg_dst_base;
                            block_x[0] <= 12'd0;
                            block_x[1] <= 12'd0;
                            block_y[0] <= 12'd0;
                            block_y[1] <= 12'd0;
                            block_active <= 2'b00;
                            block_full <= 2'b00;
                            capture_bank <= 1'b0;
                            flush_bank <= 1'b0;
                            flush_line <= 4'd0;
                            send_word <= 4'd0;
                            send_state <= SEND_IDLE;
                            command_tag <= 4'd0;
                        end
                    end
                    REG_DST_BASE: cfg_dst_base <= axi_write_data;
                    REG_STRIDE: cfg_stride <= axi_write_data;
                    REG_DIMENSIONS: begin
                        cfg_width <= axi_write_data[15:0];
                        cfg_height <= axi_write_data[31:16];
                    end
                    REG_EXPECTED_PIXELS: cfg_expected_pixels <= axi_write_data;
                    default: begin
                    end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (axi_read_fire) begin
                s_axi_rvalid <= 1'b1;
                case (s_axi_araddr)
                    REG_CONTROL: s_axi_rdata <=
                        {28'd0, done, cfg_input_sink, cfg_count_only, busy};
                    REG_DST_BASE: s_axi_rdata <= cfg_dst_base;
                    REG_STRIDE: s_axi_rdata <= cfg_stride;
                    REG_DIMENSIONS: s_axi_rdata <= {cfg_height, cfg_width};
                    REG_EXPECTED_PIXELS: s_axi_rdata <= cfg_expected_pixels;
                    REG_STATUS: s_axi_rdata <= {29'd0, |status_error_flags, done, busy};
                    REG_PIXELS: s_axi_rdata <= status_pixels;
                    REG_CYCLES: s_axi_rdata <= status_cycles;
                    REG_COMMANDS: s_axi_rdata <= status_commands;
                    REG_RESPONSES: s_axi_rdata <= status_responses;
                    REG_OUTPUT_BYTES: s_axi_rdata <= status_output_bytes;
                    REG_STALL_CYCLES: s_axi_rdata <= status_stall_cycles;
                    REG_ERROR_FLAGS: s_axi_rdata <= status_error_flags;
                    REG_INPUT_BYTES: s_axi_rdata <= input_bytes;
                    REG_LAST_ADDRESS: s_axi_rdata <= status_last_address;
                    REG_VERSION: s_axi_rdata <= VERSION;
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            if (busy && !axi_start_fire) begin
                status_cycles <= status_cycles + 32'd1;
                if ((pixel_valid && !pixel_ready) ||
                    (m_axis_cmd_tvalid && !m_axis_cmd_tready) ||
                    (m_axis_data_tvalid && !m_axis_data_tready))
                    status_stall_cycles <= status_stall_cycles + 32'd1;
            end

            if (pixel_fire) begin
                status_pixels <= status_pixels + 32'd1;
                if (pixel_width != cfg_width || pixel_height != cfg_height)
                    status_error_flags[0] <= 1'b1;
                if (pixel_x >= cfg_width || pixel_y >= cfg_height)
                    status_error_flags[1] <= 1'b1;

                if (!cfg_count_only) begin
                    // DDR byte order is B, G, R so the mmap buffer matches GstVideoFormat BGR.
                    if (!block_active[capture_bank]) begin
                        block_x[capture_bank] <= pixel_block_x;
                        block_y[capture_bank] <= pixel_block_y;
                        block_active[capture_bank] <= 1'b1;
                        block_buffer[{capture_bank, pixel_block_index}] <=
                            {pixel_b, pixel_g, pixel_r};
                    end else if (capture_same_block) begin
                        block_buffer[{capture_bank, pixel_block_index}] <=
                            {pixel_b, pixel_g, pixel_r};
                    end else begin
                        block_full[capture_bank] <= 1'b1;
                        capture_bank <= ~capture_bank;
                        block_x[~capture_bank] <= pixel_block_x;
                        block_y[~capture_bank] <= pixel_block_y;
                        block_active[~capture_bank] <= 1'b1;
                        block_buffer[{~capture_bank, pixel_block_index}] <=
                            {pixel_b, pixel_g, pixel_r};
                    end
                end
            end

            if (!cfg_count_only && busy && decoder_idle &&
                block_active[capture_bank] && !block_full[capture_bank]) begin
                block_full[capture_bank] <= 1'b1;
            end

            case (send_state)
                SEND_IDLE: begin
                    if (block_full[0]) begin
                        flush_bank <= 1'b0;
                        flush_line <= 4'd0;
                        send_state <= SEND_COMMAND;
                    end else if (block_full[1]) begin
                        flush_bank <= 1'b1;
                        flush_line <= 4'd0;
                        send_state <= SEND_COMMAND;
                    end
                end
                SEND_COMMAND: begin
                    if (cmd_fire) begin
                        status_commands <= status_commands + 32'd1;
                        status_last_address <= flush_address;
                        send_word <= 4'd0;
                        m_axis_data_tdata <= block_word(flush_bank, flush_line, 4'd0);
                        send_state <= SEND_DATA;
                    end
                end
                default: begin
                    if (data_fire) begin
                        status_output_bytes <= status_output_bytes + 32'd4;
                        if (line_last_word) begin
                            if (flush_line == 4'd15) begin
                                block_active[flush_bank] <= 1'b0;
                                block_full[flush_bank] <= 1'b0;
                                flush_line <= 4'd0;
                                send_state <= SEND_IDLE;
                            end else begin
                                flush_line <= flush_line + 4'd1;
                                send_state <= SEND_COMMAND;
                            end
                        end else begin
                            send_word <= send_word + 4'd1;
                            m_axis_data_tdata <=
                                block_word(flush_bank, flush_line, send_word + 4'd1);
                        end
                    end
                end
            endcase

            if (sts_fire) begin
                status_responses <= status_responses + 32'd1;
                if (!s_axis_sts_tdata[7] || s_axis_sts_tdata[6:4] != 3'b000)
                    status_error_flags[2] <= 1'b1;
            end

            if (!axi_start_fire) begin
                if (busy && status_error_flags != 0) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else if (busy && decoder_idle &&
                             status_pixels == cfg_expected_pixels &&
                             (cfg_count_only ||
                              (block_full == 2'b00 &&
                               block_active == 2'b00 &&
                               send_state == SEND_IDLE &&
                               status_responses == status_commands &&
                               status_commands != 0))) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
