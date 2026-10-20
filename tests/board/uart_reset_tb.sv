// selftest 的首字节: 从上电开始监视引脚, 不跳过复位期间的低电平。
// EGO1 的 key1_n = S6 & locked; 暂停 50 MHz 时钟模拟 MMCM 尚未输出时钟。
`timescale 1ns / 1ps
module uart_reset_tb;
    string rom_path;
    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        $readmemh(rom_path, dut.soc.u_rom.mem);
    end
    localparam BIT_NS = 1_000_000_000.0 / 115200;
    localparam [111:0] EXPECTED = {"AMA CPU PASS", 8'h0d, 8'h0a};
    reg clk = 0, clock_running = 0;
    always #10 if (clock_running) clk = ~clk;
    reg rst_n = 0, locked = 0;
    wire key1_n = rst_n & locked;
    wire uart_tx;
    `include "boards/mes50hp/pins_top.vh"
    wire [`IO_N-1:0] io;
    assign io[`PIN_UART_RX] = 1'b1;
    assign uart_tx = io[`PIN_UART_TX];
    mes50hp_top #(
        .MEM_FILE("")
    ) dut (
        .clk(clk),
        .key1_n(key1_n),
        .io(io)
    );

    integer boot = 0, count = 0, writes = 0;
    reg first_write = 0;
    reg [7:0] byte_rx;
    integer b;
    always @(posedge clk or negedge key1_n) begin
        if (!key1_n) begin
            first_write <= 0;
            writes <= 0;
        end else if (dut.reset_pipe[15] && dut.soc.u_uart.tx_start) begin
            if (!first_write)
                $display(
                    "boot %0d: first TXDATA=%h at %0t, baud=%0d",
                    boot,
                    dut.soc.u_uart.data_i[7:0],
                    $time,
                    dut.soc.u_uart.uart_baud
                );
            first_write <= 1;
            writes <= writes + 1;
        end
    end

    // 无时钟时也检查; NBA 更新后采样, 首次 TXDATA 握手前不能出现起始位。
    always begin
        #1;
        if ((!dut.reset_pipe[15] || !first_write) && uart_tx !== 1'b1)
            $fatal(
                1,
                "boot %0d at %0t: TX=%b before first TXDATA (reset=%b, locked=%b)",
                boot,
                $time,
                uart_tx,
                !dut.reset_pipe[15],
                locked
            );
        @(uart_tx or key1_n or dut.reset_pipe[15] or first_write);
    end

    // 独立按 115200 8N1 解码, 从复位开始监听, 每次启动严格匹配 14 字节。
    initial
        forever begin
            @(negedge uart_tx);
            if (!dut.reset_pipe[15] || !first_write)
                $fatal(1, "boot %0d at %0t: start bit without TXDATA", boot, $time);
            if (count == 14) $fatal(1, "boot %0d: extra UART byte", boot);
            if (count == 0) $display("boot %0d: first start bit at %0t", boot, $time);
            #(BIT_NS / 2);
            if (uart_tx !== 1'b0) $fatal(1, "Invalid start bit");
            for (b = 0; b < 8; b = b + 1) begin
                #BIT_NS;
                byte_rx[b] = uart_tx;
            end
            #BIT_NS;
            if (uart_tx !== 1'b1) $fatal(1, "Invalid stop bit");
            if (byte_rx !== EXPECTED[111-count*8-:8])
                $fatal(
                    1,
                    "boot %0d: UART byte %0d got %h expected %h",
                    boot,
                    count,
                    byte_rx,
                    EXPECTED[111-count*8-:8]
                );
            count = count + 1;
        end

    initial begin
        for (boot = 0; boot < 3; boot = boot + 1) begin
            // 长于一个字符的复位, 覆盖冷启动、停钟复位、时钟仍在跑的复位。
            #120000;
            rst_n = 1;
            if (boot < 2) begin
                #20000;
                clock_running = 1;
                #20000;
                locked = 1;
            end
            wait (count == 14);
            #(BIT_NS * 20);
            if (writes != 14) $fatal(1, "boot %0d: TXDATA writes=%0d", boot, writes);
            $display("PASS uart_reset boot %0d: idle through reset, exactly AMA CPU PASS\\r\\n",
                     boot);
            @(negedge clk);
            rst_n = 0;
            #1;
            count = 0;
            if (boot == 0) begin
                locked = 0;
                clock_running = 0;
            end
        end
        $display("PASS uart_reset: power-on, stopped-clock and running-clock reset");
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "uart_reset timeout");
    end
endmodule
