`timescale 1ns / 1ps
module peripherals_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] addr = 0, data = 0;
    reg [3:0] sel = 0;
    reg we = 0, uv = 0;
    wire [31:0] ud;
    wire ur, uresp, tx;
    reg rx = 1;
    reg uart_rsp_ready = 1;
    uart #(
        .CPU_CLOCK_HZ(1843200)
    ) u (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(addr),
        .data_i(data),
        .sel_i(sel),
        .we_i(we),
        .data_o(ud),
        .req_valid_i(uv),
        .req_ready_o(ur),
        .rsp_valid_o(uresp),
        .rsp_ready_i(uart_rsp_ready),
        .tx_pin(tx),
        .rx_pin(rx)
    );
    task static access (input bit write_en, input logic [31:0] offset, input logic [31:0] value,
                        input logic [3:0] lanes, output logic [31:0] result);
        @(negedge clk);
        addr = offset;
        data = value;
        sel  = lanes;
        we   = write_en;
        uv   = 1;
        #1;
        if (ur !== 1'b1) $fatal(1, "request not ready");
        @(posedge clk);
        #1;
        if (uresp !== 1'b1) $fatal(1, "missing response");
        result = ud;
        @(negedge clk);
        uv = 0;
        we = 0;
        @(posedge clk);
        #1;
        if (uresp) $fatal(1, "unexpected extra response");
    endtask
    reg [31:0] result;
    integer i;
    integer test_pass = 0;
    reg [7:0] received;
    task static send_rx(input logic [7:0] value);
        @(negedge clk);
        rx = 0;
        repeat (17) @(negedge clk);
        for (integer b = 0; b < 8; b = b + 1) begin
            rx = value[b];
            repeat (17) @(negedge clk);
        end
        rx = 1;
        repeat (20) @(negedge clk);
    endtask
    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        access (0, 8, 0, 15, result);
        if (result !== 16) $fatal(1, "UART clock parameter failure");

        // Hold a BAUD read response and present a blocked BAUD write.
        @(negedge clk);
        uart_rsp_ready = 0;
        uv = 1;
        we = 0;
        addr = 8;
        sel = 15;
        @(posedge clk);
        #1;
        if (!uresp || ud !== 16) $fatal(1, "UART read response");
        @(negedge clk);
        we   = 1;
        data = 20;
        repeat (5) begin
            @(posedge clk);
            #1;
            if (ur || !uresp || ud !== 16 || u.uart_baud !== 16)
                $fatal(1, "UART response/backpressure lost data or executed blocked write");
        end
        @(negedge clk);
        uart_rsp_ready = 1;
        @(posedge clk);
        #1;
        if (!uresp || ud !== 0 || u.uart_baud !== 20)
            $fatal(1, "UART response replacement / accepted write");
        @(negedge clk);
        uv = 0;
        we = 0;
        @(posedge clk);
        #1;
        if (uresp) $fatal(1, "UART duplicate response");
        access (1, 8, 16, 15, result);  // restore the divider for the frame tests
        access (1, 0, 3, 1, result);
        // Independent TX pin decoder, not internal-state inspection or TX/RX loopback.
        fork
            begin
                access (1, 12, 8'ha5, 1, result);
            end
            begin
                @(negedge tx);
                #85;
                if (tx !== 0) $fatal(1, "UART start bit failure");
                for (i = 0; i < 8; i = i + 1) begin
                    #170;
                    received[i] = tx;
                end
                #170;
                if (tx !== 1 || received !== 8'ha5) $fatal(1, "UART frame failure");
            end
        join
        repeat (20) @(posedge clk);
        access (0, 4, 0, 15, result);
        if (result[0] !== 0) $fatal(1, "UART busy did not clear");
        send_rx(8'h3c);
        access (0, 4, 0, 15, result);
        if (result[1] !== 1) $fatal(1, "UART RX status failure");
        access (0, 16, 0, 15, result);
        if (result !== 8'h3c) $fatal(1, "UART RX data failure: %h", result);
        access (1, 4, 0, 1, result);
        access (0, 4, 0, 15, result);
        if (result[1] !== 0) $fatal(1, "UART RX status clear failure");
        $display("PASS peripherals: UART backpressure, TX and independent RX");
        test_pass = 1;
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
