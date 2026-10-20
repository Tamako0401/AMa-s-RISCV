// 视频输出 (rib 从设备 2, 0x2000_0000): 640x480@60, 像素时钟 25 MHz = clk/2。
// 画面按 320x240 画, 每个点放大成 2x2: 背景图块层 + 16x16 精灵层, 颜色经 256 项 RGB565 调色板。
// 寄存器、显存布局和用法见 docs/video.md; 渲染细节见 video_render.v。
//
// 显存只能整字写, 读回 0 (渲染端独占读口); 寄存器可读。
// 输出 RGB888 + 行场同步 (低有效) + de + pclk: 数据在 pclk 下降沿变化, 接收端在上升沿采样。
module video (
    input wire clk,
    input wire rst_n,
    input wire [31:0] addr_i,
    input wire [31:0] data_i,
    input wire [3:0] sel_i,
    input wire we_i,
    output wire [31:0] data_o,
    input wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input wire rsp_ready_i,

    output reg pclk,
    output reg hsync_n,
    output reg vsync_n,
    output reg de,
    output reg [23:0] rgb
);
    // 640x480@60 (VESA)
    localparam H_ACT = 640, H_FP = 16, H_SYNC = 96, H_TOTAL = 800;
    localparam V_ACT = 480, V_FP = 10, V_SYNC = 2, V_TOTAL = 525;

    // ---------------- 总线: 一拍接受, 下一拍响应 ----------------
    reg response_valid;
    reg [31:0] data_r;
    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i);
    assign rsp_valid_o = response_valid;
    assign data_o = data_r;
    wire fire = req_valid_i && req_ready_o;
    wire wen = fire && we_i;
    wire [3:0] page = addr_i[15:12];

    reg enable;
    reg [8:0] scroll_x;
    reg [7:0] scroll_y;
    reg [31:0] frame;
    reg [9:0] h, v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            response_valid <= 0;
            data_r <= 0;
            enable <= 0;
            scroll_x <= 0;
            scroll_y <= 0;
        end else begin
            if (response_valid && rsp_ready_i) response_valid <= 0;
            if (fire) begin
                response_valid <= 1;
                data_r <= 0;
            end
            if (fire && !we_i && page == 0)
                case (addr_i[11:2])
                    0: data_r <= {31'b0, enable};
                    1: data_r <= {8'b0, scroll_y, 7'b0, scroll_x};
                    2: data_r <= {31'b0, v >= V_ACT};
                    3: data_r <= frame;
                    default: data_r <= 0;
                endcase
            if (wen && page == 0)
                case (addr_i[11:2])
                    0: enable <= data_i[0];
                    1: {scroll_y, scroll_x} <= {data_i[23:16], data_i[8:0]};
                    default: ;
                endcase
        end
    end

    // ---------------- 显存 ----------------
    wire [ 7:0] lb_rdata;
    wire [15:0] color;
    wire [10:0] map_raddr, pat_raddr;
    wire [11:0] map_rdata;
    wire [31:0] pat_rdata, spr_rdata;
    wire [5:0] spr_raddr;
    wire lb_we;
    wire [9:0] lb_waddr;
    wire [7:0] lb_wdata;

    dpram #(
        .DW(16),
        .DP(256)
    ) u_palette (  // 0x2000_1000: 256 色, RGB565
        .clk(clk),
        .we(wen && page == 1),
        .waddr(addr_i[9:2]),
        .wdata(data_i[15:0]),
        .raddr(lb_rdata),
        .rdata(color)
    );
    dpram #(
        .DW(32),
        .DP(64)
    ) u_sprites (  // 0x2000_2000: 64 个精灵属性
        .clk(clk),
        .we(wen && page == 2),
        .waddr(addr_i[7:2]),
        .wdata(data_i),
        .raddr(spr_raddr),
        .rdata(spr_rdata)
    );
    dpram #(
        .DW(12),
        .DP(2048)
    ) u_map (  // 0x2000_4000: 64x32 格背景
        .clk(clk),
        .we(wen && page[3:1] == 2),
        .waddr(addr_i[12:2]),
        .wdata(data_i[11:0]),
        .raddr(map_raddr),
        .rdata(map_rdata)
    );
    dpram #(
        .DW(32),
        .DP(2048)
    ) u_patterns (  // 0x2000_8000: 256 个 8x8 图块
        .clk(clk),
        .we(wen && page[3:1] == 4),
        .waddr(addr_i[12:2]),
        .wdata(data_i),
        .raddr(pat_raddr),
        .rdata(pat_rdata)
    );
    // 行缓存: 两行轮换, 显示第 n 行时渲染第 n+1 行
    dpram #(
        .DW(8),
        .DP(1024)
    ) u_line (
        .clk(clk),
        .we(lb_we),
        .waddr(lb_waddr),
        .wdata(lb_wdata),
        .raddr({v[1], h[9:1]}),
        .rdata(lb_rdata)
    );

    // ---------------- 扫描 ----------------
    // pclk 为 1 的那一拍走一个像素。逻辑行 n 显示在物理行 2n、2n+1;
    // 在物理行 2n-2 开头开始渲染逻辑行 n (第 0 行在 522 行开头, 留给它 3 行)。
    wire tick = pclk;
    wire start = tick && h == 0 && !v[0] && (v < V_ACT - 2 || v == V_TOTAL - 3);
    wire [7:0] next_line = v == V_TOTAL - 3 ? 8'd0 : v[8:1] + 8'd1;

    video_render u_render (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .line(next_line),
        .scroll_x(scroll_x),
        .scroll_y(scroll_y),
        .map_raddr(map_raddr),
        .map_rdata(map_rdata),
        .pat_raddr(pat_raddr),
        .pat_rdata(pat_rdata),
        .spr_raddr(spr_raddr),
        .spr_rdata(spr_rdata),
        .lb_we(lb_we),
        .lb_waddr(lb_waddr),
        .lb_wdata(lb_wdata)
    );

    // 像素 (h, v) 的颜色在下一个 tick 才从调色板出来, 同步信号跟着晚一个 tick:
    // tick 时行缓存锁存 (h, v) 的地址 -> 下一拍调色板锁存色号 -> 再下一拍 (下一个 tick) 出颜色。
    reg de_d, hsync_d, vsync_d;
    // RGB565 -> RGB888: 高位补到低位
    wire [23:0] rgb888 = {color[15:11], color[15:13], color[10:5], color[10:9], color[4:0], color[4:2]};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pclk <= 0;
            h <= 0;
            v <= 0;
            frame <= 0;
            {de_d, hsync_d, vsync_d} <= 3'b011;
            {de, hsync_n, vsync_n} <= 3'b011;
            rgb <= 0;
        end else begin
            pclk <= !pclk;
            if (tick) begin
                h <= h == H_TOTAL - 1 ? 10'd0 : h + 1'b1;
                if (h == H_TOTAL - 1) v <= v == V_TOTAL - 1 ? 10'd0 : v + 1'b1;
                if (h == H_TOTAL - 1 && v == V_ACT - 1) frame <= frame + 1;
                de_d <= h < H_ACT && v < V_ACT;
                hsync_d <= !(h >= H_ACT + H_FP && h < H_ACT + H_FP + H_SYNC);
                vsync_d <= !(v >= V_ACT + V_FP && v < V_ACT + V_FP + V_SYNC);
                de <= de_d;
                hsync_n <= hsync_d;
                vsync_n <= vsync_d;
                rgb <= de_d && enable ? rgb888 : 24'h0;
            end
        end
    end
endmodule
