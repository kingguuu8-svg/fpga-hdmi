`timescale 1ns/1ps
`default_nettype none

module video_timing_640x480 (
    input  wire        pix_clk,
    input  wire        reset,
    output reg  [10:0] x,
    output reg  [9:0]  y,
    output wire        active,
    output wire        hsync,
    output wire        vsync,
    output wire        frame_start,
    output wire        line_start
);

    localparam integer H_ACTIVE = 640;
    localparam integer H_FRONT  = 16;
    localparam integer H_SYNC   = 96;
    localparam integer H_BACK   = 48;
    localparam integer H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam integer V_ACTIVE = 480;
    localparam integer V_FRONT  = 10;
    localparam integer V_SYNC   = 2;
    localparam integer V_BACK   = 33;
    localparam integer V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    always @(posedge pix_clk) begin
        if (reset) begin
            x <= 11'd0;
            y <= 10'd0;
        end else if (x == H_TOTAL - 1) begin
            x <= 11'd0;
            if (y == V_TOTAL - 1) begin
                y <= 10'd0;
            end else begin
                y <= y + 10'd1;
            end
        end else begin
            x <= x + 11'd1;
        end
    end

    assign active = (x < H_ACTIVE) && (y < V_ACTIVE);
    assign hsync = ~((x >= H_ACTIVE + H_FRONT) &&
                     (x <  H_ACTIVE + H_FRONT + H_SYNC));
    assign vsync = ~((y >= V_ACTIVE + V_FRONT) &&
                     (y <  V_ACTIVE + V_FRONT + V_SYNC));
    assign frame_start = (x == 0) && (y == 0);
    assign line_start = (x == 0);

endmodule

`default_nettype wire
