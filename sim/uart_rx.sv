`timescale 1ns/1ps
module uart_rx(input wire clk, input wire tx);
    localparam BIT_CLKS = 434; // 50 MHz / 115200
    reg [7:0] ch;

    initial forever begin
        @(negedge tx);
        repeat (BIT_CLKS / 2) @(posedge clk);
        for (integer b = 0; b < 8; b = b + 1) begin
            repeat (BIT_CLKS) @(posedge clk);
            ch[b] = tx;
        end
        repeat (BIT_CLKS) @(posedge clk);
        $write("%c", ch);
        $fflush;
    end
endmodule
