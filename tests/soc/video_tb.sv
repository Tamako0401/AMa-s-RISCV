// 视频测试台: sw/app/video_demo 跑在 SoC 上, video_sink 从视频输出端口收画面, 核对背景、精灵、放大和时序。
// 结束判定同 lcd_tb: 程序准备好后写 tohost (RAM 0x1000_0000) = 1; 之后再收一整帧来核对。
`timescale 1ns / 1ps
module video_tb;
    parameter [31:0] TOHOST_ADDR = 32'h10000000;
    localparam W = 640, H = 480;

    reg clk = 0;
    always #10 clk = ~clk;  // 50 MHz, 和板子一样
    reg rst_n = 0;
    string rom_path, ram_path;
    reg seen = 0;

    `include "boards/mes50hp/pins_top.vh"
    wire [127:0] io_o, io_oe;
    wire [127:0] io_i = (128'd1 << `PIN_UART_RX);
    wire pclk, hsync_n, vsync_n, de;
    wire [23:0] rgb;
    soc_top #(
        .IO_N(`IO_N),
        .UART_TX_PIN(`PIN_UART_TX),
        .UART_RX_PIN(`PIN_UART_RX)
    ) u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .io_o(io_o),
        .io_oe(io_oe),
        .io_i(io_i),
        .video_pclk(pclk),
        .video_hsync_n(hsync_n),
        .video_vsync_n(vsync_n),
        .video_de(de),
        .video_rgb(rgb)
    );
    video_sink #(
        .W(W),
        .H(H)
    ) u_sink (
        .pclk(pclk),
        .hsync_n(hsync_n),
        .vsync_n(vsync_n),
        .de(de),
        .rgb(rgb)
    );

    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        $readmemh(rom_path, u_soc.u_rom.mem);
        if ($value$plusargs("ram=%s", ram_path)) $readmemh(ram_path, u_soc.u_ram.u_gen_ram.ram);
        repeat (5) @(negedge clk);
        rst_n = 1;
    end

    always @(posedge clk)
        if (rst_n && u_soc.u_core.dbus_req_valid_o && u_soc.u_core.dbus_req_ready_i && u_soc.u_core.dbus_we_o &&
            u_soc.u_core.dbus_addr_o == TOHOST_ADDR && u_soc.u_core.dbus_data_o == 1)
            seen <= 1;

    // 逻辑坐标 (x, y) 对应的 2x2 个物理像素都应该是 want
    integer bad = 0;
    task static expect_pixel(input integer x, input integer y, input logic [23:0] want, input logic [127:0] name);
        integer i;
        reg [23:0] got;
        begin
            for (i = 0; i < 4; i = i + 1) begin
                got = u_sink.fb[(2*y+i/2)*W+2*x+i%2];
                if (got !== want) begin
                    $display("    FAIL %0s: (%0d,%0d) 第 %0d 个物理像素 = %06h, 期望 %06h", name, x, y, i, got, want);
                    bad = bad + 1;
                    i = 4;
                end
            end
        end
    endtask

    localparam [23:0] SKY = 24'h000084, WALL = 24'hFFFFFF, RED = 24'hFF0000, YELLOW = 24'hFFFF00;

    initial begin
        integer frames;
        @(posedge seen);
        frames = u_sink.frames;
        wait (u_sink.frames == frames + 2);  // 写 tohost 之后完整的一帧

        if (u_sink.bad_lines != 0) begin
            $display("    FAIL 有 %0d 行的宽度不是 %0d", u_sink.bad_lines, W);
            bad = bad + 1;
        end
        expect_pixel(0, 0, WALL, "左上角白框");
        expect_pixel(319, 239, WALL, "右下角白框");
        expect_pixel(7, 100, WALL, "左框最内一列");
        expect_pixel(8, 100, SKY, "左框里面");
        expect_pixel(200, 60, SKY, "蓝底");
        // 静止的球在 (16,16)~(31,31): 中心里圈黄色, 外圈红色, 四角透明露出蓝底
        expect_pixel(24, 24, YELLOW, "球心");
        expect_pixel(24, 17, RED, "球上沿");
        expect_pixel(16, 16, SKY, "球的透明角");
        $display("[result] frames %0d", u_sink.frames);

        if (bad != 0) $fatal(1, "视频画面核对失败: %0d 项", bad);
        $display("PASS video: 640x480 输出, 背景 + 精灵核对通过");
        $finish;
    end

    initial begin
        #200000000;
        $fatal(1, "video_tb: 超时 (tohost=%0d, 已收 %0d 帧)", seen, u_sink.frames);
    end
endmodule
