`timescale 1ns / 1ps
module ov7670_vga_tb;
    reg sys_clk = 0;
    reg rst_n = 1;
    reg cam_pclk = 0;
    reg cam_vsync = 1;
    reg cam_href = 0;
    reg [7:0] cam_data = 0;
    wire cam_xclk;
    wire hdmi_pclk, hdmi_hs, hdmi_vs, hdmi_de;
    wire [23:0] hdmi_rgb;

    always #10 sys_clk = ~sys_clk;
    always #20 cam_pclk = ~cam_pclk;

    ov7670_vga #(
        .CAM_W(8), .CAM_H(4), .SAMPLE_DIV(2),
        .H_ACTIVE(8), .V_ACTIVE(4), .H_TOTAL(12), .V_TOTAL(8),
        .H_SYNC_START(9), .H_SYNC_END(11),
        .V_SYNC_START(6), .V_SYNC_END(7)
    ) dut (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .cam_pclk(cam_pclk),
        .cam_vsync(cam_vsync),
        .cam_href(cam_href),
        .cam_data(cam_data),
        .cam_xclk(cam_xclk),
        .hdmi_pclk(hdmi_pclk),
        .hdmi_hs(hdmi_hs),
        .hdmi_vs(hdmi_vs),
        .hdmi_de(hdmi_de),
        .hdmi_rgb(hdmi_rgb)
    );

    task automatic send_byte(input [7:0] value);
        begin
            @(negedge cam_pclk);
            cam_data = value;
        end
    endtask

    task automatic send_line(input [15:0] color);
        integer i;
        begin
            @(negedge cam_pclk);
            cam_href = 1'b1;
            cam_data = color[15:8];
            for (i = 0; i < 8; i++) begin
                send_byte(color[7:0]);
                if (i != 7) send_byte(color[15:8]);
            end
            @(negedge cam_pclk);
            cam_href = 1'b0;
            repeat (3) @(negedge cam_pclk);
        end
    endtask

    task automatic check_row(input integer row, input [23:0] color);
        integer x;
        reg [23:0] expected;
        begin
            wait (dut.v == row && dut.h == 1);
            #1;
            for (x = 0; x < 8; x++) begin
                expected = x < 4 ? color : 24'b0;
                if (!hdmi_de || hdmi_rgb !== expected)
                    $fatal(1, "output (%0d,%0d) de=%b rgb=%06h expected %06h",
                        x, row, hdmi_de, hdmi_rgb, expected);
                if (x != 7) begin
                    @(posedge dut.pixel_clk);
                    #1;
                end
            end
        end
    endtask

    task automatic check_test_pattern_row;
        integer x;
        reg [23:0] color;
        begin
            wait (dut.v == 0 && dut.h == 1);
            #1;
            for (x = 0; x < 8; x++) begin
                case (x)
                    0: color = 24'hFFFFFF;
                    1: color = 24'hFFFF00;
                    2: color = 24'h00FFFF;
                    3: color = 24'h00FF00;
                    4: color = 24'hFF00FF;
                    5: color = 24'hFF0000;
                    6: color = 24'h0000FF;
                    default: color = 24'h000000;
                endcase
                if (x >= 4)
                    color = 24'h000000;
                if (!hdmi_de || hdmi_rgb !== color)
                    $fatal(1, "test pattern x=%0d de=%b rgb=%06h expected %06h",
                        x, hdmi_de, hdmi_rgb, color);
                if (x != 7) begin
                    @(posedge dut.pixel_clk);
                    #1;
                end
            end
        end
    endtask

    initial begin
        #1 rst_n = 1'b0;
        repeat (6) @(negedge sys_clk);
        rst_n = 1;
        wait (dut.pixel_rst_n);
        check_test_pattern_row();
        check_row(3, 24'h000000);
        repeat (6) @(negedge cam_pclk);
        cam_vsync = 1'b0;
        send_line(16'hF800);
        send_line(16'h07E0);
        send_line(16'h001F);
        send_line(16'hFFFF);
        wait (dut.frame_ready);
        repeat (4) @(negedge sys_clk);

        if (dut.u_framebuffer.mem[0] !== 16'hF800)
            $fatal(1, "first framebuffer pixel wrong: %04h", dut.u_framebuffer.mem[0]);
        if (dut.u_framebuffer.mem[4] !== 16'h001F)
            $fatal(1, "third source line was not sampled: %04h", dut.u_framebuffer.mem[4]);

        check_row(0, 24'hFF0000);
        check_row(1, 24'h0000FF);
        check_row(2, 24'h000000);
        check_row(3, 24'h000000);
        if (hdmi_pclk !== ~dut.pixel_clk)
            $fatal(1, "HDMI pixel clock polarity mismatch");

        $display("[result] VGA color-bar fallback, OV7670 frame capture and live HDMI scanout");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "OV7670 VGA test timed out");
    end
endmodule
