`timescale 1ns/1ps
`default_nettype none

module button_controls #(
    parameter integer DEBOUNCE_CYCLES = 125000
) (
    input  wire       pix_clk,
    input  wire       reset,
    input  wire [1:0] key_n,
    output reg  [1:0] effect_mode,
    output reg        animation_pause,
    output wire [1:0] key_pressed
);

    reg [1:0] sync_0 = 2'b11;
    reg [1:0] sync_1 = 2'b11;
    reg [1:0] stable_n = 2'b11;
    reg [1:0] last_pressed = 2'b00;
    reg [17:0] count0 = 18'd0;
    reg [17:0] count1 = 18'd0;

    wire [1:0] pressed = ~stable_n;
    assign key_pressed = pressed;

    wire key0_rise = pressed[0] && !last_pressed[0];
    wire key1_rise = pressed[1] && !last_pressed[1];

    always @(posedge pix_clk) begin
        if (reset) begin
            sync_0 <= 2'b11;
            sync_1 <= 2'b11;
            stable_n <= 2'b11;
            last_pressed <= 2'b00;
            count0 <= 18'd0;
            count1 <= 18'd0;
            effect_mode <= 2'd3;
            animation_pause <= 1'b0;
        end else begin
            sync_0 <= key_n;
            sync_1 <= sync_0;

            if (sync_1[0] == stable_n[0]) begin
                count0 <= 18'd0;
            end else if (count0 == DEBOUNCE_CYCLES - 1) begin
                stable_n[0] <= sync_1[0];
                count0 <= 18'd0;
            end else begin
                count0 <= count0 + 18'd1;
            end

            if (sync_1[1] == stable_n[1]) begin
                count1 <= 18'd0;
            end else if (count1 == DEBOUNCE_CYCLES - 1) begin
                stable_n[1] <= sync_1[1];
                count1 <= 18'd0;
            end else begin
                count1 <= count1 + 18'd1;
            end

            if (key0_rise) begin
                effect_mode <= effect_mode + 2'd1;
            end
            if (key1_rise) begin
                animation_pause <= !animation_pause;
            end

            last_pressed <= pressed;
        end
    end

endmodule

`default_nettype wire
