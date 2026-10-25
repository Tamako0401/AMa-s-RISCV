`timescale 1ns / 1ps
// 窗口里按下的字符 (view.py 追加到 +keys 文件) 按 115200 发到板子的串口接收脚
module uart_tx (
    input  wire clk,
    output reg  tx = 1
);
    localparam BIT_CLKS = 434;  // 50 MHz / 115200
    string path;
    integer fd, pos = 0, c;

    initial begin
        void'($value$plusargs("keys=%s", path));  // 丢弃返回值的写法见 soc_tb.sv 的注释
        fd = $fopen(path, "rb");
        forever begin
            repeat (10000) @(posedge clk);
            // 文件读到过末尾后 C 库会一直返回 EOF, 每次重新定位才能读到新追加的字符
            c = $fseek(fd, pos, 0);
            c = $fgetc(fd);
            while (c != -1) begin
                pos++;
                tx = 0;
                repeat (BIT_CLKS) @(posedge clk);
                for (integer b = 0; b < 8; b++) begin
                    tx = c[b];
                    repeat (BIT_CLKS) @(posedge clk);
                end
                tx = 1;
                repeat (BIT_CLKS) @(posedge clk);
                c = $fgetc(fd);
            end
        end
    end
endmodule
