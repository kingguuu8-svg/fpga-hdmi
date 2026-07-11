`timescale 1ns/1ps

module tb_jpeg_pl_decoder_axis;
    localparam integer WIDTH = 1280;
    localparam integer HEIGHT = 720;
    localparam integer PIXELS = WIDTH * HEIGHT;
    localparam integer BYTES = PIXELS * 3;
    localparam integer STRIDE = WIDTH * 3;
    localparam integer MAX_WORDS = 65536;
    localparam integer MAX_CYCLES = 10000000;
    localparam [31:0] BASE_ADDR = 32'h02000000;
    localparam [31:0] VERSION = 32'h4a504c31;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg [5:0] awaddr = 6'd0;
    reg awvalid = 1'b0;
    wire awready;
    reg [31:0] wdata = 32'd0;
    reg [3:0] wstrb = 4'hf;
    reg wvalid = 1'b0;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 1'b0;
    reg [5:0] araddr = 6'd0;
    reg arvalid = 1'b0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready = 1'b0;

    reg [31:0] jpeg_tdata = 32'd0;
    reg [3:0] jpeg_tkeep = 4'd0;
    reg jpeg_tlast = 1'b0;
    reg jpeg_tvalid = 1'b0;
    wire jpeg_tready;

    wire [71:0] cmd_tdata;
    wire cmd_tvalid;
    reg cmd_tready = 1'b0;
    wire [31:0] data_tdata;
    wire [3:0] data_tkeep;
    wire data_tlast;
    wire data_tvalid;
    reg data_tready = 1'b0;
    reg [7:0] sts_tdata = 8'd0;
    reg sts_tvalid = 1'b0;
    wire sts_tready;

    reg [36:0] jpeg_words [0:MAX_WORDS-1];
    reg [23:0] frame [0:PIXELS-1];
    reg [15:0] lfsr;
    reg [31:0] active_address;
    reg [3:0] active_tag;
    integer active_word;
    reg [2:0] status_delay;
    reg data_active;
    integer word_count;
    integer word_index;
    integer cycle_count;
    integer index;
    integer byte_index;
    integer pixel_index;
    integer tile_count;
    integer response_count;
    integer failures;
    reg word_sent;

    always #5 clk = ~clk;

    jpeg_pl_decoder_axis dut (
        .aclk(clk),
        .aresetn(resetn),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .s_jpeg_tdata(jpeg_tdata),
        .s_jpeg_tkeep(jpeg_tkeep),
        .s_jpeg_tlast(jpeg_tlast),
        .s_jpeg_tvalid(jpeg_tvalid),
        .s_jpeg_tready(jpeg_tready),
        .m_cmd_tdata(cmd_tdata),
        .m_cmd_tvalid(cmd_tvalid),
        .m_cmd_tready(cmd_tready),
        .m_data_tdata(data_tdata),
        .m_data_tkeep(data_tkeep),
        .m_data_tlast(data_tlast),
        .m_data_tvalid(data_tvalid),
        .m_data_tready(data_tready),
        .s_sts_tdata(sts_tdata),
        .s_sts_tvalid(sts_tvalid),
        .s_sts_tready(sts_tready)
    );

    task axi_write;
        input [5:0] address;
        input [31:0] value;
        reg aw_done;
        reg w_done;
        begin
            aw_done = 1'b0;
            w_done = 1'b0;
            @(negedge clk);
            awaddr = address;
            wdata = value;
            awvalid = 1'b1;
            wvalid = 1'b1;
            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (awvalid && awready)
                    aw_done = 1'b1;
                if (wvalid && wready)
                    w_done = 1'b1;
                @(negedge clk);
                if (aw_done)
                    awvalid = 1'b0;
                if (w_done)
                    wvalid = 1'b0;
            end
            while (!bvalid)
                @(posedge clk);
            if (bresp !== 2'b00) begin
                $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=axi_write_bresp address=%h bresp=%b",
                         address, bresp);
                failures = failures + 1;
            end
            @(negedge clk);
            bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task axi_write_split;
        input [5:0] address;
        input [31:0] value;
        input integer gap_cycles;
        reg aw_done;
        reg w_done;
        begin
            aw_done = 1'b0;
            w_done = 1'b0;
            @(negedge clk);
            awaddr = address;
            awvalid = 1'b1;
            while (!aw_done) begin
                @(posedge clk);
                if (awvalid && awready)
                    aw_done = 1'b1;
                @(negedge clk);
                if (aw_done)
                    awvalid = 1'b0;
            end

            repeat (gap_cycles) @(posedge clk);
            @(negedge clk);
            wdata = value;
            wstrb = 4'hf;
            wvalid = 1'b1;
            while (!w_done) begin
                @(posedge clk);
                if (wvalid && wready)
                    w_done = 1'b1;
                @(negedge clk);
                if (w_done)
                    wvalid = 1'b0;
            end
            while (!bvalid)
                @(posedge clk);
            if (bresp !== 2'b00) begin
                $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=axi_write_split_bresp address=%h bresp=%b",
                         address, bresp);
                failures = failures + 1;
            end
            @(negedge clk);
            bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task axi_read;
        input [5:0] address;
        output [31:0] value;
        reg ar_done;
        begin
            ar_done = 1'b0;
            @(negedge clk);
            araddr = address;
            arvalid = 1'b1;
            while (!ar_done) begin
                @(posedge clk);
                if (arvalid && arready)
                    ar_done = 1'b1;
                @(negedge clk);
                if (ar_done)
                    arvalid = 1'b0;
            end
            while (!rvalid)
                @(posedge clk);
            value = rdata;
            if (rresp !== 2'b00) begin
                $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=axi_read_rresp address=%h rresp=%b",
                         address, rresp);
                failures = failures + 1;
            end
            @(negedge clk);
            rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task axi_read_expect;
        input [5:0] address;
        input [31:0] expected;
        reg [31:0] value;
        begin
            axi_read(address, value);
            if (value !== expected) begin
                $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=axi_readback address=%h expected=%h actual=%h",
                         address, expected, value);
                failures = failures + 1;
            end
        end
    endtask

    task jpeg_send_word;
        input [36:0] word;
        output accepted;
        begin
            accepted = 1'b0;
            @(negedge clk);
            jpeg_tdata = word[31:0];
            jpeg_tkeep = word[35:32];
            jpeg_tlast = word[36];
            jpeg_tvalid = 1'b1;
            while (!accepted && !dut.u_writer.done) begin
                @(posedge clk);
                if (jpeg_tvalid && jpeg_tready)
                    accepted = 1'b1;
                @(negedge clk);
                if (accepted || dut.u_writer.done) begin
                    jpeg_tvalid = 1'b0;
                    jpeg_tlast = 1'b0;
                    jpeg_tkeep = 4'd0;
                end
            end
        end
    endtask

    task store_byte;
        input [31:0] address;
        input [7:0] value;
        begin
            if (address < BASE_ADDR || address >= BASE_ADDR + BYTES) begin
                $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=bad_address address=%h", address);
                $finish;
            end
            byte_index = address - BASE_ADDR;
            pixel_index = byte_index / 3;
            case (byte_index % 3)
                0: frame[pixel_index][23:16] = value;
                1: frame[pixel_index][15:8] = value;
                default: frame[pixel_index][7:0] = value;
            endcase
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            lfsr <= 16'h1ace;
            cmd_tready <= 1'b0;
            data_tready <= 1'b0;
            cycle_count <= 0;
            active_address <= 32'd0;
            active_tag <= 4'd0;
            active_word <= 0;
            status_delay <= 3'd0;
            data_active <= 1'b0;
            sts_tdata <= 8'd0;
            sts_tvalid <= 1'b0;
            tile_count <= 0;
            response_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            cmd_tready <= lfsr[0] | lfsr[3];
            data_tready <= lfsr[1] | lfsr[4];

            if (sts_tvalid && sts_tready) begin
                sts_tvalid <= 1'b0;
                response_count <= response_count + 1;
            end else if (!sts_tvalid && status_delay != 0) begin
                status_delay <= status_delay - 3'd1;
                if (status_delay == 3'd1) begin
                    sts_tdata <= {1'b1, 3'b000, active_tag};
                    sts_tvalid <= 1'b1;
                end
            end

            if (cmd_tvalid && cmd_tready) begin
                if (cmd_tdata[22:0] != 23'd48) begin
                    $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=bad_btt btt=%0d",
                             cmd_tdata[22:0]);
                    $finish;
                end
                if (cmd_tdata[71:68] != 4'd0 || cmd_tdata[31] != 1'b0 ||
                    cmd_tdata[30] != 1'b1 || cmd_tdata[29:24] != 6'd0 ||
                    cmd_tdata[23] != 1'b1) begin
                    $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=bad_s2mm_command_fields rsv=%h drr=%0d eof=%0d dsa=%0d incr=%0d",
                             cmd_tdata[71:68], cmd_tdata[31], cmd_tdata[30],
                             cmd_tdata[29:24], cmd_tdata[23]);
                    $finish;
                end
                active_address <= cmd_tdata[63:32];
                active_tag <= cmd_tdata[67:64];
                active_word <= 0;
                data_active <= 1'b1;
                tile_count <= tile_count + 1;
            end

            if (data_tvalid && data_tready) begin
                if (!data_active || data_tkeep != 4'hf) begin
                    $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=bad_data_state active=%0d keep=%h",
                             data_active, data_tkeep);
                    $finish;
                end
                store_byte(active_address + (active_word * 4), data_tdata[7:0]);
                store_byte(active_address + (active_word * 4) + 32'd1, data_tdata[15:8]);
                store_byte(active_address + (active_word * 4) + 32'd2, data_tdata[23:16]);
                store_byte(active_address + (active_word * 4) + 32'd3, data_tdata[31:24]);
                if (data_tlast != (active_word == 11)) begin
                    $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=bad_last word=%0d last=%0d",
                             active_word, data_tlast);
                    $finish;
                end
                if (active_word == 11) begin
                    data_active <= 1'b0;
                    status_delay <= 3'd3;
                end else begin
                    active_word <= active_word + 1;
                end
            end

            if (cycle_count >= MAX_CYCLES) begin
                $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=timeout cycles=%0d word_index=%0d jpeg_valid=%0d jpeg_ready=%0d core_accept=%0d core_valid=%0d pixel_ready=%0d busy=%0d done=%0d pixels=%0d commands=%0d responses=%0d errors=%h",
                         cycle_count, word_index, jpeg_tvalid, jpeg_tready,
                         dut.core_accept, dut.core_valid, dut.pixel_ready,
                         dut.u_writer.busy, dut.u_writer.done,
                         dut.u_writer.status_pixels,
                         dut.u_writer.status_commands,
                         dut.u_writer.status_responses,
                         dut.u_writer.status_error_flags);
                $finish;
            end
        end
    end

    initial begin
        word_count = 0;
        word_index = 0;
        failures = 0;
        for (index = 0; index < PIXELS; index = index + 1)
            frame[index] = 24'd0;
        if (!$value$plusargs("WORD_COUNT=%d", word_count)) begin
            $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=missing_word_count");
            $finish;
        end
        $readmemh("jpeg_words.mem", jpeg_words);
        repeat (10) @(posedge clk);
        resetn <= 1'b1;

        axi_write(6'h00, 32'h00000005);
        axi_read_expect(6'h00, 32'h00000005);
        jpeg_send_word({1'b0, 4'hf, 32'h44332211}, word_sent);
        if (!word_sent) begin
            $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=input_sink_first_word_not_accepted");
            failures = failures + 1;
        end
        jpeg_send_word({1'b1, 4'h1, 32'h00000055}, word_sent);
        if (!word_sent) begin
            $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=input_sink_last_word_not_accepted");
            failures = failures + 1;
        end
        axi_read_expect(6'h34, 32'd5);
        axi_read_expect(6'h18, 32'd0);
        axi_read_expect(6'h20, 32'd0);
        axi_read_expect(6'h24, 32'd0);
        axi_read_expect(6'h28, 32'd0);
        repeat (20) @(posedge clk);
        axi_write(6'h00, 32'h00000003);
        repeat (3) @(posedge clk);
        if (dut.u_writer.status_cycles > 32'd16) begin
            $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=restart_cycle_counter_not_reset cycles=%0d",
                     dut.u_writer.status_cycles);
            failures = failures + 1;
        end
        if (failures == 0)
            $display("JPEG_INPUT_SINK_SUBTEST_OK input_bytes=5 pixels=0 commands=0 responses=0 output_bytes=0");

        @(negedge clk);
        resetn = 1'b0;
        jpeg_tvalid = 1'b0;
        repeat (10) @(posedge clk);
        resetn = 1'b1;

        axi_write_split(6'h04, BASE_ADDR, 3);
        axi_write_split(6'h08, STRIDE, 2);
        axi_write(6'h0c, {HEIGHT[15:0], WIDTH[15:0]});
        axi_write(6'h10, PIXELS);
        axi_read_expect(6'h3c, VERSION);
        axi_read_expect(6'h04, BASE_ADDR);
        axi_read_expect(6'h08, STRIDE);
        axi_read_expect(6'h0c, {HEIGHT[15:0], WIDTH[15:0]});
        axi_read_expect(6'h10, PIXELS);
        axi_write_split(6'h00, 32'h00000001, 4);
        axi_read_expect(6'h00, 32'h00000001);

        while (word_index < word_count && !dut.u_writer.done) begin
            jpeg_send_word(jpeg_words[word_index], word_sent);
            if (word_sent)
                word_index = word_index + 1;
        end
        if (word_index != word_count) begin
            $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=input_stopped word_index=%0d word_count=%0d errors=%h",
                     word_index, word_count, dut.u_writer.status_error_flags);
            failures = failures + 1;
        end

        wait (dut.u_writer.done);
        repeat (5) @(posedge clk);
        if (dut.u_writer.status_error_flags != 0 ||
            dut.u_writer.status_pixels != PIXELS ||
            dut.u_writer.status_output_bytes != BYTES ||
            dut.u_writer.status_commands != ((WIDTH / 16) * (HEIGHT / 16) * 16) ||
            dut.u_writer.status_responses != dut.u_writer.status_commands ||
            tile_count != ((WIDTH / 16) * (HEIGHT / 16) * 16) ||
            response_count != tile_count) begin
            $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=summary errors=%h pixels=%0d bytes=%0d commands=%0d responses=%0d tile_count=%0d response_count=%0d",
                     dut.u_writer.status_error_flags,
                     dut.u_writer.status_pixels,
                     dut.u_writer.status_output_bytes,
                     dut.u_writer.status_commands,
                     dut.u_writer.status_responses,
                     tile_count, response_count);
            failures = failures + 1;
        end
        axi_read_expect(6'h00, 32'h00000008);
        if (failures != 0)
            $display("JPEG_BOARD_DATAPATH_SIM_FAILED reason=checks failures=%0d", failures);
        else begin
            $writememh("rtl_pixels.hex", frame);
            $display("JPEG_BOARD_DATAPATH_SIM_OK pixels=%0d lines=%0d commands=%0d responses=%0d bytes=%0d input_bytes=%0d cycles=%0d stalls=%0d",
                     dut.u_writer.status_pixels, tile_count,
                     dut.u_writer.status_commands, dut.u_writer.status_responses,
                     dut.u_writer.status_output_bytes, dut.input_bytes,
                     dut.u_writer.status_cycles, dut.u_writer.status_stall_cycles);
        end
        $finish;
    end
endmodule
