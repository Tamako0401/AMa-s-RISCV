// UART STATUS 寄存器的同拍竞争 (rtl/perips/uart.v)。
//
// 软件清 RX 完成标志 (写 STATUS) 可能和硬件事件落在同一个时钟沿:
//   A. TX 停止位结束 (硬件清 TX busy): busy 必须照样清零, 否则 putc 永远等待;
//   B. 又收到一个字节 (硬件置 RX done): 标志必须保持为 1, 否则这个字节丢失。
// 两种情况都把写入时刻在事件前后各扫 3 拍, 用实际握手沿和事件沿的时间差核对偏移。
// 原先 STATUS 用一个 if/else: 软件写的那一拍整个跳过了硬件更新, A、B 都在偏移 0 出错。
`timescale 1ns / 1ps
module uart_status_tb;
    localparam BAUD     = 16;                         // 小分频, 一位 17 拍, 仿真快
    localparam BIT_CLKS = BAUD + 1;
    localparam S_IDLE   = 4'b0001, S_STOP = 4'b1000;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, rx = 1;
    reg [31:0] addr = 0, wdata = 0;
    reg we = 0, valid = 0;
    wire ready, rsp_valid, tx;
    wire [31:0] rdata;
    uart #(
        .CPU_CLOCK_HZ(1843200)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(addr),
        .data_i(wdata),
        .sel_i(4'b0001),
        .we_i(we),
        .data_o(rdata),
        .req_valid_i(valid),
        .req_ready_o(ready),
        .rsp_valid_o(rsp_valid),
        .rsp_ready_i(1'b1),
        .tx_pin(tx),
        .rx_pin(rx)
    );

    // 时间戳: 第几个上升沿发生了 STATUS 写握手 / TX 停止位结束 / RX 收完
    integer cycle = 0, write_cycle, stop_cycle, rx_cycle;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (rst_n && valid && ready && we && addr == 4) write_cycle = cycle;
        if (rst_n && dut.state == S_STOP && dut.cycle_cnt == BAUD) stop_cycle = cycle;
        if (rst_n && dut.rx_recv_over) rx_cycle = cycle;
    end

    // 一次 MMIO 读写: 下降沿给请求, 上升沿握手, 响应在下一拍
    task access (input bit wr, input [31:0] offset, input [31:0] value, output [31:0] result);
        @(negedge clk);
        addr = offset;
        wdata = value;
        we = wr;
        valid = 1;
        @(posedge clk);
        if (ready !== 1'b1) $fatal(1, "MMIO request not accepted");
        #1 result = rdata;
        @(negedge clk);
        valid = 0;
        we = 0;
        addr = 0;
    endtask

    // 在接下来第 n 个上升沿写 STATUS = 0 (清 RX 标志), 只握手一拍
    // CI 的 Verilator 5.020 不支持 fork 调用栈里的 repeat。
    task write_status_at(input integer n);
        for (integer i = 0; i < n - 1; i = i + 1) @(negedge clk);
        @(negedge clk);
        addr = 4;
        wdata = 0;
        we = 1;
        valid = 1;
        @(negedge clk);
        valid = 0;
        we = 0;
        addr = 0;
    endtask

    task send_rx(input [7:0] value);
        rx = 0;
        for (integer i = 0; i < BIT_CLKS; i = i + 1) @(negedge clk);
        for (integer b = 0; b < 8; b = b + 1) begin
            rx = value[b];
            for (integer i = 0; i < BIT_CLKS; i = i + 1) @(negedge clk);
        end
        rx = 1;
        for (integer i = 0; i < BIT_CLKS; i = i + 1) @(negedge clk);
    endtask

    task restart;
        reg [31:0] r;
        @(negedge clk);
        rst_n = 0;
        valid = 0;
        we = 0;
        rx = 1;
        repeat (3) @(negedge clk);
        rst_n = 1;
        access (1, 8, BAUD, r);  // 分频
        access (1, 0, 3, r);  // TX + RX 使能
    endtask

    integer offset, rx_lead;
    reg [31:0] r;
    initial begin
        // ---- A: 清 RX 标志 与 TX 停止位结束 同拍 ----
        for (offset = -3; offset <= 3; offset = offset + 1) begin
            restart;
            access (1, 12, 8'ha5, r);  // 开始发送
            // 停在停止位结束前 4 拍的下降沿, 再数 4+offset 拍发起写
            do @(negedge clk); while (!(dut.state == S_STOP && dut.cycle_cnt == BAUD - 4));
            write_status_at(4 + offset);
            repeat (3 * BIT_CLKS) @(negedge clk);
            access (0, 4, 0, r);
            if (write_cycle - stop_cycle != offset)
                $fatal(1, "A offset %0d: measured %0d", offset, write_cycle - stop_cycle);
            if (r[0] !== 1'b0 || dut.state !== S_IDLE)
                $fatal(1, "A offset %0d: TX busy stuck at 1 after the stop bit", offset);
        end
        $display(
            "PASS uart_status A: STATUS write on the TX stop-bit edge (offsets -3..3) still clears busy");

        // ---- B: 清 RX 标志 与 又收到一个字节 同拍 ----
        // 先量出从起始位开始到 rx_recv_over 的拍数 (与偏移无关, 固定)
        restart;
        fork
            send_rx(8'h11);
            begin
                @(negedge clk);
                rx_lead = cycle;
            end
        join
        rx_lead = rx_cycle - rx_lead;  // 起始位后第 rx_lead 个上升沿收完
        for (offset = -3; offset <= 3; offset = offset + 1) begin
            restart;
            fork
                send_rx(8'h5a);
                write_status_at(rx_lead + offset);
            join
            access (0, 4, 0, r);
            if (write_cycle - rx_cycle != offset)
                $fatal(1, "B offset %0d: measured %0d", offset, write_cycle - rx_cycle);
            // 先清后收 (offset<0) 或同拍 (offset=0): 新字节还没被软件取走, 标志必须是 1;
            // 收完以后才清 (offset>0): 软件确认过了, 标志为 0
            if (r[1] !== (offset <= 0))
                $fatal(
                    1,
                    "B offset %0d: RX done=%b, expected %b%s",
                    offset,
                    r[1],
                    offset <= 0,
                    offset == 0 ? " (byte lost)" : ""
                );
            access (0, 16, 0, r);
            if (r[7:0] !== 8'h5a) $fatal(1, "B offset %0d: RXDATA=%h", offset, r[7:0]);
        end
        $display(
            "PASS uart_status B: STATUS write on the RX-complete edge (offsets -3..3) keeps the new byte");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "uart_status timeout");
    end
endmodule
