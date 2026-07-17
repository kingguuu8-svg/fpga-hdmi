`timescale 1ns/1ps
`default_nettype none

module tb_axis_pip_overlay_core;
    localparam integer FRAME_W = 32;
    localparam integer FRAME_H = 24;
    localparam integer PIP_X = 24;
    localparam integer PIP_Y = 19;
    localparam integer PIP_W = 8;
    localparam integer PIP_H = 6;
    localparam integer PIP_DEFAULT_W = 4;
    localparam integer PIP_DEFAULT_H = 3;
    localparam integer SCALE_X = 4;
    localparam integer SCALE_Y = 4;
    localparam integer BORDER = 1;
    localparam integer FRAME_PIXELS = FRAME_W * FRAME_H;
    localparam [31:0] CTRL_ENABLE = 32'h00000001;
    localparam [31:0] CTRL_BORDER = 32'h00000002;
    localparam [31:0] CTRL_SCALE_HALF = 32'h00000000;
    localparam [31:0] CTRL_SCALE_QUARTER = 32'h00000004;
    localparam [31:0] CTRL_EFFECT_NORMAL = 32'h00000000;
    localparam [31:0] CTRL_EFFECT_INVERT = 32'h00000010;
    localparam [31:0] CTRL_EFFECT_GRAYSCALE = 32'h00000020;

    reg aclk = 1'b0;
    reg aresetn = 1'b0;

    reg [23:0] s_main_tdata = 24'd0;
    reg        s_main_tvalid = 1'b0;
    wire       s_main_tready;
    reg        s_main_tlast = 1'b0;
    reg        s_main_tuser = 1'b0;

    reg [23:0] s_pip_tdata = 24'd0;
    reg        s_pip_tvalid = 1'b0;
    wire       s_pip_tready;
    reg        s_pip_tlast = 1'b0;
    reg        s_pip_tuser = 1'b0;

    wire [23:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready = 1'b1;
    wire        m_axis_tlast;
    wire        m_axis_tuser;
    wire [31:0] status_main_frames;
    wire [31:0] status_pip_frames;
    wire [31:0] status_overlay_pixels;

    reg  [5:0]  s_axi_awaddr = 6'd0;
    reg         s_axi_awvalid = 1'b0;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata = 32'd0;
    reg  [3:0]  s_axi_wstrb = 4'hf;
    reg         s_axi_wvalid = 1'b0;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready = 1'b1;
    reg  [5:0]  s_axi_araddr = 6'd0;
    reg         s_axi_arvalid = 1'b0;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready = 1'b1;

    integer x;
    integer y;
    integer overlay_pixels = 0;
    integer border_pixels = 0;
    integer pip_content_pixels = 0;
    integer main_pixels = 0;
    integer expected_count = 0;
    integer checked_count = 0;
    integer expected_pip_x = PIP_X;
    integer expected_pip_y = PIP_Y;
    integer expected_pip_w = PIP_DEFAULT_W;
    integer expected_pip_h = PIP_DEFAULT_H;
    integer expected_scale = 8;
    integer expected_enable = 1;
    integer expected_border = 1;
    integer expected_effect = 0;

    reg [23:0] expected_data [0:FRAME_PIXELS-1];
    reg        expected_last [0:FRAME_PIXELS-1];
    reg        expected_user [0:FRAME_PIXELS-1];

    always #5 aclk = ~aclk;

    axis_pip_overlay_core #(
        .FRAME_W(FRAME_W),
        .FRAME_H(FRAME_H),
        .PIP_X(PIP_X),
        .PIP_Y(PIP_Y),
        .PIP_W(PIP_W),
        .PIP_H(PIP_H),
        .SCALE_X(SCALE_X),
        .SCALE_Y(SCALE_Y),
        .BORDER(BORDER)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_main_tdata(s_main_tdata),
        .s_main_tvalid(s_main_tvalid),
        .s_main_tready(s_main_tready),
        .s_main_tlast(s_main_tlast),
        .s_main_tuser(s_main_tuser),
        .s_pip_tdata(s_pip_tdata),
        .s_pip_tvalid(s_pip_tvalid),
        .s_pip_tready(s_pip_tready),
        .s_pip_tlast(s_pip_tlast),
        .s_pip_tuser(s_pip_tuser),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .status_main_frames(status_main_frames),
        .status_pip_frames(status_pip_frames),
        .status_overlay_pixels(status_overlay_pixels)
    );

    function [23:0] main_pixel;
        input integer px;
        input integer py;
        begin
            main_pixel = {8'h10, px[7:0], py[7:0]};
        end
    endfunction

    function [23:0] pip_pixel;
        input integer px;
        input integer py;
        begin
            pip_pixel = {px[7:0], py[7:0], 8'h55};
        end
    endfunction

    function [23:0] apply_effect;
        input [23:0] pixel;
        reg [7:0] gray;
        begin
            if (expected_effect == 1) begin
                apply_effect = ~pixel;
            end else if (expected_effect == 2) begin
                gray = pixel[15:8];
                apply_effect = {gray, gray, gray};
            end else begin
                apply_effect = pixel;
            end
        end
    endfunction

    task axi_write;
        input [5:0] addr;
        input [31:0] data;
        begin
            @(negedge aclk);
            s_axi_awaddr = addr;
            s_axi_wdata = data;
            s_axi_awvalid = 1'b1;
            s_axi_wvalid = 1'b1;
            s_axi_wstrb = 4'hf;
            @(posedge aclk);
            while (!s_axi_bvalid) begin
                @(posedge aclk);
            end
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
        end
    endtask

    task queue_expected_main_pixel;
        input integer px;
        input integer py;
        reg [23:0] expected;
        integer local_x;
        integer local_y;
        begin
            expected = main_pixel(px, py);
            if (expected_enable &&
                px >= expected_pip_x && px < expected_pip_x + expected_pip_w &&
                py >= expected_pip_y && py < expected_pip_y + expected_pip_h) begin
                overlay_pixels = overlay_pixels + 1;
                local_x = px - expected_pip_x;
                local_y = py - expected_pip_y;
                if (expected_border &&
                    (local_x < BORDER || local_y < BORDER ||
                     local_x >= expected_pip_w - BORDER || local_y >= expected_pip_h - BORDER)) begin
                    expected = 24'hffffff;
                    border_pixels = border_pixels + 1;
                end else begin
                    expected = apply_effect(pip_pixel(local_x * expected_scale, local_y * expected_scale));
                    pip_content_pixels = pip_content_pixels + 1;
                end
            end else begin
                main_pixels = main_pixels + 1;
            end

            expected_data[expected_count] = expected;
            expected_last[expected_count] = (px == FRAME_W - 1);
            expected_user[expected_count] = (px == 0 && py == 0);
            expected_count = expected_count + 1;
        end
    endtask

    task check_output_if_valid;
        begin
            #1;
            if (m_axis_tvalid) begin
                if (checked_count >= expected_count) begin
                    $display("FAIL unexpected output checked=%0d expected=%0d",
                             checked_count, expected_count);
                    $finish;
                end
                if (m_axis_tdata !== expected_data[checked_count]) begin
                    $display("FAIL pixel mismatch index=%0d got=%06x expected=%06x",
                             checked_count, m_axis_tdata, expected_data[checked_count]);
                    $finish;
                end
                if (m_axis_tlast !== expected_last[checked_count]) begin
                    $display("FAIL tlast mismatch index=%0d", checked_count);
                    $finish;
                end
                if (m_axis_tuser !== expected_user[checked_count]) begin
                    $display("FAIL tuser mismatch index=%0d", checked_count);
                    $finish;
                end
                checked_count = checked_count + 1;
            end
        end
    endtask

    task send_pip_frame;
        begin
            for (y = 0; y < FRAME_H; y = y + 1) begin
                for (x = 0; x < FRAME_W; x = x + 1) begin
                    @(negedge aclk);
                    s_pip_tvalid = 1'b1;
                    s_pip_tdata = pip_pixel(x, y);
                    s_pip_tuser = (x == 0 && y == 0);
                    s_pip_tlast = (x == FRAME_W - 1);
                    @(posedge aclk);
                end
            end
            @(negedge aclk);
            s_pip_tvalid = 1'b0;
            s_pip_tuser = 1'b0;
            s_pip_tlast = 1'b0;
        end
    endtask

    task send_and_check_main_frame;
        begin
            overlay_pixels = 0;
            border_pixels = 0;
            pip_content_pixels = 0;
            main_pixels = 0;
            expected_count = 0;
            checked_count = 0;

            for (y = 0; y < FRAME_H; y = y + 1) begin
                for (x = 0; x < FRAME_W; x = x + 1) begin
                    @(negedge aclk);
                    s_main_tvalid = 1'b1;
                    s_main_tdata = main_pixel(x, y);
                    s_main_tuser = (x == 0 && y == 0);
                    s_main_tlast = (x == FRAME_W - 1);
                    queue_expected_main_pixel(x, y);
                    @(posedge aclk);
                    check_output_if_valid();
                end
            end
            @(negedge aclk);
            s_main_tvalid = 1'b0;
            s_main_tuser = 1'b0;
            s_main_tlast = 1'b0;

            while (checked_count < expected_count) begin
                @(posedge aclk);
                check_output_if_valid();
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        send_pip_frame();
        repeat (6) @(posedge aclk);
        if (status_pip_frames != 32'd1) begin
            $display("FAIL status_pip_frames=%0d", status_pip_frames);
            $finish;
        end
        send_and_check_main_frame();
        repeat (2) @(posedge aclk);
        if (overlay_pixels != PIP_DEFAULT_W * PIP_DEFAULT_H) begin
            $display("FAIL overlay_pixels=%0d", overlay_pixels);
            $finish;
        end
        if (border_pixels != 10) begin
            $display("FAIL border_pixels=%0d", border_pixels);
            $finish;
        end
        if (pip_content_pixels != 2) begin
            $display("FAIL pip_content_pixels=%0d", pip_content_pixels);
            $finish;
        end
        if (main_pixels != FRAME_W * FRAME_H - PIP_DEFAULT_W * PIP_DEFAULT_H) begin
            $display("FAIL main_pixels=%0d", main_pixels);
            $finish;
        end
        if (status_overlay_pixels != PIP_DEFAULT_W * PIP_DEFAULT_H) begin
            $display("FAIL status_overlay_pixels=%0d", status_overlay_pixels);
            $finish;
        end

        expected_enable = 0;
        axi_write(6'h00, CTRL_BORDER | CTRL_SCALE_QUARTER | CTRL_EFFECT_NORMAL);
        send_and_check_main_frame();
        if (overlay_pixels != 0 || main_pixels != FRAME_PIXELS) begin
            $display("FAIL bypass overlay=%0d main=%0d", overlay_pixels, main_pixels);
            $finish;
        end

        expected_enable = 1;
        expected_border = 0;
        expected_effect = 1;
        expected_scale = 4;
        expected_pip_x = 2;
        expected_pip_y = 2;
        expected_pip_w = PIP_W;
        expected_pip_h = PIP_H;
        axi_write(6'h04, 32'd2);
        axi_write(6'h08, 32'd2);
        axi_write(6'h00, CTRL_ENABLE | CTRL_SCALE_HALF | CTRL_EFFECT_INVERT);
        send_pip_frame();
        send_and_check_main_frame();
        if (overlay_pixels != PIP_W * PIP_H || border_pixels != 0 ||
            pip_content_pixels != PIP_W * PIP_H) begin
            $display("FAIL half invert overlay=%0d border=%0d pip=%0d",
                     overlay_pixels, border_pixels, pip_content_pixels);
            $finish;
        end

        expected_border = 1;
        expected_effect = 2;
        expected_scale = 8;
        expected_pip_x = PIP_X;
        expected_pip_y = PIP_Y;
        expected_pip_w = PIP_DEFAULT_W;
        expected_pip_h = PIP_DEFAULT_H;
        axi_write(6'h04, PIP_X);
        axi_write(6'h08, PIP_Y);
        axi_write(6'h00, CTRL_ENABLE | CTRL_BORDER | CTRL_SCALE_QUARTER | CTRL_EFFECT_GRAYSCALE);
        send_pip_frame();
        send_and_check_main_frame();
        if (overlay_pixels != PIP_DEFAULT_W * PIP_DEFAULT_H ||
            border_pixels != 10 || pip_content_pixels != 2) begin
            $display("FAIL grayscale quarter overlay=%0d border=%0d pip=%0d",
                     overlay_pixels, border_pixels, pip_content_pixels);
            $finish;
        end

        $display("PL_CONTROLLED_PIP_CORE_SIM_OK default_overlay=%0d half_overlay=%0d grayscale_overlay=%0d",
                 PIP_DEFAULT_W * PIP_DEFAULT_H, PIP_W * PIP_H, overlay_pixels);
        $display("PL_DUAL_VDMA_PIP_CORE_SIM_OK overlay_pixels=%0d border_pixels=%0d pip_content_pixels=%0d main_pixels=%0d",
                 overlay_pixels, border_pixels, pip_content_pixels, main_pixels);
        $display("SIM_OK");
        $finish;
    end

    initial begin
        repeat (10000) @(posedge aclk);
        $display("FAIL timeout");
        $finish;
    end
endmodule

`default_nettype wire
