// 双时钟简单双口 RAM: 写口在 wclk, 读口在 rclk (跨时钟域传数据块用); 读地址打一拍, 数据下一拍有效。
module dpram2c #(
    parameter DW = 8,
    parameter DP = 256,
    parameter AW = $clog2(DP)
) (
    input wire wclk,
    input wire we,
    input wire [AW-1:0] waddr,
    input wire [DW-1:0] wdata,
    input wire rclk,
    input wire [AW-1:0] raddr,
    output wire [DW-1:0] rdata
);
    reg [DW-1:0] mem[0:DP-1];
    reg [AW-1:0] raddr_r;
    always @(posedge wclk) if (we) mem[waddr] <= wdata;
    always @(posedge rclk) raddr_r <= raddr;
    assign rdata = mem[raddr_r];
endmodule
