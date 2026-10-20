`timescale 1ns / 1ps
module snake_tb;
    parameter integer W = 240;
    parameter integer H = 320;
    parameter integer BIT_CLKS = 434;

    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    reg uart_rx = 1;
    string rom_path;
    integer cycles = 0;
    integer bad = 0;
    integer initial_pixels;
    wire spi_mosi, spi_ss, spi_clk, lcd_dc, lcd_rst_n;

    `include "boards/mes50hp/pins_top.vh"
    wire [127:0] io_o, io_oe;
    wire [127:0] io_i = ({127'b0, uart_rx} << `PIN_UART_RX);
    assign {spi_clk, spi_mosi, spi_ss, lcd_dc, lcd_rst_n} = {
        io_o[`PIN_J8_27], io_o[`PIN_J8_28], io_o[`PIN_J8_23], io_o[`PIN_J8_26], io_o[`PIN_J8_25]
    };
    soc_top #(
        .IO_N(`IO_N),
        .UART_TX_PIN(`PIN_UART_TX),
        .UART_RX_PIN(`PIN_UART_RX)
    ) u_soc (
        .clk  (clk),
        .rst_n(rst_n),
        .io_o (io_o),
        .io_oe(io_oe),
        .io_i (io_i)
    );
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

    task static send_key(input logic [7:0] c);
        integer b;
        begin
            // 在下降沿改变输入, 避开 UART 的采样沿。
            @(negedge clk);
            uart_rx = 0;
            repeat (BIT_CLKS) @(negedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx = c[b];
                repeat (BIT_CLKS) @(negedge clk);
            end
            uart_rx = 1;
            repeat (BIT_CLKS) @(negedge clk);
        end
    endtask

    task static expect_cell(input integer x, input integer y, input logic [15:0] color);
        integer wrong, dx, dy;
        begin
            wrong = 0;
            for (dy = 0; dy < 10; dy = dy + 1)
            for (dx = 0; dx < 10; dx = dx + 1)
            if (u_panel.gram[(y*10+dy)*W+x*10+dx] !== color) wrong = wrong + 1;
            if (wrong != 0) begin
                $display("FAIL 格子 (%0d,%0d): %0d 个像素不等于 %04h", x, y, wrong, color);
                bad = bad + 1;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "FAIL Missing +rom=hex");
        $readmemh(rom_path, u_soc.u_rom.mem);
        repeat (5) @(negedge clk);
        rst_n = 1;

        wait (u_panel.pixels == W * H);
        send_key("d");
        // 等每个方块的最后一个像素, 避免把传输中的画面当成完整帧。
        while (u_panel.gram[169*W+129] !== 16'h07E0) @(negedge clk);
        expect_cell(10, 16, 16'h07E0);
        expect_cell(11, 16, 16'h07E0);
        expect_cell(12, 16, 16'h07E0);
        wait (u_panel.pixels == 2 * W * H + 400);
        initial_pixels = u_panel.pixels;
        while (u_panel.gram[169*W+159] !== 16'h07E0) @(negedge clk);
        expect_cell(15, 16, 16'h07E0);
        expect_cell(10, 16, 16'h0000);
        if (bad != 0) $fatal(1, "FAIL SNAKE: 右行画面核对失败");
        $display("PASS 右行三步: 蛇头 (15,16) 绿色, 原尾 (10,16) 黑色");

        send_key("s");
        while (u_panel.gram[189*W+159] !== 16'h07E0) @(negedge clk);
        expect_cell(15, 18, 16'h07E0);
        expect_cell(11, 16, 16'h0000);
        expect_cell(12, 16, 16'h0000);
        expect_cell(16, 16, 16'h0000);
        if (u_panel.colmod !== 32'h55 || u_panel.madctl !== 32'h00)
            $fatal(1, "FAIL 屏幕初始化参数错误");
        if (u_panel.pixels - initial_pixels > 1500)
            $fatal(1, "FAIL 移动时写入过多像素, 应只更新变化的格子");
        if (bad != 0) $fatal(1, "FAIL SNAKE: %0d 项画面核对失败", bad);
        u_panel.render();
        $display("PASS SNAKE: UART 115200 8N1 控制右行和下转, SPI 画面核对通过");
        $finish;
    end

    always @(posedge clk)
        if (rst_n) begin
            cycles <= cycles + 1;
            if (cycles == 30000000)
                $fatal(1, "FAIL snake_tb: 超时 (cycles=%0d, 像素=%0d)", cycles, u_panel.pixels);
        end
endmodule
