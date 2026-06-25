`timescale 1ns/1ps
`default_nettype none

module video_effect_transform #(
    parameter integer SRC_W = 60,
    parameter integer SRC_H = 80,
    parameter integer PIP_W = 160
) (
    input  wire [10:0] local_x,
    input  wire [9:0]  local_y,
    input  wire [1:0]  effect_mode,
    output wire [10:0] src_x,
    output wire [9:0]  src_y
);

    wire [10:0] scaled_x = {1'b0, local_x[10:1]};
    wire [9:0]  scaled_y = {1'b0, local_y[9:1]};
    wire [10:0] rotate_x = {1'b0, local_y};
    wire [9:0]  rotate_y = (PIP_W - 1) - local_x[9:0];
    wire [10:0] scale_rotate_x = {1'b0, scaled_y};
    wire [9:0]  scale_rotate_y = (SRC_H - 1) - scaled_x[9:0];

    assign src_x = (effect_mode == 2'd0) ? local_x :
                   (effect_mode == 2'd1) ? scaled_x :
                   (effect_mode == 2'd2) ? rotate_x :
                                            scale_rotate_x;

    assign src_y = (effect_mode == 2'd0) ? local_y :
                   (effect_mode == 2'd1) ? {1'b0, scaled_y[8:0]} :
                   (effect_mode == 2'd2) ? rotate_y :
                                            scale_rotate_y;

endmodule

`default_nettype wire
