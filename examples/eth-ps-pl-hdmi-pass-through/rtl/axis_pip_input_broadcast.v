`timescale 1ns/1ps
`default_nettype none

// Duplicate one AXI4-Stream frame into the main and PIP consumers. Each
// consumer may complete the transfer independently, but the next source word
// is not accepted until both copies have been consumed.
module axis_pip_input_broadcast (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXIS:M_MAIN:M_PIP, ASSOCIATED_RESET aresetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    input  wire        aclk,
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    input  wire        aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [23:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire        s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire        s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input  wire        s_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TUSER" *)
    input  wire        s_axis_tuser,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_MAIN TDATA" *)
    output wire [23:0] m_main_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_MAIN TVALID" *)
    output wire        m_main_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_MAIN TREADY" *)
    input  wire        m_main_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_MAIN TLAST" *)
    output wire        m_main_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_MAIN TUSER" *)
    output wire        m_main_tuser,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_PIP TDATA" *)
    output wire [23:0] m_pip_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_PIP TVALID" *)
    output wire        m_pip_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_PIP TREADY" *)
    input  wire        m_pip_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_PIP TLAST" *)
    output wire        m_pip_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_PIP TUSER" *)
    output wire        m_pip_tuser
);

    reg        hold_valid;
    reg        main_sent;
    reg        pip_sent;
    reg [23:0] hold_data;
    reg        hold_tlast;
    reg        hold_tuser;

    wire main_fire = m_main_tvalid && m_main_tready;
    wire pip_fire = m_pip_tvalid && m_pip_tready;
    wire source_fire = s_axis_tvalid && s_axis_tready;

    assign s_axis_tready = !hold_valid;
    assign m_main_tdata = hold_data;
    assign m_main_tvalid = hold_valid && !main_sent;
    assign m_main_tlast = hold_tlast;
    assign m_main_tuser = hold_tuser;
    assign m_pip_tdata = hold_data;
    assign m_pip_tvalid = hold_valid && !pip_sent;
    assign m_pip_tlast = hold_tlast;
    assign m_pip_tuser = hold_tuser;

    always @(posedge aclk) begin
        if (!aresetn) begin
            hold_valid <= 1'b0;
            main_sent <= 1'b0;
            pip_sent <= 1'b0;
            hold_data <= 24'd0;
            hold_tlast <= 1'b0;
            hold_tuser <= 1'b0;
        end else begin
            if (source_fire) begin
                hold_valid <= 1'b1;
                main_sent <= 1'b0;
                pip_sent <= 1'b0;
                hold_data <= s_axis_tdata;
                hold_tlast <= s_axis_tlast;
                hold_tuser <= s_axis_tuser;
            end else if (hold_valid) begin
                if (main_fire) begin
                    main_sent <= 1'b1;
                end
                if (pip_fire) begin
                    pip_sent <= 1'b1;
                end
                if ((main_sent || main_fire) && (pip_sent || pip_fire)) begin
                    hold_valid <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
