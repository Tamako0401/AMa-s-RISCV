// CoreMark 仿真测试台: sw/app/coremark 跑在 rtl/soc_top 上, 把 UART 发出的字符原样打印。
//
// 时钟周期数与实机相同 (同一份 RTL, 存储都在片内), 所以这里算出的 CoreMark/MHz 就是实机值;
// 上板只是用真实主频跑满 CoreMark 规定的 10 秒。
// 结束判定: 程序在 portable_fini 里写 tohost (0x1000_0000) = 1。
`timescale 1ns / 1ps
module coremark_tb;
    parameter VIDEO_720P = 0;
    reg pixel_clk = 0;
    always #6.734006734 pixel_clk = ~pixel_clk;
    parameter [31:0] TOHOST_ADDR = 32'h10000000;
    parameter integer BIT_CLKS = 434;  // 50 MHz / 115200, 与 uart_init 算出的分频一致
    parameter integer MAX_CYCLES = 400000000;

    reg clk = 0;
    always #10 clk = ~clk;  // 50 MHz, 与板载时钟相同
    reg rst_n = 0;
    `include "boards/mes50hp/pins_top.vh"
    wire [127:0] io_o;
    wire uart_tx = io_o[`UART_TX_PIN];

    soc_top #(
        .VIDEO_720P(VIDEO_720P),        .IO_N(`IO_N),
        .UART_TX_PIN(`UART_TX_PIN),
        .UART_RX_PIN(`UART_RX_PIN)
    ) u_soc (
        .video_clk(pixel_clk),
        .clk  (clk),
        .rst_n(rst_n),
        .io_o (io_o),
        .io_oe(),
        .io_i (128'd1 << `UART_RX_PIN)
    );

    // 观察数据总线上对 tohost 的写
    wire [31:0] da = u_soc.u_core.dbus_addr_o;
    wire dwe = u_soc.u_core.dbus_we_o;
    wire dv = u_soc.u_core.dbus_req_valid_o;
    wire dr = u_soc.u_core.dbus_req_ready_i;
    reg done = 0;
    integer cycles = 0;
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (rst_n && dv && dr && dwe && da == TOHOST_ADDR) begin
            if (u_soc.u_core.dbus_data_o != 1) $fatal(1, "coremark: CRC or score failed");
            done <= 1;
        end
        if (cycles == MAX_CYCLES) $fatal(1, "coremark: timeout after %0d cycles", cycles);
    end

    // UART 接收: 起始位下降沿后等半个位到中点, 之后每 BIT_CLKS 拍采一位
    reg [7:0] ch;
    initial begin
        forever begin
            @(negedge uart_tx);
            repeat (BIT_CLKS / 2) @(posedge clk);
            for (integer b = 0; b < 8; b = b + 1) begin
                repeat (BIT_CLKS) @(posedge clk);
                ch[b] = uart_tx;
            end
            repeat (BIT_CLKS) @(posedge clk);
            if (uart_tx !== 1'b1) $fatal(1, "coremark: UART stop bit missing");
            if (ch != 8'h0d) $write("%c", ch);
            $fflush;
        end
    end

    reg [1023:0] rom_path;
    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        $readmemh(rom_path, u_soc.u_rom.mem);
        repeat (5) @(posedge clk);
        rst_n = 1;
        wait (done);
        repeat (BIT_CLKS * 12) @(posedge clk);  // 让最后一个字符发完
        $display("[coremark_tb] finished after %0d cycles", cycles);
        $finish;
    end
endmodule
