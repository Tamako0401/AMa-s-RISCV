// 新显示 (720p, 640x360 逐行渲染 + 文字层), RIB 从设备。规格见 game/tools/refmodel.py 开头, 寄存器和地址见 docs/display.md。
//
// 两个时钟: clk (sys, CPU 写、渲染) 和 pclk (74.25 MHz, 扫描、文字层)。跨时钟域只有:
//   - 显示行缓存、文字层、字库: clk 写, pclk 读 (dpram2c);
//   - "开始第几对物理行": disp_timing 翻转 ev_tgl, 这里同步后再读 ev_pair (已稳定);
//   - 开显示、整体混色: 在 clk 域场消隐开头更新, pclk 域要到下一帧第 0 行才用, 中间隔 30 行。
// 每逻辑行的流水: 显示第 n 行时, 渲染第 n+1 行, 扫描 (Y 分桶) 第 n+2 行。
// 场消隐开头 (第 720 条物理行) 如果 CPU 提交过 (COMMIT), 精灵表前后台交换, 帧参数换成 CPU 写的新值。
// 内存只能整字写, 读回 0; 寄存器可读。
// 存储: 图案库和文字层放 DRM, 其余的表用 LUT RAM (*_lut) -- 片上 DRM 是最紧的资源 (docs/display.md)。
module display (
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

    input wire pclk,
    output wire pclk_o,  // 给 HDMI 芯片: 数据在 pclk 上升沿变, 芯片在 pclk_o (反相) 上升沿采样
    output wire hsync_n,
    output wire vsync_n,
    output wire de,
    output wire [23:0] rgb,

    // 小窗: 读视觉输入的小图 (RGB332), 地址 y * 160 + x, 数据下一拍有效 (clk 域)
    output wire [14:0] win_raddr,
    input  wire [ 7:0] win_rdata
);
    assign pclk_o = !pclk;

    // ---------------- 总线: 一拍接受, 下一拍响应 ----------------
    reg response_valid;
    reg [31:0] data_r;
    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i);
    assign rsp_valid_o = response_valid;
    assign data_o = data_r;
    wire fire = req_valid_i && req_ready_o;
    wire wen = fire && we_i;
    wire [3:0] region = addr_i[19:16];
    wire [3:0] page = addr_i[15:12];
    wire low = region == 0;

    // CPU 写的帧参数 (提交后生效) 和正在用的
    reg [1:0] ctrl, a_ctrl;
    reg [15:0] backdrop, a_backdrop;
    reg [9:0] clip0, clip1, a_clip0, a_clip1;
    reg [11:0] win_x, win_y, a_win_x, a_win_y;
    reg [8:0] scroll_x, scroll_y, a_scroll_x, a_scroll_y;
    reg [15:0] fade_color, a_fade_color;
    reg [4:0] fade_level, a_fade_level;
    reg [9:0] sprite_n, a_sprite_n;
    reg pending, vblank;
    reg [31:0] frame, line_max, line_max_cur, overrun, dropped;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            response_valid <= 0;
            data_r <= 0;
        end else begin
            if (response_valid && rsp_ready_i) response_valid <= 0;
            if (fire) begin
                response_valid <= 1;
                data_r <= 0;
            end
            if (fire && !we_i && low && page == 0)
                case (addr_i[11:2])
                    0: data_r <= {30'b0, ctrl};
                    1: data_r <= {16'b0, backdrop};
                    2: data_r <= {6'b0, clip1, 6'b0, clip0};
                    3: data_r <= {4'b0, win_y, 4'b0, win_x};
                    4: data_r <= {7'b0, scroll_y, 7'b0, scroll_x};
                    5: data_r <= {11'b0, fade_level, fade_color};
                    6: data_r <= {22'b0, sprite_n};
                    7: data_r <= {31'b0, pending};
                    8: data_r <= {31'b0, vblank};
                    9: data_r <= frame;
                    10: data_r <= line_max;
                    11: data_r <= overrun;
                    12: data_r <= dropped;
                    default: data_r <= 0;
                endcase
        end
    end

    // ---------------- 扫描 (pclk 域) 和"开始第几对物理行" ----------------
    wire [10:0] h;
    wire [9:0] v;
    wire ev_tgl;
    wire [8:0] ev_pair;
    disp_timing u_timing (
        .pclk(pclk),
        .rst_n(rst_n),
        .h(h),
        .v(v),
        .ev_tgl(ev_tgl),
        .ev_pair(ev_pair)
    );

    reg [2:0] ev_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) ev_sync <= 0;
        else ev_sync <= {ev_sync[1:0], ev_tgl};
    wire ev = ev_sync[2] != ev_sync[1];
    // 第 p 对物理行开始: 显示逻辑行 p (p < 360); 渲染 p+1、扫描 p+2。第 0 行在场消隐最后两对里先扫描、再渲染。
    wire render_go = ev && (ev_pair <= 358 || ev_pair == 374);
    wire [8:0] render_line = ev_pair == 374 ? 9'd0 : ev_pair + 1'b1;
    wire scan_go = ev && (ev_pair <= 357 || ev_pair >= 373);
    wire [8:0] scan_line = ev_pair == 373 ? 9'd0 : ev_pair == 374 ? 9'd1 : ev_pair + 9'd2;
    wire frame_end = ev && ev_pair == 360;

    // ---------------- 精灵表、Y 分桶 ----------------
    wire spr_we = wen && low && page == 4;
    wire img_we = wen && low && page == 2;
    wire [8:0] spr_raddr, yr_raddr;
    wire [63:0] spr_rdata;
    wire [25:0] yr_rdata;
    wire front;
    disp_sprites u_sprites (
        .clk(clk),
        .rst_n(rst_n),
        .swap(frame_end && pending),
        .front(front),
        .we(spr_we),
        .waddr(addr_i[11:3]),
        .wword(addr_i[2]),
        .wdata(data_i),
        .size_we(img_we),
        .size_waddr(addr_i[11:2]),
        .size_wdata(data_i[15:13]),
        .raddr(spr_raddr),
        .rdata(spr_rdata),
        .yr_raddr(yr_raddr),
        .yr_rdata(yr_rdata)
    );

    wire list_we, scan_busy, scan_drop;
    wire [7:0] list_waddr, list_raddr, count0, count1;
    wire [8:0] list_wdata, list_rdata;
    disp_scan u_scan (
        .clk(clk),
        .rst_n(rst_n),
        .go(scan_go),
        .line(scan_line),
        .count(a_sprite_n),
        .busy(scan_busy),
        .yr_raddr(yr_raddr),
        .yr_rdata(yr_rdata),
        .list_we(list_we),
        .list_waddr(list_waddr),
        .list_wdata(list_wdata),
        .count0(count0),
        .count1(count1),
        .dropped(scan_drop)
    );
    dpram_lut #(
        .DW(9),
        .DP(256)
    ) u_list (  // 对象列表: {行号[0], 第几个}
        .clk(clk),
        .we(list_we),
        .waddr(list_waddr),
        .wdata(list_wdata),
        .raddr(list_raddr),
        .rdata(list_rdata)
    );

    // ---------------- 图案表、图案库、背景图块表 ----------------
    wire [9:0] img_raddr, map_rdata;
    wire [15:0] img_rdata;
    wire [11:0] map_raddr;
    wire [12:0] pat_raddr;
    wire [63:0] pat_rdata;
    dpram_lut #(
        .DW(16),
        .DP(1024)
    ) u_images (  // {尺寸码[15:13], 起始字[12:0]}
        .clk(clk),
        .we(img_we),
        .waddr(addr_i[11:2]),
        .wdata(data_i[15:0]),
        .raddr(img_raddr),
        .rdata(img_rdata)
    );
    dpram #(
        .DW(32),
        .DP(8192)
    ) u_pat_lo (  // 每个字的左 4 个点
        .clk(clk),
        .we(wen && region == 4 && !addr_i[2]),
        .waddr(addr_i[15:3]),
        .wdata(data_i),
        .raddr(pat_raddr),
        .rdata(pat_rdata[31:0])
    );
    dpram #(
        .DW(32),
        .DP(8192)
    ) u_pat_hi (
        .clk(clk),
        .we(wen && region == 4 && addr_i[2]),
        .waddr(addr_i[15:3]),
        .wdata(data_i),
        .raddr(pat_raddr),
        .rdata(pat_rdata[63:32])
    );
    dpram_lut #(
        .DW(10),
        .DP(4096)
    ) u_map (
        .clk(clk),
        .we(wen && region == 1),
        .waddr(addr_i[13:2]),
        .wdata(data_i[9:0]),
        .raddr(map_raddr),
        .rdata(map_rdata)
    );

    // ---------------- 渲染、混合、行缓存 ----------------
    wire render_busy, blend_idle;
    wire cell_valid, cell_bank, cell_raw, cell_fill;
    wire [  6:0] cell_x;
    wire [127:0] cell_pix;
    wire [  7:0] cell_mask;
    wire [  1:0] cell_mode;
    wire [  4:0] cell_alpha;
    disp_render u_render (
        .clk(clk),
        .rst_n(rst_n),
        .go(render_go),
        .line(render_line),
        .busy(render_busy),
        .scroll_x(a_scroll_x),
        .scroll_y(a_scroll_y),
        .clip0(a_clip0),
        .clip1(a_clip1),
        .win_on(a_ctrl[1]),
        .win_x(a_win_x),
        .win_y(a_win_y),
        .list_raddr(list_raddr),
        .list_rdata(list_rdata),
        .count0(count0),
        .count1(count1),
        .spr_raddr(spr_raddr),
        .spr_rdata(spr_rdata),
        .img_raddr(img_raddr),
        .img_rdata(img_rdata),
        .map_raddr(map_raddr),
        .map_rdata(map_rdata),
        .pat_raddr(pat_raddr),
        .pat_rdata(pat_rdata),
        .win_raddr(win_raddr),
        .win_rdata(win_rdata),
        .cell_valid(cell_valid),
        .cell_x(cell_x),
        .cell_bank(cell_bank),
        .cell_pix(cell_pix),
        .cell_raw(cell_raw),
        .cell_mask(cell_mask),
        .cell_fill(cell_fill),
        .cell_mode(cell_mode),
        .cell_alpha(cell_alpha)
    );

    wire [ 63:0] pal_raddr;
    wire [127:0] pal_rdata;
    disp_palette u_palette (
        .clk(clk),
        .we(wen && low && page == 1),
        .waddr(addr_i[9:2]),
        .wdata(data_i[15:0]),
        .raddr(pal_raddr),
        .rdata(pal_rdata)
    );

    wire [6:0] work_raddr, work_waddr;
    wire [127:0] work_rdata, work_wdata;
    wire work_we, show_we;
    wire [7:0] show_waddr;
    disp_blend u_blend (
        .clk(clk),
        .rst_n(rst_n),
        .cell_valid(cell_valid),
        .cell_x(cell_x),
        .cell_bank(cell_bank),
        .cell_pix(cell_pix),
        .cell_raw(cell_raw),
        .cell_mask(cell_mask),
        .cell_fill(cell_fill),
        .cell_mode(cell_mode),
        .cell_alpha(cell_alpha),
        .backdrop(a_backdrop),
        .idle(blend_idle),
        .pal_raddr(pal_raddr),
        .pal_rdata(pal_rdata),
        .work_raddr(work_raddr),
        .work_rdata(work_rdata),
        .work_we(work_we),
        .work_waddr(work_waddr),
        .work_wdata(work_wdata),
        .show_we(show_we),
        .show_waddr(show_waddr)
    );
    dpram_lut #(
        .DW(128),
        .DP(80)
    ) u_work (  // 工作行: 正在画的那一行, 混合时读出底下的颜色
        .clk(clk),
        .we(work_we),
        .waddr(work_waddr),
        .wdata(work_wdata),
        .raddr(work_raddr),
        .rdata(work_rdata)
    );

    wire [  7:0] show_raddr;
    wire [127:0] show_rdata;
    dpram2c_lut #(
        .DW(128),
        .DP(256)
    ) u_show (  // 显示行: {行号[0], 格号}, 两行轮换
        .wclk(clk),
        .we(show_we),
        .waddr(show_waddr),
        .wdata(work_wdata),
        .rclk(pclk),
        .raddr(show_raddr),
        .rdata(show_rdata)
    );

    // ---------------- 文字层、显示端 ----------------
    wire [12:0] text_raddr;
    wire [11:0] text_rdata;
    wire [10:0] font_raddr;
    wire [ 7:0] font_rdata;
    dpram2c #(
        .DW(12),
        .DP(8192)
    ) u_text (  // 160x45 格 {颜色, 字符}
        .wclk(clk),
        .we(wen && region == 2),
        .waddr(addr_i[14:2]),
        .wdata(data_i[11:0]),
        .rclk(pclk),
        .raddr(text_raddr),
        .rdata(text_rdata)
    );
    dpram2c_lut #(
        .DW(8),
        .DP(2048)
    ) u_font (  // 128 个字 x 16 行
        .wclk(clk),
        .we(wen && region == 3),
        .waddr(addr_i[12:2]),
        .wdata(data_i[7:0]),
        .rclk(pclk),
        .raddr(font_raddr),
        .rdata(font_rdata)
    );

    disp_scanout u_scanout (
        .pclk(pclk),
        .rst_n(rst_n),
        .h(h),
        .v(v),
        .enable(a_ctrl[0]),
        .fade_color(a_fade_color),
        .fade_level(a_fade_level),
        .lb_raddr(show_raddr),
        .lb_rdata(show_rdata),
        .text_raddr(text_raddr),
        .text_rdata(text_rdata),
        .font_raddr(font_raddr),
        .font_rdata(font_rdata),
        .hsync_n(hsync_n),
        .vsync_n(vsync_n),
        .de(de),
        .rgb(rgb)
    );

    // ---------------- 寄存器、提交、计数 ----------------
    reg drawing;  // 这一行还在画 (渲染或混合没完)
    reg [15:0] line_cycles;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl <= 0;
            backdrop <= 0;
            clip0 <= 0;
            clip1 <= 640;
            win_x <= 0;
            win_y <= 0;
            scroll_x <= 0;
            scroll_y <= 0;
            fade_color <= 0;
            fade_level <= 0;
            sprite_n <= 0;
            a_ctrl <= 0;
            a_backdrop <= 0;
            a_clip0 <= 0;
            a_clip1 <= 640;
            a_win_x <= 0;
            a_win_y <= 0;
            a_scroll_x <= 0;
            a_scroll_y <= 0;
            a_fade_color <= 0;
            a_fade_level <= 0;
            a_sprite_n <= 0;
            pending <= 0;
            vblank <= 0;
            frame <= 0;
            line_max <= 0;
            line_max_cur <= 0;
            overrun <= 0;
            dropped <= 0;
            drawing <= 0;
            line_cycles <= 0;
        end else begin
            if (wen && low && page == 0)
                case (addr_i[11:2])
                    0: ctrl <= data_i[1:0];
                    1: backdrop <= data_i[15:0];
                    2: {clip1, clip0} <= {data_i[25:16], data_i[9:0]};
                    3: {win_y, win_x} <= {data_i[27:16], data_i[11:0]};
                    4: {scroll_y, scroll_x} <= {data_i[24:16], data_i[8:0]};
                    5: {fade_level, fade_color} <= data_i[20:0];
                    6: sprite_n <= data_i[9:0] > 512 ? 10'd512 : data_i[9:0];
                    default: ;
                endcase
            if (ev) vblank <= ev_pair >= 360;
            if (frame_end) begin
                frame <= frame + 1;
                line_max <= line_max_cur;
                line_max_cur <= 0;
                if (pending) begin
                    pending <= 0;
                    a_ctrl <= ctrl;
                    a_backdrop <= backdrop;
                    a_clip0 <= clip0;
                    a_clip1 <= clip1;
                    a_win_x <= win_x;
                    a_win_y <= win_y;
                    a_scroll_x <= scroll_x;
                    a_scroll_y <= scroll_y;
                    a_fade_color <= fade_color;
                    a_fade_level <= fade_level;
                    a_sprite_n <= sprite_n;
                end
            end
            // 提交写在交换之后: 同一拍不会把刚写的提交清掉
            if (wen && low && page == 0 && addr_i[11:2] == 7 && data_i[0]) pending <= 1;
            // 一行从 go 到渲染、混合都完的拍数; 下一对物理行开始时还没画完算一次超时
            if (render_go) begin
                drawing <= 1;
                line_cycles <= 0;
            end else if (drawing) begin
                line_cycles <= line_cycles + 1'b1;
                if (!render_busy && blend_idle) begin
                    drawing <= 0;
                    if (line_cycles > line_max_cur[15:0]) line_max_cur <= {16'b0, line_cycles};
                end
            end
            if (ev && drawing) overrun <= overrun + 1;
            if (scan_drop) dropped <= dropped + 1;
        end
    end
endmodule
