// 调色板: 256 项 RGB565, 一拍查 8 个色号 (一格 8 个点)。先用 8 份简单双口 RAM, 写口一起写。
// 资源紧了可以改成 4 份真双口, 每份查 2 个。
module disp_palette (
    input wire clk,
    input wire we,
    input wire [7:0] waddr,
    input wire [15:0] wdata,
    input wire [63:0] raddr,  // 第 i 个色号在 [8i+7:8i]
    output wire [127:0] rdata  // 第 i 个颜色在 [16i+15:16i], 下一拍有效
);
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_copy
            dpram #(
                .DW(16),
                .DP(256)
            ) u_ram (
                .clk(clk),
                .we(we),
                .waddr(waddr),
                .wdata(wdata),
                .raddr(raddr[8*i+:8]),
                .rdata(rdata[16*i+:16])
            );
        end
    endgenerate
endmodule
