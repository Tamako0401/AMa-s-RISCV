// 简单双口 RAM: 一个写口, 一个读口, 同一时钟; 读地址打一拍, 数据下一拍有效 (综合成块 RAM)。
// 同一拍读写同一地址: 下一拍读到新值。
module dpram #(
    parameter DW = 32,
    parameter DP = 256,
    parameter AW = $clog2(DP)
) (
    input wire clk,
    input wire we,
    input wire [AW-1:0] waddr,
    input wire [DW-1:0] wdata,
    input wire [AW-1:0] raddr,
    output wire [DW-1:0] rdata
);
    reg [DW-1:0] mem[0:DP-1];
    reg [AW-1:0] raddr_r;
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        raddr_r <= raddr;
    end
    assign rdata = mem[raddr_r];
endmodule
