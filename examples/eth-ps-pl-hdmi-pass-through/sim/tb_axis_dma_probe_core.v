`timescale 1ns/1ps
`default_nettype none

module tb_axis_dma_probe_core;
    reg aclk = 1'b0;
    reg aresetn = 1'b0;

    reg  [5:0]  s_axi_awaddr = 6'd0;
    reg         s_axi_awvalid = 1'b0;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata = 32'd0;
    reg  [3:0]  s_axi_wstrb = 4'hf;
    reg         s_axi_wvalid = 1'b0;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready = 1'b1;
    reg  [5:0]  s_axi_araddr = 6'd0;
    reg         s_axi_arvalid = 1'b0;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready = 1'b1;

    reg  [31:0] s_axis_tdata = 32'd0;
    reg  [3:0]  s_axis_tkeep = 4'hf;
    reg         s_axis_tvalid = 1'b0;
    wire        s_axis_tready;
    reg         s_axis_tlast = 1'b0;

    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    reg         m_axis_tready = 1'b1;
    wire        m_axis_tlast;

    wire [31:0] status_frames;
    wire [31:0] status_beats;
    wire [31:0] status_bytes;
    wire [31:0] status_input_checksum;
    wire [31:0] status_output_checksum;

    integer out_count = 0;
    integer expected_count = 0;
    reg [31:0] expected_data [0:15];
    reg [3:0]  expected_keep [0:15];
    reg        expected_last [0:15];

    always #5 aclk = ~aclk;

    axis_dma_probe_core dut (
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
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .status_frames(status_frames),
        .status_beats(status_beats),
        .status_bytes(status_bytes),
        .status_input_checksum(status_input_checksum),
        .status_output_checksum(status_output_checksum)
    );

    task axi_write;
        input [5:0] addr;
        input [31:0] data;
        begin
            @(negedge aclk);
            s_axi_awaddr = addr;
            s_axi_wdata = data;
            s_axi_awvalid = 1'b1;
            s_axi_wvalid = 1'b1;
            @(posedge aclk);
            while (!s_axi_bvalid) begin
                @(posedge aclk);
            end
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
        end
    endtask

    task expect_beat;
        input [31:0] data;
        input [3:0] keep;
        input last;
        begin
            expected_data[expected_count] = data;
            expected_keep[expected_count] = keep;
            expected_last[expected_count] = last;
            expected_count = expected_count + 1;
        end
    endtask

    task send_beat;
        input [31:0] data;
        input [3:0] keep;
        input last;
        begin
            @(negedge aclk);
            s_axis_tdata = data;
            s_axis_tkeep = keep;
            s_axis_tlast = last;
            s_axis_tvalid = 1'b1;
            @(posedge aclk);
            while (!s_axis_tready) begin
                @(posedge aclk);
            end
            #1;
            if (!m_axis_tvalid) begin
                $display("FAIL missing output beat");
                $finish;
            end
            if (m_axis_tdata !== expected_data[out_count] ||
                m_axis_tkeep !== expected_keep[out_count] ||
                m_axis_tlast !== expected_last[out_count]) begin
                $display("FAIL output mismatch index=%0d got=%08x keep=%x last=%b expected=%08x keep=%x last=%b",
                         out_count, m_axis_tdata, m_axis_tkeep, m_axis_tlast,
                         expected_data[out_count], expected_keep[out_count],
                         expected_last[out_count]);
                $finish;
            end
            out_count = out_count + 1;
        end
    endtask

    initial begin
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);

        expect_beat(32'h01020304, 4'hf, 1'b0);
        expect_beat(32'h11121314, 4'h3, 1'b1);
        send_beat(32'h01020304, 4'hf, 1'b0);
        send_beat(32'h11121314, 4'h3, 1'b1);
        @(negedge aclk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        repeat (2) @(posedge aclk);

        if (status_frames != 32'd1 || status_beats != 32'd2 || status_bytes != 32'd6) begin
            $display("FAIL pass counters frames=%0d beats=%0d bytes=%0d",
                     status_frames, status_beats, status_bytes);
            $finish;
        end
        if (status_input_checksum !== status_output_checksum) begin
            $display("FAIL pass checksum input=%08x output=%08x",
                     status_input_checksum, status_output_checksum);
            $finish;
        end

        axi_write(6'h00, 32'h00000004);
        axi_write(6'h04, 32'h00ff00ff);
        axi_write(6'h00, 32'h00000003);

        out_count = 0;
        expected_count = 0;
        expect_beat(32'haabbccdd ^ 32'h00ff00ff, 4'hf, 1'b0);
        expect_beat(32'h12345678 ^ 32'h00ff00ff, 4'hf, 1'b1);
        send_beat(32'haabbccdd, 4'hf, 1'b0);
        send_beat(32'h12345678, 4'hf, 1'b1);
        @(negedge aclk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        repeat (2) @(posedge aclk);

        if (status_frames != 32'd1 || status_beats != 32'd2 || status_bytes != 32'd8) begin
            $display("FAIL marker counters frames=%0d beats=%0d bytes=%0d",
                     status_frames, status_beats, status_bytes);
            $finish;
        end
        if (status_input_checksum === status_output_checksum) begin
            $display("FAIL marker checksum did not change checksum=%08x",
                     status_input_checksum);
            $finish;
        end

        $display("AXIS_DMA_PROBE_CORE_SIM_OK frames=%0d beats=%0d bytes=%0d input_checksum=%08x output_checksum=%08x",
                 status_frames, status_beats, status_bytes,
                 status_input_checksum, status_output_checksum);
        $display("SIM_OK");
        $finish;
    end

    initial begin
        repeat (1000) @(posedge aclk);
        $display("FAIL timeout");
        $finish;
    end
endmodule

`default_nettype wire
