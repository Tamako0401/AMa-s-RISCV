`timescale 1ns / 1ps
module gpio_matrix_case #(
    parameter IO_N = 37,
    parameter TX   = 5,
    parameter RX   = 6
) (
    output reg done = 0
);
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] addr = 0, wdata = 0;
    reg we = 0, valid = 0, rsp_ready = 0;
    wire ready, rsp_valid;
    wire [ 31:0] rdata;
    reg  [127:0] pins = 0;
    wire [127:0] out_pins, oe;
    reg tx = 0, sck = 0, mosi = 0, tx2 = 0;
    wire rx, miso, rx2;
    gpio_matrix #(
        .IO_N(IO_N),
        .UART_TX_PIN(TX),
        .UART_RX_PIN(RX)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(addr),
        .data_i(wdata),
        .sel_i(4'hf),
        .we_i(we),
        .data_o(rdata),
        .req_valid_i(valid),
        .req_ready_o(ready),
        .rsp_valid_o(rsp_valid),
        .rsp_ready_i(rsp_ready),
        .io_i(pins),
        .io_o(out_pins),
        .io_oe(oe),
        .uart_tx_i(tx),
        .uart_rx_o(rx),
        .spi_sck_i(sck),
        .spi_mosi_i(mosi),
        .spi_miso_o(miso),
        .uart2_tx_i(tx2),
        .uart2_rx_o(rx2)
    );

    task static check(input bit ok, input string message);
        if (!ok) begin
            $display("FAIL IO_N=%0d: %s", IO_N, message);
            $fatal(1);
        end
    endtask

    reg [31:0] result;
    task static access (input bit write_en, input logic [31:0] offset, input logic [31:0] value);
        @(negedge clk);
        addr = offset;
        wdata = value;
        we = write_en;
        valid = 1;
        @(posedge clk);
        check(ready === 1'b1, "request ready");
        #1;
        check(rsp_valid === 1'b1, "registered response");
        result = rdata;
        @(negedge clk);
        valid = 0;
        rsp_ready = 1;
        @(posedge clk);
        #1;
        check(rsp_valid === 1'b0, "response consumed");
        @(negedge clk);
        rsp_ready = 0;
    endtask
    task static read_check(input logic [31:0] offset, input logic [31:0] expected);
        access (0, offset, 0);
        check(result === expected, $sformatf("read %h got %h expected %h", offset, result, expected
              ));
    endtask

    integer k, n, sig;
    reg [ 31:0] mask;
    reg [127:0] expected_oe;
    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;
        expected_oe = 0;
        if (TX < IO_N) expected_oe[TX] = 1;
        #1;
        check(oe === expected_oe && out_pins === 128'b0, "reset outputs");
        check(rx === (RX < IO_N ? 1'b0 : 1'b1) && miso === 1'b0 && rx2 === 1'b1, "reset inputs");
        tx = 1;
        #1;
        check(out_pins === expected_oe, "reset UART TX routing");
        read_check('h400, RX);
        read_check('h404, 'hff);
        read_check('h408, 'hff);
        access (1, 'h40c, 5);  // 3 号输入信号保留: 写丢弃, 读 0
        read_check('h40c, 0);
        for (n = 0; n < 128; n = n + 1) read_check('h200 + 4 * n, n < IO_N && n == TX ? 1 : 0);
        if (TX < IO_N) access (1, 'h200 + TX * 4, 0);

        for (k = 0; k < 4; k = k + 1) begin
            mask = 0;
            for (n = 0; n < 32; n = n + 1) if (k * 32 + n < IO_N) mask[n] = 1;
            read_check(4 * k, 0);
            read_check('h30 + 4 * k, 0);
            access (1, 4 * k, 'ha5a55a5a);
            read_check(4 * k, 'ha5a55a5a & mask);
            access (1, 'h10 + 4 * k, 'h0f0f0f0f);
            read_check(4 * k, 'hafaf5f5f & mask);
            access (1, 'h20 + 4 * k, 'h00ff00ff);
            read_check(4 * k, 'haf005f00 & mask);
            read_check('h10 + 4 * k, 0);
            read_check('h20 + 4 * k, 0);
            access (1, 'h30 + 4 * k, 'ha5a55a5a);
            read_check('h30 + 4 * k, 'ha5a55a5a & mask);
            access (1, 'h40 + 4 * k, 'h0f0f0f0f);
            read_check('h30 + 4 * k, 'hafaf5f5f & mask);
            access (1, 'h50 + 4 * k, 'h00ff00ff);
            read_check('h30 + 4 * k, 'haf005f00 & mask);
            read_check('h40 + 4 * k, 0);
            read_check('h50 + 4 * k, 0);
            check(out_pins[k*32+:32] === ('haf005f00 & mask), "GPIO output");
            check(oe[k*32+:32] === ('haf005f00 & mask), "GPIO enable");
            access (1, 'h60 + 4 * k, 'hffffffff);
            read_check('h60 + 4 * k, 0);
            access (1, 4 * k, 0);
            access (1, 'h30 + 4 * k, 0);
        end

        // 逐拍观察外设输入，防止总线访问的延迟掩盖同步级数错误。
        if (RX < IO_N) begin
            @(negedge clk);
            pins[RX] = 1;
            #1;
            check(rx === 1'b0, "input must not bypass synchronizer");
            @(posedge clk);
            #1;
            check(rx === 1'b0, "first synchronizer stage");
            @(posedge clk);
            #1;
            check(rx === 1'b1, "second synchronizer stage");
        end
        @(negedge clk);
        pins = 128'hfedcba98765432100123456789abcdef;
        repeat (2) @(posedge clk);
        #1;
        for (k = 0; k < 4; k = k + 1) begin
            mask = 0;
            for (n = 0; n < 32; n = n + 1) if (k * 32 + n < IO_N) mask[n] = 1;
            read_check('h60 + 4 * k, pins[k*32+:32] & mask);
        end

        for (n = 0; n < 128; n = n + 1) begin
            access (1, 'h10 + (n / 32) * 4, 32'd1 << (n % 32));
            access (1, 'h40 + (n / 32) * 4, 32'd1 << (n % 32));
            for (sig = 1; sig <= 4; sig = sig + 1) begin
                access (1, 'h200 + 4 * n, sig);
                read_check('h200 + 4 * n, n < IO_N ? sig : 0);
                tx   = 0;
                sck  = 0;
                mosi = 0;
                tx2  = 0;
                #1;
                check(out_pins[n] === 1'b0 && oe[n] === (n < IO_N), "peripheral low/OE");
                tx   = sig == 1;
                sck  = sig == 2;
                mosi = sig == 3;
                tx2  = sig == 4;
                #1;
                check(out_pins[n] === (n < IO_N), "peripheral signal selection");
            end
            access (1, 'h200 + 4 * n, 0);
            check(out_pins[n] === (n < IO_N) && oe[n] === (n < IO_N), "restored GPIO registers");
            access (1, 'h20 + (n / 32) * 4, 32'd1 << (n % 32));
            access (1, 'h50 + (n / 32) * 4, 32'd1 << (n % 32));
            access (1, 'h400, n);
            access (1, 'h404, n);
            access (1, 'h408, n);
            check(rx === (n < IO_N ? pins[n] : 1'b1), "UART input selection");
            check(miso === (n < IO_N ? pins[n] : 1'b0), "SPI input selection");
            check(rx2 === (n < IO_N ? pins[n] : 1'b1), "UART2 input selection");
        end
        access (1, 'h400, 'hff);
        access (1, 'h404, 'hff);
        access (1, 'h408, 'hff);
        check(rx === 1'b1 && miso === 1'b0 && rx2 === 1'b1, "disconnected idle levels");

        // 背压期间持续发新写请求，检查它不会提前改变寄存器。
        access (1, 0, 0);
        @(negedge clk);
        addr = 'h60;
        we = 0;
        valid = 1;
        @(posedge clk);
        #1;
        check(rsp_valid === 1'b1, "stalled read response");
        result = rdata;
        @(negedge clk);
        addr = 0;
        we = 1;
        wdata = 'hffffffff;
        pins = ~pins;
        repeat (4) begin
            @(posedge clk);
            #1;
            check(ready === 1'b0 && rsp_valid === 1'b1 && rdata === result,
                  "response held under backpressure");
            check(out_pins === 128'b0, "blocked write discarded until handshake");
        end
        @(negedge clk);
        rsp_ready = 1;
        @(posedge clk);
        #1;
        check(rsp_valid === 1'b1 && rdata === 0, "response replaced on simultaneous handshake");
        @(negedge clk);
        valid = 0;
        @(posedge clk);
        #1;
        check(rsp_valid === 1'b0, "no duplicate response");
        @(negedge clk);
        rsp_ready = 0;
        mask = 0;
        for (n = 0; n < 32; n = n + 1) if (n < IO_N) mask[n] = 1;
        read_check(0, mask);
        done = 1;
    end
endmodule

module gpio_matrix_tb;
    wire [3:0] done;
    gpio_matrix_case #(.IO_N(0)) c0 (done[0]);
    gpio_matrix_case #(
        .IO_N(1),
        .TX  (0),
        .RX  (0)
    ) c1 (
        done[1]
    );
    gpio_matrix_case #(.IO_N(37)) c37 (done[2]);
    gpio_matrix_case #(
        .IO_N(128),
        .TX  (127),
        .RX  (126)
    ) c128 (
        done[3]
    );
    initial begin
        wait (&done);
        $display("PASS gpio_matrix");
        $finish;
    end
    initial begin
        #1000000;
        $display("FAIL gpio_matrix timeout");
        $fatal(1);
    end
endmodule
