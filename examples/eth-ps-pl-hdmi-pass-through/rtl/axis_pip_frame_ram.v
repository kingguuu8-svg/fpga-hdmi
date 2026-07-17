`timescale 1ns/1ps
`default_nettype none

// Simple dual-port frame storage. Keeping the read and write ports in one
// clocked process gives Vivado a direct BRAM inference pattern.
module axis_pip_frame_ram #(
    parameter integer DEPTH = 57600,
    parameter integer ADDR_WIDTH = 16
) (
    input  wire        clk,
    input  wire        wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [23:0] wr_data,
    input  wire        rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [23:0] rd_data
);

    (* ram_style = "block" *) reg [23:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
        if (rd_en) begin
            rd_data <= mem[rd_addr];
        end
    end

endmodule

`default_nettype wire
