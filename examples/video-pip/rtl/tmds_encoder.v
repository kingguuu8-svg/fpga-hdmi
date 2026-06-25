`timescale 1ns/1ps
`default_nettype none

module tmds_encoder (
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] din,
    input  wire       c0,
    input  wire       c1,
    input  wire       de,
    output reg  [9:0] dout
);

    function [3:0] count_ones8;
        input [7:0] value;
        integer i;
        begin
            count_ones8 = 4'd0;
            for (i = 0; i < 8; i = i + 1) begin
                count_ones8 = count_ones8 + value[i];
            end
        end
    endfunction

    wire [3:0] ones_d = count_ones8(din);
    wire use_xnor = (ones_d > 4) || ((ones_d == 4) && (din[0] == 1'b0));

    reg [8:0] q_m;
    integer bit_index;

    always @* begin
        q_m[0] = din[0];
        for (bit_index = 1; bit_index < 8; bit_index = bit_index + 1) begin
            q_m[bit_index] = use_xnor ?
                ~(q_m[bit_index - 1] ^ din[bit_index]) :
                 (q_m[bit_index - 1] ^ din[bit_index]);
        end
        q_m[8] = ~use_xnor;
    end

    wire [3:0] ones_qm = count_ones8(q_m[7:0]);
    wire signed [4:0] balance = $signed({1'b0, ones_qm}) -
                                $signed({1'b0, (4'd8 - ones_qm)});
    reg signed [4:0] disparity;

    always @(posedge clk) begin
        if (reset) begin
            dout <= 10'b1101010100;
            disparity <= 5'sd0;
        end else if (!de) begin
            disparity <= 5'sd0;
            case ({c1, c0})
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                default: dout <= 10'b1010101011;
            endcase
        end else if ((disparity == 0) || (balance == 0)) begin
            if (q_m[8]) begin
                dout <= {2'b01, q_m[7:0]};
                disparity <= disparity + balance;
            end else begin
                dout <= {2'b10, ~q_m[7:0]};
                disparity <= disparity - balance;
            end
        end else if (((disparity > 0) && (balance > 0)) ||
                     ((disparity < 0) && (balance < 0))) begin
            dout <= {1'b1, q_m[8], ~q_m[7:0]};
            disparity <= disparity + $signed({3'b000, q_m[8], 1'b0}) - balance;
        end else begin
            dout <= {1'b0, q_m[8], q_m[7:0]};
            disparity <= disparity - $signed({3'b000, ~q_m[8], 1'b0}) + balance;
        end
    end

endmodule

`default_nettype wire
