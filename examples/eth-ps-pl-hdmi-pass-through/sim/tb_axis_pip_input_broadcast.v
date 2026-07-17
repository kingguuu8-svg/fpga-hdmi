`timescale 1ns/1ps
`default_nettype none

module tb_axis_pip_input_broadcast;
    reg aclk = 1'b0;
    reg aresetn = 1'b0;
    reg [23:0] s_axis_tdata = 24'd0;
    reg        s_axis_tvalid = 1'b0;
    wire       s_axis_tready;
    reg        s_axis_tlast = 1'b0;
    reg        s_axis_tuser = 1'b0;
    wire [23:0] m_main_tdata;
    wire        m_main_tvalid;
    reg         m_main_tready = 1'b1;
    wire        m_main_tlast;
    wire        m_main_tuser;
    wire [23:0] m_pip_tdata;
    wire        m_pip_tvalid;
    reg         m_pip_tready = 1'b0;
    wire        m_pip_tlast;
    wire        m_pip_tuser;
    integer main_count = 0;
    integer pip_count = 0;
    integer i;

    always #5 aclk = ~aclk;

    axis_pip_input_broadcast dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .m_main_tdata(m_main_tdata),
        .m_main_tvalid(m_main_tvalid),
        .m_main_tready(m_main_tready),
        .m_main_tlast(m_main_tlast),
        .m_main_tuser(m_main_tuser),
        .m_pip_tdata(m_pip_tdata),
        .m_pip_tvalid(m_pip_tvalid),
        .m_pip_tready(m_pip_tready),
        .m_pip_tlast(m_pip_tlast),
        .m_pip_tuser(m_pip_tuser)
    );

    always @(posedge aclk) begin
        if (aresetn) begin
            if (m_main_tvalid && m_main_tready) begin
                if (m_main_tdata !== (24'h100000 + main_count) ||
                    m_main_tuser !== (main_count == 0) ||
                    m_main_tlast !== (main_count == 3)) begin
                    $fatal(1, "main copy mismatch count=%0d data=%h", main_count, m_main_tdata);
                end
                main_count = main_count + 1;
            end
            if (m_pip_tvalid && m_pip_tready) begin
                if (m_pip_tdata !== (24'h100000 + pip_count) ||
                    m_pip_tuser !== (pip_count == 0) ||
                    m_pip_tlast !== (pip_count == 3)) begin
                    $fatal(1, "pip copy mismatch count=%0d data=%h", pip_count, m_pip_tdata);
                end
                pip_count = pip_count + 1;
            end
        end
    end

    task send_beat;
        input [23:0] data;
        input        tuser;
        input        tlast;
        begin
            @(negedge aclk);
            s_axis_tdata = data;
            s_axis_tuser = tuser;
            s_axis_tlast = tlast;
            s_axis_tvalid = 1'b1;
            while (!s_axis_tready) @(negedge aclk);
            @(negedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tuser = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    initial begin
        #20;
        aresetn = 1'b1;
        #30;
        m_pip_tready = 1'b1;
        for (i = 0; i < 4; i = i + 1) begin
            send_beat(24'h100000 + i, i == 0, i == 3);
        end
        wait (main_count == 4 && pip_count == 4);
        $display("AXIS_PIP_INPUT_BROADCAST_SIM_OK beats=%0d", main_count);
        $display("SIM_OK");
        $finish;
    end
endmodule

`default_nettype wire
