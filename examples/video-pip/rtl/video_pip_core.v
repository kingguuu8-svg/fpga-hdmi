`timescale 1ns/1ps
`default_nettype none

module video_pip_core #(
    parameter integer DEMO_FRAMES_PER_PHASE = 300
) (
    input  wire        pix_clk,
    input  wire        reset,
    input  wire [1:0]  effect_mode,
    input  wire        animation_pause,
    output wire [23:0] rgb,
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire        pip_active,
    output wire [10:0] x,
    output wire [9:0]  y,
    output reg  [7:0]  frame_count,
    output reg  [2:0]  demo_phase,
    output reg  [8:0]  demo_step,
    output wire [1:0]  active_effect_mode
);

    wire frame_start;
    wire line_start_unused;
    wire [23:0] bg_rgb;

    video_timing_640x480 timing_i (
        .pix_clk(pix_clk),
        .reset(reset),
        .x(x),
        .y(y),
        .active(de),
        .hsync(hsync),
        .vsync(vsync),
        .frame_start(frame_start),
        .line_start(line_start_unused)
    );

    always @(posedge pix_clk) begin
        if (reset) begin
            frame_count <= 8'd0;
            demo_phase <= 3'd0;
            demo_step <= 9'd0;
        end else if (frame_start && !animation_pause) begin
            frame_count <= frame_count + 8'd1;
            if (demo_step == DEMO_FRAMES_PER_PHASE[8:0] - 9'd1) begin
                demo_step <= 9'd0;
                demo_phase <= (demo_phase == 3'd5) ? 3'd0 : demo_phase + 3'd1;
            end else begin
                demo_step <= demo_step + 9'd1;
            end
        end
    end

    pattern_bg bg_i (
        .x(x),
        .y(y),
        .active(de),
        .rgb(bg_rgb)
    );

    pip_compositor pip_i (
        .x(x),
        .y(y),
        .active(de),
        .bg_rgb(bg_rgb),
        .demo_phase(demo_phase),
        .demo_step(demo_step),
        .manual_effect_mode(effect_mode),
        .active_effect_mode(active_effect_mode),
        .pip_active(pip_active),
        .rgb(rgb)
    );

endmodule

`default_nettype wire
