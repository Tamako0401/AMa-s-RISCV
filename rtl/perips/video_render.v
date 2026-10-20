// 行渲染: 收到 start 后把逻辑行 line (0~239) 画进行缓存的 line[0] 号缓冲, 先背景后精灵。
// 每像素存 {调色板号, 色号} 8 位, 调色板查表在显示端做。
//
// 背景: 64x32 格的图块表, 每格 {调色板号[11:8], 图块号[7:0]}; 按 scroll 偏移取 41 格, 每格 8 个像素。
// 精灵: 64 个, 每个 16x16, 由图块 t (左上)、t+1 (右上)、t+2 (左下)、t+3 (右下) 拼成;
//       属性 {使能[31], 调色板号[29:26], 图块号[25:18], y[17:9], x[8:0]}, x、y 按 512 回绕 (可以半出屏);
//       色号 0 透明。从 63 号画到 0 号, 小号盖在上面。
// 图块: 8x8, 每行一个字, 左起第 i 个像素在 [4i+3:4i]。
// 耗时: 背景 41 x 11 拍, 每个精灵 2 拍, 落在本行的再加 18 拍; 最坏约 1700 拍, 显示端给 2 个物理行 (3200 拍)。
module video_render (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [7:0] line,
    input wire [8:0] scroll_x,
    input wire [7:0] scroll_y,

    output wire [10:0] map_raddr,
    input  wire [11:0] map_rdata,
    output reg  [10:0] pat_raddr,
    input  wire [31:0] pat_rdata,
    output wire [ 5:0] spr_raddr,
    input  wire [31:0] spr_rdata,

    output reg lb_we,
    output reg [9:0] lb_waddr,  // {缓冲号, x}
    output reg [7:0] lb_wdata
);
    localparam IDLE = 0, BG_MAP = 1, BG_PAT = 2, BG_LATCH = 3, BG_PIX = 4;
    localparam SP_ATTR = 5, SP_CHECK = 6, SP_RIGHT = 7, SP_LATCH = 8, SP_PIX = 9;

    reg [ 3:0] state;
    reg [ 7:0] y;
    reg [ 8:0] sx;
    reg [ 7:0] by;  // 背景里的行 = y + scroll_y, 按 256 回绕
    reg [ 5:0] col;  // 背景第几格, 0~40
    reg [ 5:0] spr;  // 精灵号, 63~0
    reg [ 3:0] i;  // 格内 / 精灵内第几个像素
    reg [ 3:0] pal;
    reg [ 8:0] px;  // 精灵左边的 x
    reg [ 7:0] tile;  // 精灵这一行左半的图块
    reg [ 2:0] row;
    reg [63:0] pixels;  // 背景用低 32 位; 精灵 {右半, 左半}

    // 背景格 col 在图块表里的位置
    assign map_raddr = {by[7:3], sx[8:3] + col};
    assign spr_raddr = spr;

    // 精灵 spr 和本行的关系
    wire [8:0] dy = {1'b0, y} - spr_rdata[17:9];
    wire hit = spr_rdata[31] && dy < 16;
    wire [7:0] first_tile = spr_rdata[25:18] + (dy[3] ? 8'd2 : 8'd0);

    always @(*) begin
        case (state)
            BG_PAT:   pat_raddr = {map_rdata[7:0], by[2:0]};
            SP_CHECK: pat_raddr = {first_tile, dy[2:0]};
            default:  pat_raddr = {tile + 8'd1, row};  // SP_RIGHT
        endcase
    end

    wire [9:0] bg_x = {1'b0, col, i[2:0]} - {7'b0, sx[2:0]};  // 负数回绕成大数, 下面一并按 >= 320 丢掉
    wire [8:0] sp_x = px + {5'b0, i};
    wire [3:0] color = pixels[{i, 2'b00}+:4];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            lb_we <= 0;
        end else begin
            lb_we <= 0;
            case (state)
                IDLE:
                if (start) begin
                    y <= line;
                    sx <= scroll_x;
                    by <= line + scroll_y;
                    col <= 0;
                    state <= BG_MAP;
                end
                BG_MAP:  state <= BG_PAT;
                BG_PAT: begin
                    pal   <= map_rdata[11:8];
                    state <= BG_LATCH;
                end
                BG_LATCH: begin
                    pixels <= {32'b0, pat_rdata};
                    i <= 0;
                    state <= BG_PIX;
                end
                BG_PIX: begin
                    lb_we <= bg_x < 320;
                    lb_waddr <= {y[0], bg_x[8:0]};
                    lb_wdata <= {pal, color};
                    i <= i + 1'b1;
                    if (i == 7) begin
                        col   <= col + 1'b1;
                        spr   <= 63;
                        state <= col == 40 ? SP_ATTR : BG_MAP;
                    end
                end
                SP_ATTR: state <= SP_CHECK;
                SP_CHECK:
                if (hit) begin
                    px <= spr_rdata[8:0];
                    pal <= spr_rdata[29:26];
                    tile <= first_tile;
                    row <= dy[2:0];
                    state <= SP_RIGHT;
                end else begin
                    spr   <= spr - 1'b1;
                    state <= spr == 0 ? IDLE : SP_ATTR;
                end
                SP_RIGHT: begin
                    pixels[31:0] <= pat_rdata;
                    state <= SP_LATCH;
                end
                SP_LATCH: begin
                    pixels[63:32] <= pat_rdata;
                    i <= 0;
                    state <= SP_PIX;
                end
                SP_PIX: begin
                    lb_we <= color != 0 && sp_x < 320;
                    lb_waddr <= {y[0], sp_x};
                    lb_wdata <= {pal, color};
                    i <= i + 1'b1;
                    if (i == 15) begin
                        spr   <= spr - 1'b1;
                        state <= spr == 0 ? IDLE : SP_ATTR;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
