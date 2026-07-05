`timescale 1ns / 1ps

module tb_jpeg_core_720p;
    localparam integer WIDTH = 1280;
    localparam integer HEIGHT = 720;
    localparam integer PIXELS = WIDTH * HEIGHT;
    localparam integer MAX_WORDS = 65536;
    localparam integer MAX_CYCLES = 4000000;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg in_valid = 1'b0;
    reg [31:0] in_data = 32'b0;
    reg [3:0] in_strb = 4'b0;
    reg in_last = 1'b0;
    wire in_accept;
    wire out_valid;
    wire [15:0] out_width;
    wire [15:0] out_height;
    wire [15:0] out_x;
    wire [15:0] out_y;
    wire [7:0] out_r;
    wire [7:0] out_g;
    wire [7:0] out_b;
    wire idle;

    reg [36:0] jpeg_words [0:MAX_WORDS-1];
    reg [23:0] frame [0:PIXELS-1];
    reg seen [0:PIXELS-1];
    integer word_count;
    integer word_index;
    integer pixel_count;
    integer duplicate_count;
    integer cycle_count;
    integer address;
    integer index;

    always #5 clk = ~clk;

    jpeg_core #(
        .SUPPORT_WRITABLE_DHT(0)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .inport_valid_i(in_valid),
        .inport_data_i(in_data),
        .inport_strb_i(in_strb),
        .inport_last_i(in_last),
        .outport_accept_i(1'b1),
        .inport_accept_o(in_accept),
        .outport_valid_o(out_valid),
        .outport_width_o(out_width),
        .outport_height_o(out_height),
        .outport_pixel_x_o(out_x),
        .outport_pixel_y_o(out_y),
        .outport_pixel_r_o(out_r),
        .outport_pixel_g_o(out_g),
        .outport_pixel_b_o(out_b),
        .idle_o(idle)
    );

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;
            if (out_valid) begin
                if (out_width != WIDTH || out_height != HEIGHT ||
                    out_x >= WIDTH || out_y >= HEIGHT) begin
                    $display("JPEG_PL_RTL_SIM_FAILED reason=output_bounds width=%0d height=%0d x=%0d y=%0d",
                             out_width, out_height, out_x, out_y);
                    $finish;
                end
                address = out_y * WIDTH + out_x;
                if (seen[address])
                    duplicate_count <= duplicate_count + 1;
                else begin
                    seen[address] <= 1'b1;
                    pixel_count <= pixel_count + 1;
                end
                frame[address] <= {out_r, out_g, out_b};
            end

            if (cycle_count >= MAX_CYCLES) begin
                $display("JPEG_PL_RTL_SIM_FAILED reason=timeout cycles=%0d pixels=%0d", cycle_count, pixel_count);
                $finish;
            end

            if (word_index == word_count && pixel_count == PIXELS && idle) begin
                if (duplicate_count != 0) begin
                    $display("JPEG_PL_RTL_SIM_FAILED reason=duplicates count=%0d", duplicate_count);
                    $finish;
                end
                $writememh("rtl_pixels.hex", frame);
                $display("JPEG_PL_RTL_SIM_OK width=%0d height=%0d pixels=%0d cycles=%0d duplicates=%0d",
                         WIDTH, HEIGHT, pixel_count, cycle_count, duplicate_count);
                $finish;
            end
        end
    end

    initial begin
        word_count = 0;
        word_index = 0;
        pixel_count = 0;
        duplicate_count = 0;
        cycle_count = 0;
        for (index = 0; index < PIXELS; index = index + 1) begin
            frame[index] = 24'b0;
            seen[index] = 1'b0;
        end
        if (!$value$plusargs("WORD_COUNT=%d", word_count)) begin
            $display("JPEG_PL_RTL_SIM_FAILED reason=missing_word_count");
            $finish;
        end
        $readmemh("jpeg_words.mem", jpeg_words);
        repeat (10) @(posedge clk);
        rst <= 1'b0;

        while (word_index < word_count) begin
            @(posedge clk);
            if (!in_valid || in_accept) begin
                in_data <= jpeg_words[word_index][31:0];
                in_strb <= jpeg_words[word_index][35:32];
                // Match the upstream AXI wrapper: EOI terminates JPEG data.
                // The core's inport_last_i is byte-level, not AXI word TLAST.
                in_last <= 1'b0;
                in_valid <= 1'b1;
                word_index = word_index + 1;
            end
        end
        @(posedge clk);
        while (!in_accept)
            @(posedge clk);
        in_valid <= 1'b0;
        in_last <= 1'b0;
        in_strb <= 4'b0;
    end
endmodule
