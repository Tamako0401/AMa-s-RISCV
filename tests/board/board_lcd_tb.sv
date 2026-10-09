// MES50HP 板级 LCD 测试台: 真实板级固件 (sw/board/lcd_main.c) 跑在
// mes50hp_top -> minimal_soc 上, st7789_model 从真实顶层引脚重建画面并核对。
//
// 与 tests/soc/lcd_tb.sv 的分工: lcd_tb 验通用 RIB SoC, 这里验要上板的那套
// 系统(统一 RAM @ 0x80000000, SPI @ 0x40002000, GPIO 0/1/2 控屏, 8~15 控灯)。
//
// 程序镜像: 构建目录下的 sim.hex (scripts/build-board.py --lcd --simulate)。
// 结束判定: 向 0x8000F000 写 1 (lcd_main.c 的 TOHOST)。
`timescale 1ns/1ps
module board_lcd_tb;
    parameter [31:0] TOHOST_ADDR = 32'h8000F000;
    parameter integer W = 240;
    parameter integer H = 320;

    reg clk = 0;
    always #10 clk = ~clk;               // 物理 50 MHz
    reg key1_n = 1;

    wire uart_tx;
    wire [7:0] led;
    wire lcd_sck, lcd_mosi, lcd_cs, lcd_dc, lcd_rst_n, lcd_bl;

    // Parameter override at instantiation: Verilator rejects hierarchical
    // defparam (dut.soc.MEM_FILE), Icarus accepts both forms.
    mes50hp_top #(.MEM_FILE("sim.hex")) dut(
        .clk(clk), .key1_n(key1_n),
        .uart_rx(1'b1), .uart_tx(uart_tx),
        .led(led),
        .lcd_sck(lcd_sck), .lcd_mosi(lcd_mosi), .lcd_cs(lcd_cs),
        .lcd_dc(lcd_dc), .lcd_rst_n(lcd_rst_n), .lcd_bl(lcd_bl)
    );

    // 面板模型接在真实顶层引脚上
    st7789_model #(.W(W), .H(H)) u_panel(
        .rst_n(lcd_rst_n),
        .cs_n(lcd_cs),
        .dc(lcd_dc),
        .sck(lcd_sck),
        .mosi(lcd_mosi)
    );

    // 层次化引用核的数据总线, 只用于观察"程序什么时候写完 tohost"
    wire [31:0] da, dw;
    wire        dwe, dv, dr;
    assign da  = dut.soc.cpu.dbus_addr_o;
    assign dw  = dut.soc.cpu.dbus_data_o;
    assign dwe = dut.soc.cpu.dbus_we_o;
    assign dv  = dut.soc.cpu.dbus_req_valid_o;
    assign dr  = dut.soc.cpu.dbus_req_ready_i;

    integer cycles = 0;
    reg seen = 0;
    reg [31:0] result;
    integer sck_edges = 0;

    always @ (lcd_sck) if (dut.soc.rst_n && !seen) sck_edges = sck_edges + 1;

    // 每 50 万拍报一次进度, "跑得慢"和"卡住了"一眼可分
    always @ (posedge clk) if (dut.soc.rst_n && !seen) begin
        cycles <= cycles + 1;
        if (cycles % 500000 == 0)
            $display("    [%0t ns] 周期 %0d, SCK 边沿 %0d, 命令 %0d, 像素 %0d",
                     $time, cycles, sck_edges, u_panel.cmd_cnt, u_panel.pixels);
        if (cycles == 4000000 && u_panel.cmd_cnt == 0)
            $fatal(1, "400 万拍内屏幕一条命令都没收到, 检查复位/CS/SCK");
        if (dv && dr && dwe && da == TOHOST_ADDR) begin
            result <= dw;
            seen <= 1;
        end
    end

    // 检查: 读 GRAM 的某个像素
    reg [15:0] px;
    integer bad = 0;
    task expect_pixel(input integer x, input integer y, input [15:0] want,
                      input [127:0] name);
        begin
            px = u_panel.gram[y*W + x];
            if (px !== want) begin
                $display("    FAIL %0s: (%0d,%0d) = %04h, 期望 %04h",
                         name, x, y, px, want);
                bad = bad + 1;
            end
        end
    endtask

    // 对角线是 Bresenham 画出来的, 精确 x 依赖算法; 在附近几列里找一个绿点
    task expect_diagonal(input integer y);
        integer x, hit;
        begin
            hit = 0;
            for (x = 0; x < W; x = x + 1)
                if (u_panel.gram[y*W + x] == 16'h07E0) hit = hit + 1;
            if (hit != 1) begin
                $display("    FAIL 对角线: y=%0d 找到 %0d 个绿点 (期望 1)", y, hit);
                bad = bad + 1;
            end
        end
    endtask

    // 完成后: 等 SPI 把最后一个字节移出去, 再渲染并核对
    initial begin
        @(posedge seen);
        repeat (2000) @(posedge clk);      // 冲刷最后一个字节

        if (result !== 32'h1) $fatal(1, "程序返回 %h, 期望 1", result);

        $display("");
        $display("======== st7789_model 从引脚重建的画面 (MES50HP 顶层) ========");
        $display("  时钟周期 %0d, SCK 边沿 %0d, 命令 %0d 条, 数据 %0d 字节",
                 cycles, sck_edges, u_panel.cmd_cnt, u_panel.data_cnt);
        $display("  COLMOD 0x3A = %02h (期望 55 = RGB565), MADCTL 0x36 = %02h",
                 u_panel.colmod, u_panel.madctl);
        $display("  RAMWR 进入 %0d 次, 累计写入 %0d 像素 (一屏 %0d)",
                 u_panel.ramwr_cnt, u_panel.pixels, W*H);
        u_panel.render();

        if (u_panel.colmod !== 8'h55) begin
            $display("    FAIL COLMOD = %02h, 期望 55", u_panel.colmod);
            bad = bad + 1;
        end
        if (u_panel.madctl !== 8'h00) begin
            $display("    FAIL MADCTL = %02h, 期望 00", u_panel.madctl);
            bad = bad + 1;
        end
        if (u_panel.pixels < W*H) begin
            $display("    FAIL 只写了 %0d 像素, 一屏是 %0d", u_panel.pixels, W*H);
            bad = bad + 1;
        end

        // lcd_main: 黑底 + 白边框 + 绿对角线 + 红/绿/蓝三个色块
        expect_pixel(120,   0, 16'hFFFF, "上边框");
        expect_pixel(120, 319, 16'hFFFF, "下边框");
        expect_pixel(  0, 160, 16'hFFFF, "左边框");
        expect_pixel(239, 160, 16'hFFFF, "右边框");
        expect_pixel( 40,  40, 16'hF800, "红色块");
        expect_pixel(120,  40, 16'h07E0, "绿色块");
        expect_pixel(200,  40, 16'h001F, "蓝色块");
        expect_pixel( 10, 300, 16'h0000, "黑底");
        expect_diagonal(160);

        if (bad != 0) $fatal(1, "LCD 画面核对失败: %0d 项", bad);
        $display("");
        $display("PASS board LCD: mes50hp_top 经 SPI 点亮 %0dx%0d 屏幕, 画面核对通过",
                 W, H);
        $finish;
    end

    // 仿真里初始化延时已按 SIM_CYCLE_DIV=1000 缩短; 画一屏约几百万拍
    initial begin
        #400000000;
        $fatal(1, "board_lcd_tb: 全局超时 (cycles=%0d, 命令=%0d, 像素=%0d)",
               cycles, u_panel.cmd_cnt, u_panel.pixels);
    end
endmodule
