// 和 dpram 一样的简单双口 RAM, 但存储强制用 LUT RAM (不占 DRM): 给又浅又宽、或块数比 DRM 余量更紧的表用。
// 读地址打一拍, 数据下一拍有效; 同一拍读写同一地址: 下一拍读到新值。
module dpram_lut #(
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
    (* syn_ramstyle = "select_ram" *) reg [DW-1:0] mem[0:DP-1];
    reg [AW-1:0] raddr_r;
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        raddr_r <= raddr;
    end
    assign rdata = mem[raddr_r];
endmodule
