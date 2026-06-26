`timescale 1ns/1ps
`default_nettype none

module rgmii_rx_activity_axi_writer #(
    parameter [31:0] BASE_ADDR = 32'h1ff0_0000,
    parameter integer AXI_TICKS_PER_WRITE = 6_250_000,
    parameter integer AXI_START_DELAY_TICKS = 125_000_000
) (
    input  wire        reset_n,

    input  wire        rgmii_rxc,
    input  wire        rgmii_rx_ctl,
    input  wire [3:0]  rgmii_rd,

    input  wire        axi_clk,
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    output reg  [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output reg         m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    output reg         write_error
);

    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_AW   = 2'd1,
        ST_W    = 2'd2,
        ST_B    = 2'd3;

    reg [31:0] rxc_edges;
    reg [31:0] rx_ctl_high_cycles;
    reg [31:0] rx_ctl_rise_count;
    reg [31:0] rd_transition_count;
    reg [31:0] rxc_edges_gray;
    reg [31:0] rx_ctl_high_cycles_gray;
    reg [31:0] rx_ctl_rise_count_gray;
    reg [31:0] rd_transition_count_gray;
    reg        prev_rx_ctl;
    reg [3:0]  prev_rd;

    reg [31:0] tick_count;
    reg [31:0] start_delay_count;
    reg        start_delay_done;
    reg [1:0]  state;
    reg        beat_index;
    reg [31:0] snap_edges;
    reg [31:0] snap_high_cycles;
    reg [31:0] snap_rise_count;
    reg [31:0] snap_transition_count;

    (* ASYNC_REG = "TRUE" *) reg [31:0] rxc_edges_gray_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rxc_edges_gray_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rx_ctl_high_cycles_gray_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rx_ctl_high_cycles_gray_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rx_ctl_rise_count_gray_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rx_ctl_rise_count_gray_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rd_transition_count_gray_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rd_transition_count_gray_sync;

    assign m_axi_awaddr = BASE_ADDR;
    assign m_axi_awlen = 8'd1;
    assign m_axi_awsize = 3'b011;
    assign m_axi_awburst = 2'b01;
    assign m_axi_wstrb = 8'hff;

    function [31:0] bin_to_gray32;
        input [31:0] value;
        begin
            bin_to_gray32 = value ^ (value >> 1);
        end
    endfunction

    function [31:0] gray_to_bin32;
        input [31:0] value;
        integer i;
        begin
            gray_to_bin32[31] = value[31];
            for (i = 30; i >= 0; i = i - 1) begin
                gray_to_bin32[i] = gray_to_bin32[i + 1] ^ value[i];
            end
        end
    endfunction

    always @(posedge rgmii_rxc or negedge reset_n) begin
        if (!reset_n) begin
            rxc_edges <= 32'd0;
            rx_ctl_high_cycles <= 32'd0;
            rx_ctl_rise_count <= 32'd0;
            rd_transition_count <= 32'd0;
            rxc_edges_gray <= 32'd0;
            rx_ctl_high_cycles_gray <= 32'd0;
            rx_ctl_rise_count_gray <= 32'd0;
            rd_transition_count_gray <= 32'd0;
            prev_rx_ctl <= 1'b0;
            prev_rd <= 4'd0;
        end else begin
            rxc_edges <= rxc_edges + 32'd1;
            if (rgmii_rx_ctl) begin
                rx_ctl_high_cycles <= rx_ctl_high_cycles + 32'd1;
            end
            if (rgmii_rx_ctl && !prev_rx_ctl) begin
                rx_ctl_rise_count <= rx_ctl_rise_count + 32'd1;
            end
            if (rgmii_rd != prev_rd) begin
                rd_transition_count <= rd_transition_count + 32'd1;
            end
            prev_rx_ctl <= rgmii_rx_ctl;
            prev_rd <= rgmii_rd;
            rxc_edges_gray <= bin_to_gray32(rxc_edges);
            rx_ctl_high_cycles_gray <= bin_to_gray32(rx_ctl_high_cycles);
            rx_ctl_rise_count_gray <= bin_to_gray32(rx_ctl_rise_count);
            rd_transition_count_gray <= bin_to_gray32(rd_transition_count);
        end
    end

    always @(posedge axi_clk or negedge reset_n) begin
        if (!reset_n) begin
            tick_count <= 32'd0;
            start_delay_count <= 32'd0;
            start_delay_done <= 1'b0;
            state <= ST_IDLE;
            beat_index <= 1'b0;
            snap_edges <= 32'd0;
            snap_high_cycles <= 32'd0;
            snap_rise_count <= 32'd0;
            snap_transition_count <= 32'd0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata <= 64'd0;
            m_axi_wlast <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;
            write_error <= 1'b0;
            rxc_edges_gray_meta <= 32'd0;
            rxc_edges_gray_sync <= 32'd0;
            rx_ctl_high_cycles_gray_meta <= 32'd0;
            rx_ctl_high_cycles_gray_sync <= 32'd0;
            rx_ctl_rise_count_gray_meta <= 32'd0;
            rx_ctl_rise_count_gray_sync <= 32'd0;
            rd_transition_count_gray_meta <= 32'd0;
            rd_transition_count_gray_sync <= 32'd0;
        end else begin
            rxc_edges_gray_meta <= rxc_edges_gray;
            rxc_edges_gray_sync <= rxc_edges_gray_meta;
            rx_ctl_high_cycles_gray_meta <= rx_ctl_high_cycles_gray;
            rx_ctl_high_cycles_gray_sync <= rx_ctl_high_cycles_gray_meta;
            rx_ctl_rise_count_gray_meta <= rx_ctl_rise_count_gray;
            rx_ctl_rise_count_gray_sync <= rx_ctl_rise_count_gray_meta;
            rd_transition_count_gray_meta <= rd_transition_count_gray;
            rd_transition_count_gray_sync <= rd_transition_count_gray_meta;

            if (!start_delay_done) begin
                if (start_delay_count >= AXI_START_DELAY_TICKS - 1) begin
                    start_delay_done <= 1'b1;
                end else begin
                    start_delay_count <= start_delay_count + 32'd1;
                end
                m_axi_awvalid <= 1'b0;
                m_axi_wvalid <= 1'b0;
                m_axi_wlast <= 1'b0;
                m_axi_bready <= 1'b0;
                state <= ST_IDLE;
            end else begin
                case (state)
                ST_IDLE: begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast <= 1'b0;
                    m_axi_bready <= 1'b0;
                    if (tick_count >= AXI_TICKS_PER_WRITE - 1) begin
                        tick_count <= 32'd0;
                        snap_edges <= gray_to_bin32(rxc_edges_gray_sync);
                        snap_high_cycles <= gray_to_bin32(rx_ctl_high_cycles_gray_sync);
                        snap_rise_count <= gray_to_bin32(rx_ctl_rise_count_gray_sync);
                        snap_transition_count <= gray_to_bin32(rd_transition_count_gray_sync);
                        m_axi_awvalid <= 1'b1;
                        state <= ST_AW;
                    end else begin
                        tick_count <= tick_count + 32'd1;
                    end
                end

                ST_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        beat_index <= 1'b0;
                        m_axi_wdata <= {snap_high_cycles, snap_rise_count};
                        m_axi_wlast <= 1'b0;
                        m_axi_wvalid <= 1'b1;
                        state <= ST_W;
                    end
                end

                ST_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (!beat_index) begin
                            beat_index <= 1'b1;
                            m_axi_wdata <= {snap_transition_count, snap_edges};
                            m_axi_wlast <= 1'b1;
                        end else begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state <= ST_B;
                        end
                    end
                end

                ST_B: begin
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00) begin
                            write_error <= 1'b1;
                        end
                        m_axi_bready <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
