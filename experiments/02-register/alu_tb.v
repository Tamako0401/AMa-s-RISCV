`timescale 1ns/1ps

module register_tb;
    reg clk = 0;
    reg rst = 1;
    reg [7:0] d = 0;
    wire [7:0] q;

    register dut (.clk(clk), .rst(rst), .d(d), .q(q));

    always #5 clk = ~clk;       // 每隔 5 ns 翻转一次信号，10 ns 一个上升沿

    initial begin
        #6;
        if (q !== 8'd0) $fatal(1, "Reset failed");

        rst = 0;
        d = 8'd42;
        #10;
        if (q !== 8'd42) $fatal(1, "Capture failed");

        d = 8'd99;
        #2;
        if (q !== 8'd42) $fatal(1, "Changed before clock edge");

        #8;
        if (q !== 8'd99) $fatal(1, "Second capture failed");

        $display("PASS");
        $finish;
    end
endmodule