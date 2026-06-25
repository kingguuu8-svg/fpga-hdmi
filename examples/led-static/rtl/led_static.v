`default_nettype none

module led_static #(
    parameter integer LED_COUNT = 1,
    parameter integer ACTIVE_LOW = 0
) (
    output wire [LED_COUNT-1:0] led
);

    wire [LED_COUNT-1:0] on_value = {LED_COUNT{1'b1}};
    assign led = ACTIVE_LOW ? ~on_value : on_value;

endmodule

`default_nettype wire
