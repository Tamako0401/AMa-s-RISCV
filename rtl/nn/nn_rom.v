// 只读 ROM: 一拍读延迟, 初值用 $readmemh 从 INIT_FILE 载入 (和 rtl/perips/rom.v 的做法一致)。
module nn_rom #(
    parameter DW = 32,
    parameter DP = 1024,
    parameter AW = $clog2(DP),
    parameter INIT_FILE = ""
) (
    input wire clk,
    input wire [AW-1:0] addr,
    output reg [DW-1:0] data
);
    reg [DW-1:0] mem[0:DP-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end
endmodule
