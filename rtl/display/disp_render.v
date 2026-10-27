// 画一条逻辑行 (640 点) 进行缓存: 收到 go 后按顺序
//   1. 背景: 81 个图块的这一行 (卷动不对齐格子时多一个), 拼成 80 格; 游戏区 (clip) 外和透明的点写底色。
//   2. 摄像头小窗: 这一行落在小窗里时, 一拍读一个点 (RGB332 扩成 RGB565), 不透明, 不受 clip 影响。
//   3. 对象列表 (disp_scan 写好的, 和这一行相交的精灵, 按表的顺序) 里的每个精灵:
//      读列表 -> 读精灵表 -> 查图案表 -> 算外框、裁剪 -> 不旋转交给 disp_span, AFFINE 再算行首的图案坐标交给 disp_affine。
//      准备好一个就等画的那个画完马上开始, 接着准备下一个: 准备 (约 6 拍) 和画上一个重叠。
// 产出的都是"格子" (8 个点) 交给 disp_blend。算法同 game/tools/refmodel.py 开头的规格。
module disp_render (
    input wire clk,
    input wire rst_n,
    input wire go,
    input wire [8:0] line,
    output wire busy,

    input wire [8:0] scroll_x,
    input wire [8:0] scroll_y,
    input wire [9:0] clip0,
    input wire [9:0] clip1,
    input wire win_on,
    input wire [11:0] win_x,
    input wire [11:0] win_y,

    output reg  [ 7:0] list_raddr,
    input  wire [ 8:0] list_rdata,
    input  wire [ 7:0] count0,
    input  wire [ 7:0] count1,
    output wire [ 8:0] spr_raddr,
    input  wire [63:0] spr_rdata,
    output reg  [ 9:0] img_raddr,
    input  wire [15:0] img_rdata,
    output wire [11:0] map_raddr,
    input  wire [ 9:0] map_rdata,
    output reg  [12:0] pat_raddr,
    input  wire [63:0] pat_rdata,
    output wire [14:0] win_raddr,
    input  wire [ 7:0] win_rdata,

    output wire cell_valid,
    output reg [6:0] cell_x,
    output wire cell_bank,
    output reg [127:0] cell_pix,
    output reg cell_raw,
    output reg [7:0] cell_mask,
    output reg cell_fill,
    output reg [1:0] cell_mode,
    output reg [4:0] cell_alpha
);
    `include "disp_tables.vh"
    localparam ALPHA = 0, ADD = 1, FLIP_X = 2, FLIP_Y = 3, AFFINE = 4, CLIP = 5;  // flags 的位
    localparam IDLE = 0, BG = 1, WIN_SETUP = 2, WIN = 3, OBJ_LIST = 4, OBJ_SPR = 5, OBJ_IMG = 6, OBJ_GEO = 7;
    localparam OBJ_PREP = 8, OBJ_MUL = 9, OBJ_SUM = 10, OBJ_READY = 11, OBJ_WAIT = 12;

    reg [3:0] state;
    reg [8:0] ln;
    assign busy = state != IDLE;
    assign cell_bank = ln[0];

    // ---------------- 背景 ----------------
    reg [6:0] bc;  // 发出第几个图块, 0~80
    reg b1, b2, b3;
    reg [6:0] c1, c2, c3;
    reg [63:0] bg_prev;
    reg [ 2:0] row_in;
    reg [ 5:0] tile_row;
    reg [9:0] lo_clip, hi_clip;
    wire [5:0] tile_col = scroll_x[8:3] + bc[5:0];
    assign map_raddr = {tile_row, tile_col};
    wire [127:0] bg_pair = {pat_rdata, bg_prev} >> {scroll_x[2:0], 3'b0};
    wire [6:0] bg_k = c3 - 7'd1;
    reg [7:0] bg_mask;
    reg [127:0] bg_pix;
    integer j;
    always @(*) begin
        for (j = 0; j < 8; j = j + 1) begin
            bg_mask[j] = bg_pair[8*j+:8] != 0 && {bg_k, j[2:0]} >= lo_clip && {bg_k, j[2:0]} < hi_clip;
            bg_pix[16*j+:16] = {8'b0, bg_pair[8*j+:8]};
        end
    end
    reg bg_valid;
    reg [6:0] bg_k_q;
    reg [127:0] bg_pix_q;
    reg [7:0] bg_mask_q;

    // ---------------- 小窗 ----------------
    reg signed [12:0] w_row;
    reg [9:0] wx, wx_end;  // 发出的点, 结束点 (不含)
    reg signed [12:0] w_left;  // 小窗左边
    reg w1;
    reg [9:0] w1_x;
    reg w1_last;
    reg [127:0] w_acc;
    reg [7:0] w_acc_mask;
    reg win_valid;
    reg [6:0] win_x_q;
    reg [127:0] win_pix_q;
    reg [7:0] win_mask_q;
    wire signed [12:0] w_col = $signed({3'b0, wx}) - w_left;
    assign win_raddr = {w_row[6:0], 7'b0} + {2'b0, w_row[6:0], 5'b0} + {2'b0, w_col[12:0]};
    wire [  7:0] c332 = win_rdata;
    wire [ 15:0] c565 = {c332[7:5], c332[7:6], c332[4:2], c332[4:2], c332[1:0], c332[1:0], c332[1]};
    wire [127:0] w_acc_next = w_acc | ({112'b0, c565} << {w1_x[2:0], 4'b0});
    wire [  7:0] w_mask_next = w_acc_mask | (8'd1 << w1_x[2:0]);

    // ---------------- 对象 ----------------
    reg [7:0] oj, ocount;
    reg signed [13:0] o_x, o_y;
    reg [7:0] o_scale, o_angle;
    reg [4:0] o_alpha;
    reg [5:0] o_flags;
    assign spr_raddr = list_rdata;  // OBJ_SPR 那一拍列表到了, 直接去读精灵表
    always @(*) list_raddr = {ln[0], oj[6:0]};

    // 图案表到了: 外框和裁剪
    wire [2:0] code = img_rdata[15:13];
    wire [2:0] lg = code + 3'd2;
    wire [13:0] scaled = {6'b0, o_scale} << lg;
    wire [9:0] quarter = scaled[13:4];
    wire [11:0] tripled = {2'b0, quarter} + {1'b0, quarter, 1'b0};
    wire signed [13:0] side = o_flags[AFFINE] ? $signed(
        {3'b0, tripled[11:1]}
    ) : $signed(
        14'd1 << lg
    );
    wire signed [13:0] left = o_x - (side >>> 1);
    wire signed [13:0] lo = o_flags[CLIP] ? $signed({4'b0, clip0}) : 14'sd0;
    wire signed [13:0] hi = o_flags[CLIP] ? $signed({4'b0, clip1}) : 14'sd640;
    wire signed [13:0] right = left + side;

    reg g_ok, g_aff, g_fx, g_fy;
    reg [ 2:0] g_lg;
    reg [12:0] g_base;
    reg signed [13:0] g_left, g_x0, g_x1, g_v;

    // 不旋转: disp_span 的参数
    wire signed [13:0] g_side = 14'sd1 <<< g_lg;
    wire [6:0] k0 = g_x0[9:3];
    wire signed [13:0] last_x = g_x1 - 14'sd1;
    wire [6:0] k_end = last_x[9:3];
    wire [6:0] cells = k_end - k0 + 7'd1;
    wire [5:0] vv = g_fy ? g_side[5:0] - 6'd1 - g_v[5:0] : g_v[5:0];
    wire [12:0] row_base = g_base + ({7'b0, vv} << (g_lg - 3'd3));
    wire signed [13:0] fwd = $signed(
        {4'b0, k0, 3'b0}
    ) - g_left;  // 第一格左边在图案里的 u
    wire signed [13:0] rev = g_side - 14'sd1 + g_left - $signed(
        {4'b0, k0, 3'b0}
    );  // FLIP_X: 第一格左边的 u'
    wire signed [13:0] first = g_fx ? rev : fwd;
    wire signed [13:0] first_word = first >>> 3;
    wire [12:0] span_addr = row_base + first_word[12:0];
    wire [2:0] span_off = g_fx ? ~rev[2:0] : fwd[2:0];
    wire span_busy, aff_busy;
    wire launch = state == OBJ_READY && !span_busy && !aff_busy;
    wire span_start = launch && !g_aff;

    // 旋转: 行首的图案坐标
    wire signed [16:0] cos_v = sin_q14(o_angle + 8'd64);
    wire signed [16:0] sin_v = sin_q14(o_angle);
    wire signed [17:0] inv_v = $signed({1'b0, inv_q12(o_scale)});
    wire signed [34:0] pa_full = cos_v * inv_v;
    wire signed [34:0] pb_full = sin_v * inv_v;
    reg signed [19:0] pa, pb;
    reg signed [13:0] dx0, dy;
    reg signed [31:0] m1, m2, m3, m4;
    wire signed [31:0] half = $signed(32'd1 << ({2'b0, g_lg} + 5'd12));
    wire signed [31:0] u2 = m1 + m2 + half;
    wire signed [31:0] v2 = m4 - m3 + half;
    wire aff_start = launch && g_aff;

    wire [12:0] span_raddr, aff_raddr;
    wire span_valid, aff_valid;
    wire [6:0] span_x, aff_x;
    wire [63:0] span_idx, aff_idx;
    wire [7:0] span_mask, aff_mask;

    disp_span u_span (
        .clk(clk),
        .rst_n(rst_n),
        .start(span_start),
        .addr0(span_addr),
        .down(g_fx),
        .off(span_off),
        .k0(k0),
        .cells(cells[3:0]),
        .x0(g_x0[9:0]),
        .x1(g_x1[9:0]),
        .busy(span_busy),
        .pat_raddr(span_raddr),
        .pat_rdata(pat_rdata),
        .cell_valid(span_valid),
        .cell_x(span_x),
        .cell_idx(span_idx),
        .cell_mask(span_mask)
    );

    wire signed [13:0] aff_n = g_x1 - g_x0;
    disp_affine u_affine (
        .clk(clk),
        .rst_n(rst_n),
        .start(aff_start),
        .x0(g_x0[9:0]),
        .n(aff_n[10:0]),
        .u2(u2),
        .v2(v2),
        .du(pa <<< 1),
        .dv(pb <<< 1),
        .lg(g_lg),
        .base(g_base),
        .flip_x(g_fx),
        .flip_y(g_fy),
        .busy(aff_busy),
        .pat_raddr(aff_raddr),
        .pat_rdata(pat_rdata),
        .cell_valid(aff_valid),
        .cell_x(aff_x),
        .cell_idx(aff_idx),
        .cell_mask(aff_mask)
    );

    // 对象的混合方式: 准备时算好, 开始画时交给正在画的那个
    reg [1:0] o_mode, l_mode;
    reg [4:0] o_alpha_eff, l_alpha;
    reg l_aff;  // 正在画的是旋转的

    // ---------------- 共用的读口 ----------------
    always @(*) begin
        img_raddr = state == BG ? map_rdata : spr_rdata[41:32];
        case (state)
            BG: pat_raddr = img_rdata[12:0] + {10'b0, row_in};
            default: pat_raddr = l_aff ? aff_raddr : span_raddr;
        endcase
    end

    // ---------------- 交给 disp_blend 的格子 ----------------
    assign cell_valid = bg_valid || win_valid || span_valid || aff_valid;
    wire [127:0] obj_pix;
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_obj_pix
            assign obj_pix[16*gi+:16] = {8'b0, span_valid ? span_idx[8*gi+:8] : aff_idx[8*gi+:8]};
        end
    endgenerate
    always @(*) begin
        cell_x = bg_valid ? bg_k_q : win_valid ? win_x_q : span_valid ? span_x : aff_x;
        cell_pix = bg_valid ? bg_pix_q : win_valid ? win_pix_q : obj_pix;
        cell_raw = win_valid;
        cell_mask = bg_valid ? bg_mask_q : win_valid ? win_mask_q : span_valid ? span_mask : aff_mask;
        cell_fill = bg_valid;
        cell_mode = bg_valid || win_valid ? 2'b00 : l_mode;
        cell_alpha = l_alpha;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            b1 <= 0;
            b2 <= 0;
            b3 <= 0;
            w1 <= 0;
            bg_valid <= 0;
            win_valid <= 0;
        end else begin
            bg_valid <= 0;
            win_valid <= 0;
            b1 <= 0;
            b2 <= b1;
            b3 <= b2;
            c2 <= c1;
            c3 <= c2;
            w1 <= 0;
            if (go) begin
                state <= BG;
                ln <= line;
                bc <= 0;
                tile_row <= line[8:3] + scroll_y[8:3] + {5'b0, line[2:0] + scroll_y[2:0] > 7};
                row_in <= line[2:0] + scroll_y[2:0];
                lo_clip <= clip0;
                hi_clip <= clip1;
                b2 <= 0;
                b3 <= 0;
            end else
                case (state)
                    BG: begin
                        if (bc <= 80) begin
                            b1 <= 1;
                            c1 <= bc;
                            bc <= bc + 1'b1;
                        end
                        if (b3) begin
                            bg_prev <= pat_rdata;
                            if (c3 != 0) begin
                                bg_valid <= 1;
                                bg_k_q <= bg_k;
                                bg_pix_q <= bg_pix;
                                bg_mask_q <= bg_mask;
                            end
                            if (c3 == 80) state <= WIN_SETUP;
                        end
                    end
                    WIN_SETUP: begin
                        w_row <= $signed({4'b0, ln}) - $signed({win_y[11], win_y});
                        w_left <= $signed({win_x[11], win_x});
                        wx <= win_x[11] ? 10'd0 : win_x[9:0];
                        wx_end <= $signed(
                            {win_x[11], win_x}
                        ) + 13'sd160 > 13'sd640 ? 10'd640 : win_x[9:0] + 10'd160;
                        w_acc <= 0;
                        w_acc_mask <= 0;
                        state <= WIN;  // 小窗不在这一行 (或整个在屏外) 就跳过: 下一拍在 WIN 里判断
                    end
                    WIN: begin
                        if (!win_on || w_row < 0 || w_row >= 120 || w_left >= 640 || w_left <= -160) begin
                            state <= OBJ_LIST;
                            oj <= 0;
                            ocount <= ln[0] ? count1 : count0;
                        end else begin
                            if (wx < wx_end) begin
                                w1 <= 1;
                                w1_x <= wx;
                                w1_last <= wx + 1'b1 == wx_end;
                                wx <= wx + 1'b1;
                            end
                            if (w1) begin
                                if (w1_x[2:0] == 7 || w1_last) begin
                                    win_valid <= 1;
                                    win_x_q <= w1_x[9:3];
                                    win_pix_q <= w_acc_next;
                                    win_mask_q <= w_mask_next;
                                    w_acc <= 0;
                                    w_acc_mask <= 0;
                                end else begin
                                    w_acc <= w_acc_next;
                                    w_acc_mask <= w_mask_next;
                                end
                                if (w1_last) begin
                                    state <= OBJ_LIST;
                                    oj <= 0;
                                    ocount <= ln[0] ? count1 : count0;
                                end
                            end
                        end
                    end
                    OBJ_LIST: state <= oj == ocount ? OBJ_WAIT : OBJ_SPR;
                    OBJ_SPR:  state <= OBJ_IMG;
                    OBJ_IMG: begin
                        o_x <= {{2{spr_rdata[11]}}, spr_rdata[11:0]};
                        o_y <= {{2{spr_rdata[23]}}, spr_rdata[23:12]};
                        o_scale <= spr_rdata[31:24];
                        o_angle <= spr_rdata[63:56];
                        o_alpha <= spr_rdata[52:48];
                        o_flags <= spr_rdata[47:42];
                        state <= OBJ_GEO;
                    end
                    OBJ_GEO: begin
                        g_ok <= code != 0 && code <= 4;
                        g_aff <= o_flags[AFFINE];
                        g_fx <= o_flags[FLIP_X];
                        g_fy <= o_flags[FLIP_Y];
                        g_lg <= lg;
                        g_base <= img_rdata[12:0];
                        g_left <= left;
                        g_x0 <= left > lo ? left : lo;
                        g_x1 <= right < hi ? right : hi;
                        g_v <= $signed({5'b0, ln}) - (o_y - ((14'sd1 <<< lg) >>> 1));
                        o_mode <= {o_flags[ADD], !o_flags[ADD] && o_flags[ALPHA] && o_alpha < 16};
                        o_alpha_eff <= o_flags[ALPHA] ? o_alpha : 5'd16;
                        state <= OBJ_PREP;
                    end
                    OBJ_PREP: begin
                        // 位切片本身是无符号的, $signed 显式标回有符号 (位宽相同, 语义不变)
                        pa  <= $signed(pa_full[33:14]);
                        pb  <= $signed(pb_full[33:14]);
                        dx0 <= ((g_x0 - o_x) <<< 1) + 14'sd1;
                        dy  <= (($signed({5'b0, ln}) - o_y) <<< 1) + 14'sd1;
                        if (!g_ok || g_x0 >= g_x1) begin
                            oj <= oj + 1'b1;
                            state <= OBJ_LIST;
                        end else state <= g_aff ? OBJ_MUL : OBJ_READY;
                    end
                    OBJ_MUL: begin
                        m1 <= pa * dx0;
                        m2 <= pb * dy;
                        m3 <= pb * dx0;
                        m4 <= pa * dy;
                        state <= OBJ_SUM;
                    end
                    OBJ_SUM:  state <= OBJ_READY;
                    OBJ_READY:
                    if (launch) begin
                        l_aff <= g_aff;
                        l_mode <= o_mode;
                        l_alpha <= o_alpha_eff;
                        oj <= oj + 1'b1;
                        state <= OBJ_LIST;
                    end
                    OBJ_WAIT: if (!span_busy && !aff_busy) state <= IDLE;
                    default:  state <= IDLE;
                endcase
        end
    end
endmodule
