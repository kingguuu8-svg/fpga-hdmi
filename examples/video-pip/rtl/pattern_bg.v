`timescale 1ns/1ps
`default_nettype none

module pattern_bg (
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire        active,
    output reg  [23:0] rgb
);

    wire grid = (x[5:0] == 6'd0) || (y[5:0] == 6'd0);
    wire panel = (x >= 11'd48) && (x < 11'd592) && (y >= 10'd48) && (y < 10'd432);
    wire horizon = (y >= 10'd236) && (y < 10'd244);

    always @* begin
        if (!active) begin
            rgb = 24'h000000;
        end else if (horizon) begin
            rgb = 24'h203850;
        end else if (grid) begin
            rgb = panel ? 24'h1d3346 : 24'h12202c;
        end else if (panel) begin
            rgb = 24'h172a3a;
        end else if (y < 10'd48) begin
            rgb = 24'h0f1c28;
        end else begin
            rgb = 24'h101820;
        end
    end

endmodule

`default_nettype wire
