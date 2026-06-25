`timescale 1ns/1ps
`default_nettype none

module pattern_pip #(
    parameter integer PIP_W = 160,
    parameter integer PIP_H = 120
) (
    input  wire [10:0] local_x,
    input  wire [9:0]  local_y,
    input  wire [10:0] src_x,
    input  wire [9:0]  src_y,
    output reg  [23:0] rgb
);

    wire border = (local_x < 11'd4) || (local_y < 10'd4) ||
                  (local_x >= PIP_W - 4) || (local_y >= PIP_H - 4);
    wire left_marker = src_x < 11'd12;
    wire top_marker = src_y < 10'd12;
    wire center_marker = (src_x >= 11'd52) && (src_x < 11'd68) &&
                         (src_y >= 10'd32) && (src_y < 10'd48);
    wire diagonal = (src_x[6:2] == src_y[6:2]) ||
                    (src_x[6:2] == src_y[6:2] + 5'd1);

    always @* begin
        if (border) begin
            rgb = 24'hffffff;
        end else if (left_marker) begin
            rgb = 24'he53935;
        end else if (top_marker) begin
            rgb = 24'h43a047;
        end else if (center_marker) begin
            rgb = 24'hfdd835;
        end else if (diagonal) begin
            rgb = 24'h80deea;
        end else begin
            rgb = 24'h1565c0;
        end
    end

endmodule

`default_nettype wire
