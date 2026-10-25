// 不旋转的精灵画一行: 一拍出一格 (8 个点)。
// 图案库一个字 8 个点; 精灵左边不一定对齐格子, 所以按顺序读出 n+1 个字, 每格由相邻两个字拼出:
//   格 t = ({字 t+1, 字 t} >> 8 * off) 的低 8 个点。
// 不翻转时字从 addr0 往上读; FLIP_X 时往下读、每个字倒过来 (rev), 拼法一样 (准备好的 addr0、off 见 disp_render)。
// 屏幕上 x0 <= x < x1 以外的点和色号 0 (透明) 不画。
module disp_span (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [12:0] addr0,
    input wire down,  // 字地址往下走 (FLIP_X)
    input wire [2:0] off,
    input wire [6:0] k0,  // 第一格
    input wire [3:0] cells,  // 格数, 1~9
    input wire [9:0] x0,
    input wire [9:0] x1,
    output wire busy,

    output wire [12:0] pat_raddr,
    input  wire [63:0] pat_rdata,

    output reg cell_valid,
    output reg [6:0] cell_x,
    output reg [63:0] cell_idx,
    output reg [7:0] cell_mask
);
    reg issuing, got;
    reg [3:0] t, n, got_t;
    reg [12:0] addr;
    reg dir, rev;
    reg [2:0] o;
    reg [6:0] k;
    reg [9:0] lo, hi;
    reg [63:0] prev;
    assign pat_raddr = addr;
    assign busy = issuing || got;

    // 这一拍到的字 (FLIP_X 时倒过来)
    wire [63:0] word;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_rev
            assign word[8*i+:8] = rev ? pat_rdata[8*(7-i)+:8] : pat_rdata[8*i+:8];
        end
    endgenerate
    wire [127:0] pair = {word, prev} >> {o, 3'b0};
    wire [6:0] kx = k + {3'b0, got_t} - 7'd1;
    reg [7:0] mask;
    integer j;
    always @(*) begin
        for (j = 0; j < 8; j = j + 1)
        mask[j] = pair[8*j+:8] != 0 && {kx, j[2:0]} >= lo && {kx, j[2:0]} < hi;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issuing <= 0;
            got <= 0;
            cell_valid <= 0;
        end else begin
            cell_valid <= 0;
            if (start) begin
                issuing <= 1;
                t <= 0;
                n <= cells;
                addr <= addr0;
                dir <= down;
                rev <= down;
                o <= off;
                k <= k0;
                lo <= x0;
                hi <= x1;
            end else if (issuing) begin
                t <= t + 1'b1;
                addr <= dir ? addr - 1'b1 : addr + 1'b1;
                if (t == n) issuing <= 0;
            end
            got   <= issuing;
            got_t <= t;
            if (got) begin
                prev <= word;
                if (got_t != 0) begin
                    cell_valid <= 1;
                    cell_x <= kx;
                    cell_idx <= pair[63:0];
                    cell_mask <= mask;
                end
            end
        end
    end
endmodule
