`timescale 1ns/1ps
`default_nettype none

module tb_video_pip_core;
    reg pix_clk = 1'b0;
    reg reset = 1'b1;
    reg [1:0] effect_mode = 2'd0;
    reg animation_pause = 1'b0;
    reg [1:0] key_n = 2'b11;

    wire [23:0] rgb;
    wire hsync;
    wire vsync;
    wire de;
    wire pip_active;
    wire [10:0] x;
    wire [9:0] y;
    wire [7:0] frame_count;
    wire [2:0] demo_phase;
    wire [8:0] demo_step;
    wire [1:0] active_effect_mode;

    integer frame_edges = 0;
    integer active_pixels = 0;
    integer pip_pixels = 0;
    integer bg_pixels = 0;
    integer hsync_low = 0;
    integer vsync_low = 0;
    integer cycle_count = 0;
    reg saw_background_panel = 1'b0;
    reg saw_phase0_hidden = 1'b0;
    reg saw_phase1_static_pip = 1'b0;
    reg saw_phase2_moving_pip = 1'b0;
    reg saw_phase3_rotate = 1'b0;
    reg saw_phase4_scale = 1'b0;
    reg saw_phase5_combo = 1'b0;
    reg button_control_ok = 1'b0;
    wire [1:0] control_mode;
    wire control_pause;
    wire [1:0] control_key_pressed;

    always #20 pix_clk = ~pix_clk;

    video_pip_core #(
        .DEMO_FRAMES_PER_PHASE(5)
    ) dut (
        .pix_clk(pix_clk),
        .reset(reset),
        .effect_mode(effect_mode),
        .animation_pause(animation_pause),
        .rgb(rgb),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .pip_active(pip_active),
        .x(x),
        .y(y),
        .frame_count(frame_count),
        .demo_phase(demo_phase),
        .demo_step(demo_step),
        .active_effect_mode(active_effect_mode)
    );

    button_controls #(
        .DEBOUNCE_CYCLES(4)
    ) control_dut (
        .pix_clk(pix_clk),
        .reset(reset),
        .key_n(key_n),
        .effect_mode(control_mode),
        .animation_pause(control_pause),
        .key_pressed(control_key_pressed)
    );

    initial begin
        repeat (8) @(posedge pix_clk);
        reset = 1'b0;
    end

    initial begin
        wait (!reset);
        repeat (8) @(posedge pix_clk);
        key_n[0] = 1'b0;
        repeat (8) @(posedge pix_clk);
        key_n[0] = 1'b1;
        repeat (8) @(posedge pix_clk);
        key_n[1] = 1'b0;
        repeat (8) @(posedge pix_clk);
        key_n[1] = 1'b1;
        repeat (8) @(posedge pix_clk);
        if (control_mode == 2'd0 && control_pause == 1'b1) begin
            button_control_ok = 1'b1;
        end
    end

    always @(posedge pix_clk) begin
        cycle_count = cycle_count + 1;

        if (!reset) begin
            if (x == 0 && y == 0) begin
                if (frame_edges == 30) begin
                    if (active_pixels != 640 * 480 * 30) begin
                        $display("FAIL active_pixels=%0d", active_pixels);
                        $finish;
                    end
                    if (pip_pixels <= 160 * 120 * 4) begin
                        $display("FAIL too few pip_pixels=%0d", pip_pixels);
                        $finish;
                    end
                    if (pip_pixels >= active_pixels) begin
                        $display("FAIL too many pip_pixels=%0d", pip_pixels);
                        $finish;
                    end
                    if (bg_pixels <= 0) begin
                        $display("FAIL no background pixels");
                        $finish;
                    end
                    if (hsync_low != 96 * 525 * 30) begin
                        $display("FAIL hsync_low=%0d", hsync_low);
                        $finish;
                    end
                    if (vsync_low != 2 * 800 * 30) begin
                        $display("FAIL vsync_low=%0d", vsync_low);
                        $finish;
                    end
                    if (!saw_background_panel) begin
                        $display("FAIL stage1 background panel check did not hit");
                        $finish;
                    end
                    if (!saw_phase0_hidden) begin
                        $display("FAIL demo phase0 hidden check did not hit");
                        $finish;
                    end
                    if (!saw_phase1_static_pip) begin
                        $display("FAIL demo phase1 static PIP check did not hit");
                        $finish;
                    end
                    if (!saw_phase2_moving_pip) begin
                        $display("FAIL demo phase2 moving PIP check did not hit");
                        $finish;
                    end
                    if (!saw_phase3_rotate) begin
                        $display("FAIL demo phase3 rotate check did not hit");
                        $finish;
                    end
                    if (!saw_phase4_scale) begin
                        $display("FAIL demo phase4 scale check did not hit");
                        $finish;
                    end
                    if (!saw_phase5_combo) begin
                        $display("FAIL demo phase5 combo check did not hit");
                        $finish;
                    end
                    if (!button_control_ok) begin
                        $display("FAIL button control check did not hit mode=%0d pause=%0d",
                                 control_mode, control_pause);
                        $finish;
                    end

                    $display("STAGE1_TIMING_AND_PATTERN_OK active_pixels=%0d hsync_low=%0d vsync_low=%0d",
                             active_pixels, hsync_low, vsync_low);
                    $display("STAGE2_PIP_OK pip_pixels=%0d bg_pixels=%0d", pip_pixels, bg_pixels);
                    $display("STAGE3_EFFECT_PIPE_OK preset_modes=normal,move,rotate,scale,rotate_scale");
                    $display("STAGE4_BUTTON_CONTROL_OK key1=mode_cycle key2=pause_toggle");
                    $display("STAGE5_AUTO_DEMO_SCRIPT_OK phases=6 frames_per_phase=5 hardware_frames_per_phase=300");
                    $display("SIM_OK frames=%0d cycles=%0d", frame_edges, cycle_count);
                    $finish;
                end
                frame_edges = frame_edges + 1;
            end
            if (de) begin
                active_pixels = active_pixels + 1;
                if (pip_active) begin
                    pip_pixels = pip_pixels + 1;
                end else begin
                    bg_pixels = bg_pixels + 1;
                end
            end
            if (!hsync) begin
                hsync_low = hsync_low + 1;
            end
            if (!vsync) begin
                vsync_low = vsync_low + 1;
            end
            if (de && x == 11'd80 && y == 10'd80 && rgb == 24'h172a3a) begin
                saw_background_panel = 1'b1;
            end
            if (de && demo_phase == 3'd0 && x == 11'd106 && y == 10'd90 && !pip_active) begin
                saw_phase0_hidden = 1'b1;
            end
            if (de && demo_phase == 3'd1 && active_effect_mode == 2'd0 &&
                x == 11'd97 && y == 10'd80 && pip_active && rgb == 24'hffffff) begin
                saw_phase1_static_pip = 1'b1;
            end
            if (de && demo_phase == 3'd2 && demo_step == 9'd4 &&
                x == 11'd98 && y == 10'd80 && pip_active && rgb == 24'hffffff) begin
                saw_phase2_moving_pip = 1'b1;
            end
            if (de && demo_phase == 3'd3 && active_effect_mode == 2'd2 &&
                x == 11'd136 && y == 10'd88 && pip_active && rgb == 24'he53935) begin
                saw_phase3_rotate = 1'b1;
            end
            if (de && demo_phase == 3'd4 && active_effect_mode == 2'd1 &&
                x == 11'd118 && y == 10'd100 && pip_active && rgb == 24'he53935) begin
                saw_phase4_scale = 1'b1;
            end
            if (de && demo_phase == 3'd5 && active_effect_mode == 2'd3 &&
                (((demo_step == 9'd0) && x == 11'd324 && y == 10'd228) ||
                 ((demo_step == 9'd4) && x == 11'd325 && y == 10'd228)) &&
                pip_active && rgb == 24'he53935) begin
                saw_phase5_combo = 1'b1;
            end
        end

        if (cycle_count > 13000000) begin
            $display("FAIL timeout cycle_count=%0d frame_edges=%0d", cycle_count, frame_edges);
            $finish;
        end
    end
endmodule

`default_nettype wire
