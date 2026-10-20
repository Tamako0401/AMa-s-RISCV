// LCD 点亮测试台: 让真实的 C 程序 (sw/app/ 下的程序) 跑在 RTL SoC 上,
// 由 st7789_model 从真实引脚重建画面, 最后打印 ASCII 图并核对关键像素。
//
// 与 tests/soc/soc_tb.sv 的分工: soc_tb 用汇编小程序验总线互连, 这里跑真正的
// 屏幕驱动软件, 验的是"能不能点亮一块屏"。
//
// 结束判定: 向 RAM 窗口第 0 个字 0x1000_0000 写 1 —— sw/link.ld 把 .tohost 放在
// 那里, 程序结束前写 tohost = 1。
`timescale 1ns / 1ps
module lcd_tb;
    parameter [31:0] TOHOST_ADDR = 32'h10000000;
    parameter integer W = 240;
    parameter integer H = 320;

    reg clk = 0;
    always #5 clk = ~clk;  // 100 MHz 仿真时钟
    reg rst_n = 0;

    string rom_path, ram_path;
    integer unused;
    integer cycles = 0;
    reg seen = 0;
    reg [31:0] result;

    // 层次化引用核的数据总线, 只用于观察"程序什么时候写完 tohost"
    wire [31:0] da, dw;
    wire [3:0] dsel;
    wire dwe, dv, dr;
    assign da   = u_soc.u_core.dbus_addr_o;
    assign dw   = u_soc.u_core.dbus_data_o;
    assign dsel = u_soc.u_core.dbus_sel_o;
    assign dwe  = u_soc.u_core.dbus_we_o;
    assign dv   = u_soc.u_core.dbus_req_valid_o;
    assign dr   = u_soc.u_core.dbus_req_ready_i;

    // SoC 的屏幕引脚, 显式连出来再送给面板模型
    wire spi_mosi, spi_ss, spi_clk, lcd_dc, lcd_rst_n;

    `include "boards/mes50hp/pins_top.vh"
    wire [127:0] io_o, io_oe;
    wire [127:0] io_i = {69'b0, 1'b1, 58'b0};
    assign {spi_clk, spi_mosi, spi_ss, lcd_dc, lcd_rst_n} = {
        io_o[24], io_o[25], io_o[20], io_o[23], io_o[22]
    };
    soc_top #(
        .IO_N(`IO_N),
        .UART_TX_PIN(`UART_TX_PIN),
        .UART_RX_PIN(`UART_RX_PIN)
    ) u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .io_o(io_o),
        .io_oe(io_oe),
        .io_i(io_i),
        .uart_rx(1'b1),
        .uart_tx(),
        .led(),
        .spi_mosi(),
        .spi_miso(1'b0),
        .spi_ss(),
        .spi_clk(),
        .lcd_dc(),
        .lcd_rst_n()
    );
    // 面板模型接在真实引脚上
    st7789_model #(
        .W(W),
        .H(H)
    ) u_panel (
        .rst_n(lcd_rst_n),
        .cs_n(spi_ss),
        .dc(lcd_dc),
        .sck(spi_clk),
        .mosi(spi_mosi)
    );

    // 统计 SCK 边沿, 作为"确实有数据流过"的旁证
    integer sck_edges = 0;
    always @(spi_clk) if (rst_n && !seen) sck_edges = sck_edges + 1;

    // 检查: 读 GRAM 的某个像素
    reg [15:0] px;
    integer bad = 0;
    task expect_pixel(input integer x, input integer y, input [15:0] want, input [127:0] name);
        begin
            px = u_panel.gram[y*W+x];
            if (px !== want) begin
                $display("    FAIL %0s: (%0d,%0d) = %04h, 期望 %04h", name, x, y, px, want);
                bad = bad + 1;
            end
        end
    endtask

    // 对角线是 Bresenham 画出来的, 精确 x 依赖算法; 在附近几列里找一个绿点
    task expect_diagonal(input integer y);
        integer x, hit;
        begin
            hit = 0;
            for (x = 0; x < W; x = x + 1) if (u_panel.gram[y*W+x] == 16'h07E0) hit = hit + 1;
            if (hit != 1) begin
                $display("    FAIL 对角线: y=%0d 找到 %0d 个绿点 (期望 1)", y, hit);
                bad = bad + 1;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        $readmemh(rom_path, u_soc.u_rom.mem);
        if ($value$plusargs("ram=%s", ram_path)) $readmemh(ram_path, u_soc.u_ram.u_gen_ram.ram);
        repeat (5) @(negedge clk);
        rst_n = 1;
    end

    // 等程序写完 tohost。每 50 万拍报一次进度, 这样"跑得慢"和"卡住了"一眼可分。
    always @(posedge clk)
        if (rst_n && !seen) begin
            cycles <= cycles + 1;
            if (cycles % 500000 == 0)
                $display(
                    "    [%0t ns] 周期 %0d, SCK 边沿 %0d, 命令 %0d, 像素 %0d",
                    $time,
                    cycles,
                    sck_edges,
                    u_panel.cmd_cnt,
                    u_panel.pixels
                );
            if (cycles == 4000000 && u_panel.cmd_cnt == 0)
                $fatal(1, "400 万拍内屏幕一条命令都没收到, 检查复位/CS/SCK");
            if (dv && dr && dwe && da == TOHOST_ADDR) begin
                result <= dw;
                seen   <= 1;
            end
        end

    // 完成后: 等 SPI 把最后一个字节移出去, 再渲染并核对
    initial begin
        integer i, j;
        @(posedge seen);
        repeat (2000) @(posedge clk);  // 冲刷最后一个字节

        if (result !== 32'h1) $fatal(1, "程序返回 %h, 期望 1", result);

        $display("");
        $display("======== st7789_model 从引脚重建的画面 ========");
        $display("  时钟周期 %0d, SCK 边沿 %0d, 命令 %0d 条, 数据 %0d 字节", cycles,
                 sck_edges, u_panel.cmd_cnt, u_panel.data_cnt);
        $display("  COLMOD 0x3A = %02h (期望 55 = RGB565), MADCTL 0x36 = %02h", u_panel.colmod,
                 u_panel.madctl);
        $display("  RAMWR 进入 %0d 次, 累计写入 %0d 像素 (一屏 %0d)", u_panel.ramwr_cnt,
                 u_panel.pixels, W * H);
        u_panel.render();

        // 初始化命令必须都发过
        if (u_panel.colmod !== 8'h55) begin
            $display("    FAIL COLMOD = %02h, 期望 55", u_panel.colmod);
            bad = bad + 1;
        end
        if (u_panel.madctl !== 8'h00) begin
            $display("    FAIL MADCTL = %02h, 期望 00", u_panel.madctl);
            bad = bad + 1;
        end
        if (u_panel.pixels < W * H) begin
            $display("    FAIL 只写了 %0d 像素, 一屏是 %0d", u_panel.pixels, W * H);
            bad = bad + 1;
        end

        // selftest: 黑底 + 白边框 + 绿对角线 + 红/绿/蓝三个色块
        expect_pixel(120, 0, 16'hFFFF, "上边框");
        expect_pixel(120, 319, 16'hFFFF, "下边框");
        expect_pixel(0, 160, 16'hFFFF, "左边框");
        expect_pixel(239, 160, 16'hFFFF, "右边框");
        expect_pixel(40, 40, 16'hF800, "红色块");
        expect_pixel(120, 40, 16'h07E0, "绿色块");
        expect_pixel(200, 40, 16'h001F, "蓝色块");
        expect_pixel(10, 300, 16'h0000, "黑底");
        expect_diagonal(160);

        if (bad != 0) $fatal(1, "LCD 画面核对失败: %0d 项", bad);
        $display("");
        $display(
            "PASS LCD: 微控制器经 RIB 驱动 SPI 点亮 %0dx%0d 屏幕, 画面核对通过",
            W, H);
        $finish;
    end

    // 兜底超时: 仿真里延时已按 SIM_CYCLE_DIV 缩短, 画一屏约几百万拍
    initial begin
        #200000000;
        $fatal(1, "lcd_tb: 全局超时 (cycles=%0d, 命令=%0d, 像素=%0d)", cycles,
               u_panel.cmd_cnt, u_panel.pixels);
    end
endmodule
