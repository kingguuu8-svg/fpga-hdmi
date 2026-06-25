`default_nettype none

module led_chaser #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer STEP_HZ = 4,
    parameter integer LED_COUNT = 4,
    parameter integer ACTIVE_LOW = 0
) (
    input  wire                 clk,
    output wire [LED_COUNT-1:0] led
);

    localparam integer DIVISOR = CLK_HZ / STEP_HZ;
    localparam integer COUNTER_WIDTH = $clog2(DIVISOR);

    reg [COUNTER_WIDTH-1:0] counter = {COUNTER_WIDTH{1'b0}};
    reg [LED_COUNT-1:0] pattern = {{(LED_COUNT-1){1'b0}}, 1'b1};

    always @(posedge clk) begin
        if (counter == DIVISOR - 1) begin
            counter <= {COUNTER_WIDTH{1'b0}};
            pattern <= {pattern[LED_COUNT-2:0], pattern[LED_COUNT-1]};
        end else begin
            counter <= counter + 1'b1;
        end
    end

    assign led = ACTIVE_LOW ? ~pattern : pattern;

endmodule

`default_nettype wire

