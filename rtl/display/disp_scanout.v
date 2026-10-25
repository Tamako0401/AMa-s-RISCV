// 显示端 (pclk 域): 读显示行缓存 -> 整体混色 -> RGB565 扩成 RGB888 -> 盖文字层 -> 输出。
// 逻辑点 (h/2, v/2) 在显示行缓存 {逻辑行[0], 第几格} 的第 (h/2)&7 个 16 位里。
// 文字层 1280x720 原生: 格 (h/8, v/16) 的 {颜色[11:8], 字符[7:0]} -> 字库第 字符*16 + v%16 字节, 最高位在左;
// 字符 33~127 才画, 字形是 1 的点用 16 色 (CGA) 之一, 是 0 的点透明。
// 同步信号 (低有效) 和数据一起延迟 4 拍。
module disp_scanout (
    input wire pclk,
    input wire rst_n,
    input wire [10:0] h,
    input wire [9:0] v,
    input wire enable,
    input wire [15:0] fade_color,
    input wire [4:0] fade_level,

    output wire [  7:0] lb_raddr,
    input  wire [127:0] lb_rdata,
    output wire [ 12:0] text_raddr,
    input  wire [ 11:0] text_rdata,
    output wire [ 10:0] font_raddr,
    input  wire [  7:0] font_rdata,

    output reg hsync_n,
    output reg vsync_n,
    output reg de,
    output reg [23:0] rgb
);
    localparam H_ACT = 1280, H_SYNC0 = 1280 + 110, H_SYNC1 = 1280 + 110 + 40;
    localparam V_ACT = 720, V_SYNC0 = 720 + 5, V_SYNC1 = 720 + 5 + 5;

    // 第 0 拍: 地址
    wire [5:0] row = v[9:4];
    assign lb_raddr   = {v[1], h[10:4]};
    assign text_raddr = {row, 7'b0} + {2'b0, row, 5'b0} + {5'b0, h[10:3]};
    wire de0 = h < H_ACT && v < V_ACT;
    wire hs0 = !(h >= H_SYNC0 && h < H_SYNC1);
    wire vs0 = !(v >= V_SYNC0 && v < V_SYNC1);

    // 第 1 拍: 行缓存、文字数据到了
    reg [2:0] lane1, bit1;
    reg [3:0] font_row1;
    reg [2:0] de_d, hs_d, vs_d;
    wire [7:0] ch1 = text_rdata[7:0];
    assign font_raddr = {ch1[6:0], font_row1};

    // 第 2 拍: 字库到了; 混色
    reg [15:0] pix2;
    reg [3:0] color2;
    reg [2:0] bit2;
    reg draw2;
    wire [4:0] keep = 5'd16 - fade_level;
    wire [10:0] r_mix = pix2[15:11] * keep + fade_color[15:11] * fade_level;
    wire [11:0] g_mix = pix2[10:5] * keep + fade_color[10:5] * fade_level;
    wire [10:0] b_mix = pix2[4:0] * keep + fade_color[4:0] * fade_level;
    wire [4:0] r5 = r_mix[8:4];
    wire [5:0] g6 = g_mix[9:4];
    wire [4:0] b5 = b_mix[8:4];

    // 第 3 拍: 选文字还是画面
    reg [23:0] rgb3;
    reg text3;
    reg [3:0] color3;

    // 文字颜色: CGA 16 色先变 RGB565 再扩成 RGB888 (同参考模型)
    function automatic [23:0] cga(input reg [3:0] c);
        case (c)
            4'd0: cga = 24'h000000;
            4'd1: cga = 24'h0000ad;
            4'd2: cga = 24'h00aa00;
            4'd3: cga = 24'h00aaad;
            4'd4: cga = 24'had0000;
            4'd5: cga = 24'had00ad;
            4'd6: cga = 24'had5500;
            4'd7: cga = 24'hadaaad;
            4'd8: cga = 24'h525552;
            4'd9: cga = 24'h5255ff;
            4'd10: cga = 24'h52ff52;
            4'd11: cga = 24'h52ffff;
            4'd12: cga = 24'hff5552;
            4'd13: cga = 24'hff55ff;
            4'd14: cga = 24'hffff52;
            default: cga = 24'hffffff;
        endcase
    endfunction

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            de_d <= 0;
            hs_d <= 3'b111;
            vs_d <= 3'b111;
            de <= 0;
            hsync_n <= 1;
            vsync_n <= 1;
            rgb <= 0;
            draw2 <= 0;
            text3 <= 0;
        end else begin
            {de, de_d} <= {de_d, de0};
            {hsync_n, hs_d} <= {hs_d, hs0};
            {vsync_n, vs_d} <= {vs_d, vs0};

            lane1 <= h[3:1];
            bit1 <= h[2:0];
            font_row1 <= v[3:0];

            pix2 <= lb_rdata[{lane1, 4'b0}+:16];
            color2 <= text_rdata[11:8];
            bit2 <= bit1;
            draw2 <= ch1 > 32 && ch1 < 128;

            rgb3 <= {r5, r5[4:2], g6, g6[5:4], b5, b5[4:2]};
            text3 <= draw2 && font_rdata[3'd7-bit2];
            color3 <= color2;

            rgb <= !(de_d[2] && enable) ? 24'h0 : text3 ? cga(color3) : rgb3;
        end
    end
endmodule
