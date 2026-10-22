`ifndef MES50HP_VIDEO_CLOCK_VH
`define MES50HP_VIDEO_CLOCK_VH
`timescale 1ns / 1ps
// 板级像素时钟边界: 当前仓库没有 PLL IP 或原语实例可供核对。
module mes50hp_video_clock (
    input wire clk, input wire rst_n,
    output wire pix_clk, output wire locked
);
`ifndef VERILATOR
    // TODO: 用 PDS 为 PGL50H 生成 50 MHz -> 74.25 MHz PLL, 接上锁定信号。
    // 刻意保留未定义实例, 缺 IP 时综合必须失败, 不能悄悄用 50 MHz 代替。
    MES50HP_720P_PLL_TODO u_pll (.clkin(clk), .resetn(rst_n), .clkout(pix_clk), .lock(locked));
`else
    reg pixel = 0;
    always #6.734006734 pixel = ~pixel;
    assign pix_clk = pixel;
    assign locked = rst_n;
`endif
endmodule
`endif
