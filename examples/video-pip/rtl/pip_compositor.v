`timescale 1ns/1ps
`default_nettype none

module pip_compositor #(
    parameter integer PIP_X = 96,
    parameter integer PIP_Y = 80,
    parameter integer PIP_W = 160,
    parameter integer PIP_H = 120
) (
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire        active,
    input  wire [23:0] bg_rgb,
    input  wire [2:0]  demo_phase,
    input  wire [8:0]  demo_step,
    input  wire [1:0]  manual_effect_mode,
    output wire [1:0]  active_effect_mode,
    output wire        pip_active,
    output wire [23:0] rgb
);

    wire [11:0] motion_tmp = {1'b0, demo_step, 2'b00} + {3'b000, demo_step};
    wire [6:0]  motion_x = motion_tmp[10:4];
    wire [5:0]  motion_y = motion_tmp[10:5];
    wire [10:0] step_x = {4'b0000, motion_x};
    wire [9:0]  step_y = {4'b0000, motion_y};

    wire [10:0] pip_x_static = PIP_X;
    wire [9:0]  pip_y_static = PIP_Y;
    wire [10:0] pip_x_move = PIP_X + step_x;
    wire [9:0]  pip_y_move = PIP_Y + step_y;
    wire [10:0] pip_x_combo = 11'd320 + step_x;
    wire [9:0]  pip_y_combo = 10'd220 - step_y;
    wire        pip_visible = (demo_phase != 3'd0);

    wire [10:0] pip_x_dynamic = (demo_phase == 3'd2) ? pip_x_move :
                                 (demo_phase == 3'd5) ? pip_x_combo :
                                                        pip_x_static;
    wire [9:0]  pip_y_dynamic = (demo_phase == 3'd2) ? pip_y_move :
                                 (demo_phase == 3'd5) ? pip_y_combo :
                                                        pip_y_static;
    assign active_effect_mode = (demo_phase == 3'd3) ? 2'd2 :
                                (demo_phase == 3'd4) ? 2'd1 :
                                (demo_phase == 3'd5) ? 2'd3 :
                                                       manual_effect_mode;

    wire inside_x = (x >= pip_x_dynamic) && (x < pip_x_dynamic + PIP_W);
    wire inside_y = (y >= pip_y_dynamic) && (y < pip_y_dynamic + PIP_H);
    wire [10:0] local_x = x - pip_x_dynamic;
    wire [9:0]  local_y = y - pip_y_dynamic;
    wire [10:0] src_x;
    wire [9:0]  src_y;
    wire [23:0] pip_rgb;

    video_effect_transform transform_i (
        .local_x(local_x),
        .local_y(local_y),
        .effect_mode(active_effect_mode),
        .src_x(src_x),
        .src_y(src_y)
    );

    pattern_pip #(
        .PIP_W(PIP_W),
        .PIP_H(PIP_H)
    ) pattern_pip_i (
        .local_x(local_x),
        .local_y(local_y),
        .src_x(src_x),
        .src_y(src_y),
        .rgb(pip_rgb)
    );

    assign pip_active = active && pip_visible && inside_x && inside_y;
    assign rgb = pip_active ? pip_rgb : bg_rgb;

endmodule

`default_nettype wire
