`timescale 1ns/1ps
`default_nettype none

module tb_axi_framebuffer_line_reader;
    localparam integer H_ACTIVE = 16;
    localparam integer V_ACTIVE = 4;
    localparam integer H_TOTAL = 20;
    localparam integer V_TOTAL = 12;
    localparam [31:0] BASE_ADDR = 32'h1000_0000;
    localparam integer STRIDE_BYTES = H_ACTIVE * 2;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b1;
    reg [10:0] x = 11'd0;
    reg [9:0] y = 10'd0;
    wire active = (x < H_ACTIVE) && (y < V_ACTIVE);

    wire [7:0] red;
    wire [7:0] green;
    wire [7:0] blue;
    wire pixel_valid;
    wire underflow;
    wire axi_error;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid;
    wire arready;
    reg [63:0] rdata = 64'd0;
    reg [1:0] rresp = 2'b00;
    reg rvalid = 1'b0;
    wire rready;
    reg rlast = 1'b0;

    integer frame_count = 0;
    integer checked_pixels = 0;
    integer failures = 0;
    integer debug_dumped = 0;

    always #5 clk = ~clk;

    assign arready = 1'b1;

    axi_framebuffer_line_reader #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(64),
        .H_ACTIVE(H_ACTIVE),
        .V_ACTIVE(V_ACTIVE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .frame_base_addr(BASE_ADDR),
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
        .m_axi_araddr(araddr),
        .m_axi_arlen(arlen),
        .m_axi_arsize(arsize),
        .m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid),
        .m_axi_arready(arready),
        .m_axi_rdata(rdata),
        .m_axi_rresp(rresp),
        .m_axi_rvalid(rvalid),
        .m_axi_rready(rready),
        .m_axi_rlast(rlast)
    );

    function [15:0] pixel_for_index;
        input integer pixel_index;
        integer px;
        integer py;
        integer sum;
        begin
            px = pixel_index % H_ACTIVE;
            py = pixel_index / H_ACTIVE;
            sum = px + py;
            pixel_for_index = {py[4:0], px[5:0], sum[4:0]};
        end
    endfunction

    function [7:0] exp_red;
        input [15:0] pixel;
        begin
            exp_red = {pixel[15:11], pixel[15:13]};
        end
    endfunction

    function [7:0] exp_green;
        input [15:0] pixel;
        begin
            exp_green = {pixel[10:5], pixel[10:9]};
        end
    endfunction

    function [7:0] exp_blue;
        input [15:0] pixel;
        begin
            exp_blue = {pixel[4:0], pixel[4:2]};
        end
    endfunction

    task drive_axi_read_data;
        input [31:0] addr;
        integer first_pixel;
        integer lane;
        begin
            first_pixel = (addr - BASE_ADDR) / 2;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                rdata[(lane * 16) +: 16] = pixel_for_index(first_pixel + lane);
            end
            rresp = 2'b00;
            rvalid = 1'b1;
            rlast = 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            x <= 11'd0;
            y <= 10'd0;
            frame_count <= 0;
        end else if (x == H_TOTAL - 1) begin
            x <= 11'd0;
            if (y == V_TOTAL - 1) begin
                y <= 10'd0;
                frame_count <= frame_count + 1;
            end else begin
                y <= y + 10'd1;
            end
        end else begin
            x <= x + 11'd1;
        end
    end

    always @(negedge clk) begin
        if (reset) begin
            rvalid <= 1'b0;
            rlast <= 1'b0;
        end else if (rvalid && rready) begin
            rvalid <= 1'b0;
            rlast <= 1'b0;
        end else if (!rvalid && dut.wait_r) begin
            drive_axi_read_data(araddr);
        end

        if (!reset && arvalid && arready) begin
                if (arlen != 8'd0 || arsize != 3'b011 || arburst != 2'b01) begin
                    $display("FAIL invalid AXI read attributes");
                    failures <= failures + 1;
                end
        end
    end

    always @(posedge clk) begin
        if (!reset && frame_count >= 2 && active) begin
            if (!pixel_valid) begin
                $display("FAIL missing pixel frame=%0d x=%0d y=%0d", frame_count, x, y);
                if (!debug_dumped) begin
                    $display("DBG state b0v=%0d b0line=%0d b1v=%0d b1line=%0d filling=%0d wait_r=%0d arvalid=%0d arready=%0d rvalid=%0d rready=%0d",
                             dut.buf0_valid, dut.buf0_line, dut.buf1_valid, dut.buf1_line,
                             dut.filling, dut.wait_r, arvalid, arready, rvalid, rready);
                    debug_dumped <= 1;
                end
                failures <= failures + 1;
            end else if ({red, green, blue} !== {
                    exp_red(pixel_for_index((y * H_ACTIVE) + x)),
                    exp_green(pixel_for_index((y * H_ACTIVE) + x)),
                    exp_blue(pixel_for_index((y * H_ACTIVE) + x))}) begin
                $display("FAIL pixel mismatch frame=%0d x=%0d y=%0d got=%02x%02x%02x",
                         frame_count, x, y, red, green, blue);
                if (!debug_dumped) begin
                    $display("DBG tags b0v=%0d b0line=%0d b1v=%0d b1line=%0d",
                             dut.buf0_valid, dut.buf0_line, dut.buf1_valid, dut.buf1_line);
                    $display("DBG line0[0]=%016x line0[1]=%016x line1[0]=%016x line1[1]=%016x",
                             dut.line0[0], dut.line0[1], dut.line1[0], dut.line1[1]);
                    debug_dumped <= 1;
                end
                failures <= failures + 1;
            end else begin
                checked_pixels <= checked_pixels + 1;
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        reset = 1'b0;
        wait (frame_count == 4);
        if (failures != 0) begin
            $display("FAIL failures=%0d checked_pixels=%0d", failures, checked_pixels);
            $finish;
        end
        if (checked_pixels < H_ACTIVE * V_ACTIVE) begin
            $display("FAIL insufficient checked pixels: %0d", checked_pixels);
            $finish;
        end
        if (axi_error) begin
            $display("FAIL AXI error flag set");
            $finish;
        end
        $display("AXI_FRAMEBUFFER_LINE_READER_OK checked_pixels=%0d underflow_seen=%0d", checked_pixels, underflow);
        $display("SIM_OK");
        $finish;
    end
endmodule

`default_nettype wire
