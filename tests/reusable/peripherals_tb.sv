`timescale 1ns / 1ps
module peripherals_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] addr = 0, data = 0;
    reg [3:0] sel = 0;
    reg we = 0, gv = 0, uv = 0;
    wire [31:0] gd, ud, ctrl, pins;
    wire gr, gresp, ur, uresp, tx;
    reg [1:0] inputs = 0;
    reg rx = 1;
    reg gpio_rsp_ready = 1, uart_rsp_ready = 1;
    // Both peripherals are tested with immediate consumption and with backpressure.
    gpio g (
        clk,
        rst_n,
        addr,
        data,
        sel,
        we,
        gd,
        gv,
        gr,
        gresp,
        gpio_rsp_ready,
        inputs,
        ctrl,
        pins
    );
    uart #(
        .CPU_CLOCK_HZ(1843200)
    ) u (
        clk,
        rst_n,
        addr,
        data,
        sel,
        we,
        ud,
        uv,
        ur,
        uresp,
        uart_rsp_ready,
        tx,
        rx
    );
    task access (input bit is_uart, input bit write_en, input [31:0] offset, input [31:0] value,
                 input [3:0] lanes, output [31:0] result);
        @(negedge clk);
        addr = offset;
        data = value;
        sel  = lanes;
        we   = write_en;
        gv   = !is_uart;
        uv   = is_uart;
        #1;
        if ((is_uart ? ur : gr) !== 1'b1) $fatal(1, "request not ready");
        @(posedge clk);
        #1;
        if ((is_uart ? uresp : gresp) !== 1'b1) $fatal(1, "missing response");
        result = is_uart ? ud : gd;
        @(negedge clk);
        gv = 0;
        uv = 0;
        we = 0;
        @(posedge clk);
        #1;
        if (gresp || uresp) $fatal(1, "unexpected extra response");
    endtask
    reg [31:0] result;
    integer i;
    integer test_pass = 0;
    reg [7:0] received;
    task send_rx(input [7:0] value);
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
        access (0, 0, 0, 0, 15, result);
        if (result !== 0) $fatal(1, "GPIO reset failure");
        access (0, 1, 0, 5, 1, result);  // both pins outputs
        access (0, 1, 4, 32'h00001203, 3, result);
        access (0, 1, 4, 32'h0000ab00, 2, result);
        access (0, 0, 4, 0, 15, result);
        if (result !== 32'h0000ab03 || ctrl !== 5 || pins !== result)
            $fatal(1, "GPIO write/mask/read failure");
        access (0, 1, 8, 32'h00010004, 15, result);  // clear pin 0, set pin 2
        if (pins !== 32'h0000ab06) $fatal(1, "BSRR set/reset");
        access (0, 1, 8, 32'h00040004, 15, result);  // set wins on overlap
        if (pins !== 32'h0000ab06) $fatal(1, "BSRR overlap priority");
        access (0, 1, 10, 32'h00060000, 12, result);  // upper halfword reset
        if (pins !== 32'h0000ab00) $fatal(1, "BSRR halfword reset");
        access (0, 1, 9, 32'h00001200, 2, result);
        if (pins !== 32'h0000bb00) $fatal(1, "BSRR byte set");
        access (0, 1, 11, 32'h12000000, 8, result);
        if (pins !== 32'h0000a900) $fatal(1, "BSRR byte reset");
        access (0, 1, 8, 1, 1, result);
        access (0, 0, 8, 0, 15, result);
        if (result !== 0) $fatal(1, "BSRR read must be zero");

        // Hold a DATA read response and present a blocked BSRR write. The write
        // must execute exactly once when the old response is finally consumed.
        @(negedge clk);
        gpio_rsp_ready = 0;
        gv = 1;
        uv = 0;
        we = 0;
        addr = 4;
        sel = 15;
        @(posedge clk);
        #1;
        if (!gresp || gd !== 32'h0000a901) $fatal(1, "GPIO read response");
        @(negedge clk);
        we   = 1;
        addr = 8;
        data = 32'h00010002;
        repeat (5) begin
            @(posedge clk);
            #1;
            if (gr || !gresp || gd !== 32'h0000a901 || pins !== 32'h0000a901)
                $fatal(1, "GPIO response/backpressure lost data or executed blocked write");
        end
        @(negedge clk);
        gpio_rsp_ready = 1;
        @(posedge clk);
        #1;
        if (!gresp || gd !== 0 || pins !== 32'h0000a902)
            $fatal(1, "GPIO response replacement / accepted write");
        @(negedge clk);
        gv = 0;
        we = 0;
        @(posedge clk);
        #1;
        if (gresp) $fatal(1, "GPIO duplicate response");
        access (0, 1, 0, 10, 1, result);  // both pins inputs
        inputs = 2'b01;
        repeat (3) @(posedge clk);
        access (0, 0, 4, 0, 15, result);
        if (result[1:0] !== 1) $fatal(1, "GPIO sampling failure");

        access (1, 0, 8, 0, 15, result);
        if (result !== 16) $fatal(1, "UART clock parameter failure");

        // Same as GPIO: hold a BAUD read response and present a blocked BAUD write.
        @(negedge clk);
        uart_rsp_ready = 0;
        uv = 1;
        gv = 0;
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
        access (1, 1, 8, 16, 15, result);  // restore the divider for the frame tests
        access (1, 1, 0, 3, 1, result);
        // Independent TX pin decoder, not internal-state inspection or TX/RX loopback.
        fork
            begin
                access (1, 1, 12, 8'ha5, 1, result);
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
        access (1, 0, 4, 0, 15, result);
        if (result[0] !== 0) $fatal(1, "UART busy did not clear");
        send_rx(8'h3c);
        access (1, 0, 4, 0, 15, result);
        if (result[1] !== 1) $fatal(1, "UART RX status failure");
        access (1, 0, 16, 0, 15, result);
        if (result !== 8'h3c) $fatal(1, "UART RX data failure: %h", result);
        access (1, 1, 4, 0, 1, result);
        access (1, 0, 4, 0, 15, result);
        if (result[1] !== 0) $fatal(1, "UART RX status clear failure");
        $display(
            "PASS peripherals: GPIO masks/input/BSRR/backpressure, UART backpressure, TX and independent RX");
        test_pass = 1;
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
