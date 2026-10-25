// 格子写回: 渲染一次交来一格 (8 个点), 和工作行缓存里已有的颜色混合后写回工作行和显示行。
//   第 1 拍 (输入寄存器): 8 个色号送调色板, 格号送工作行读口
//   第 2 拍: 拿到 8 个颜色和底下的颜色, 逐点混合 (每个通道按自己的位数 5/6/5 算)
//   第 3 拍: 写工作行 (clk 域, 下一格要读) 和显示行 ({行号[0], 格号}, 给 pclk 域)
// 一拍可以收一格, 不反压: 同一格紧挨着来时, 底下的颜色从第 3 拍 (正在写) 或第 4 拍 (刚写完) 前递, 不依赖 RAM 读写冲突的行为。
// 点的去向: mask 为 1 的点按 mode 画; 为 0 的点 fill 时写底色 (背景那一遍), 否则不变。
module disp_blend (
    input wire clk,
    input wire rst_n,

    input wire cell_valid,
    input wire [6:0] cell_x,
    input wire cell_bank,
    input wire [127:0] cell_pix,  // raw: 8 个 RGB565; 否则第 i 个点的色号在 [16i+7:16i]
    input wire cell_raw,
    input wire [7:0] cell_mask,
    input wire cell_fill,
    input wire [1:0] cell_mode,  // [1] 加法, [0] 按 alpha 半透明; 都为 0 是不透明
    input wire [4:0] cell_alpha,
    input wire [15:0] backdrop,
    output wire idle,

    output wire [ 63:0] pal_raddr,
    input  wire [127:0] pal_rdata,

    output wire [  6:0] work_raddr,
    input  wire [127:0] work_rdata,
    output reg          work_we,
    output reg  [  6:0] work_waddr,
    output reg  [127:0] work_wdata,
    output reg          show_we,
    output reg  [  7:0] show_waddr
);
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_idx
            assign pal_raddr[8*i+:8] = cell_pix[16*i+:8];
        end
    endgenerate
    assign work_raddr = cell_x;

    reg v2, v4;
    reg [6:0] x2, x4;
    reg bank2;
    reg [127:0] pix2, d4;
    reg raw2, fill2;
    reg [7:0] mask2;
    reg [1:0] mode2;
    reg [4:0] alpha2;
    assign idle = !cell_valid && !v2 && !work_we;

    // 底下的颜色: 刚写的优先
    wire [127:0] dst = work_we && work_waddr == x2 ? work_wdata : v4 && x4 == x2 ? d4 : work_rdata;

    function automatic [15:0] blend(input reg [15:0] s, input reg [15:0] d, input reg [1:0] mode,
                                    input reg [4:0] a);
        reg [11:0] r, g, b, sr, sg, sb, dr, dg, db, ka, kd;
        begin
            {sr, sg, sb} = {7'b0, s[15:11], 6'b0, s[10:5], 7'b0, s[4:0]};
            {dr, dg, db} = {7'b0, d[15:11], 6'b0, d[10:5], 7'b0, d[4:0]};
            ka = {7'b0, a};
            kd = 12'd16 - ka;
            if (mode[1]) begin
                r = dr + ((sr * ka) >> 4);
                g = dg + ((sg * ka) >> 4);
                b = db + ((sb * ka) >> 4);
                blend = {r > 31 ? 5'd31 : r[4:0], g > 63 ? 6'd63 : g[5:0], b > 31 ? 5'd31 : b[4:0]};
            end else if (mode[0]) begin
                r = (sr * ka + dr * kd) >> 4;
                g = (sg * ka + dg * kd) >> 4;
                b = (sb * ka + db * kd) >> 4;
                blend = {r[4:0], g[5:0], b[4:0]};
            end else blend = s;
        end
    endfunction

    reg [127:0] result;
    integer k;
    always @(*) begin
        for (k = 0; k < 8; k = k + 1)
        result[16*k+:16] = mask2[k] ?
            blend(raw2 ? pix2[16*k+:16] : pal_rdata[16*k+:16], dst[16*k+:16], mode2, alpha2) :
            fill2 ? backdrop : dst[16*k+:16];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v2 <= 0;
            v4 <= 0;
            work_we <= 0;
            show_we <= 0;
        end else begin
            v2 <= cell_valid;
            x2 <= cell_x;
            bank2 <= cell_bank;
            pix2 <= cell_pix;
            raw2 <= cell_raw;
            mask2 <= cell_mask;
            fill2 <= cell_fill;
            mode2 <= cell_mode;
            alpha2 <= cell_alpha;

            work_we <= v2;
            show_we <= v2;
            work_waddr <= x2;
            show_waddr <= {bank2, x2};
            work_wdata <= result;

            v4 <= work_we;
            x4 <= work_waddr;
            d4 <= work_wdata;
        end
    end
endmodule
