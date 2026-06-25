`timescale 1ns/1ps
`default_nettype none

module video_pip_top (
    input  wire       clk,
    output wire [1:0] led,
    output wire       hdmi_clk_p,
    output wire       hdmi_clk_n,
    output wire [2:0] hdmi_d_p,
    output wire [2:0] hdmi_d_n
);

    wire pix_clk;
    wire ser_clk;
    wire clk_locked;
    reg [7:0] reset_shift = 8'h00;

    clock_gen_50_to_hdmi clock_i (
        .clk_50(clk),
        .reset(1'b0),
        .pix_clk(pix_clk),
        .ser_clk(ser_clk),
        .locked(clk_locked)
    );

    always @(posedge pix_clk) begin
        if (!clk_locked) begin
            reset_shift <= 8'h00;
        end else if (!reset_shift[7]) begin
            reset_shift <= {reset_shift[6:0], 1'b1};
        end
    end

    wire reset = !reset_shift[7];
    wire [23:0] rgb;
    wire hsync;
    wire vsync;
    wire de;
    wire pip_active;
    wire [10:0] x_unused;
    wire [9:0] y_unused;
    wire [7:0] frame_count;
    wire [2:0] demo_phase;
    wire [8:0] demo_step_unused;
    wire [1:0] active_effect_mode_unused;
    wire [1:0] effect_mode = 2'd0;
    wire animation_pause = 1'b0;

    video_pip_core core_i (
        .pix_clk(pix_clk),
        .reset(reset),
        .effect_mode(effect_mode),
        .animation_pause(animation_pause),
        .rgb(rgb),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .pip_active(pip_active),
        .x(x_unused),
        .y(y_unused),
        .frame_count(frame_count),
        .demo_phase(demo_phase),
        .demo_step(demo_step_unused),
        .active_effect_mode(active_effect_mode_unused)
    );

    wire [9:0] tmds_red;
    wire [9:0] tmds_green;
    wire [9:0] tmds_blue;

    tmds_encoder enc_red_i (
        .clk(pix_clk),
        .reset(reset),
        .din(rgb[23:16]),
        .c0(1'b0),
        .c1(1'b0),
        .de(de),
        .dout(tmds_red)
    );

    tmds_encoder enc_green_i (
        .clk(pix_clk),
        .reset(reset),
        .din(rgb[15:8]),
        .c0(1'b0),
        .c1(1'b0),
        .de(de),
        .dout(tmds_green)
    );

    tmds_encoder enc_blue_i (
        .clk(pix_clk),
        .reset(reset),
        .din(rgb[7:0]),
        .c0(hsync),
        .c1(vsync),
        .de(de),
        .dout(tmds_blue)
    );

    hdmi_phy_7series phy_i (
        .pix_clk(pix_clk),
        .ser_clk(ser_clk),
        .reset(reset),
        .tmds_red(tmds_red),
        .tmds_green(tmds_green),
        .tmds_blue(tmds_blue),
        .hdmi_clk_p(hdmi_clk_p),
        .hdmi_clk_n(hdmi_clk_n),
        .hdmi_d_p(hdmi_d_p),
        .hdmi_d_n(hdmi_d_n)
    );

    assign led[0] = clk_locked;
    assign led[1] = demo_phase[0] ^ pip_active;

endmodule

`default_nettype wire
