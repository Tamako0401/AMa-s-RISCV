// 视频输出: 320x240 逻辑画面, VGA x2 或 720p x3 居中; 渲染在系统域, 扫描在像素域。
module video #(parameter MODE_720P = 0) (
    input wire clk,
    input wire pix_clk,  // 独立扫描时钟: 74.25 MHz 或 25 MHz
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

    output wire pclk,
    output reg hsync_n,
    output reg vsync_n,
    output reg de,
    output reg [23:0] rgb,

    // 小窗: 读视觉输入的小图 (RGB332), 地址 y * 160 + x, 数据下一拍有效
    output wire [14:0] win_raddr,
    input  wire [ 7:0] win_rdata
);
    // 720p 为 CEA 正同步; VGA 保留原来的 25 MHz、负同步。
    localparam H_ACT = MODE_720P ? 1280 : 640, H_FP = MODE_720P ? 110 : 16;
    localparam H_SYNC = MODE_720P ? 40 : 96, H_TOTAL = MODE_720P ? 1650 : 800;
    localparam V_ACT = MODE_720P ? 720 : 480, V_FP = MODE_720P ? 5 : 10;
    localparam V_SYNC = MODE_720P ? 5 : 2, V_TOTAL = MODE_720P ? 750 : 525;
    localparam SCALE = MODE_720P ? 3 : 2, LEFT = MODE_720P ? 160 : 0;
    assign pclk = ~pix_clk;  // 数据在下降沿更新, 芯片在上升沿采样
    reg [1:0] prst;
    always @(posedge pix_clk or negedge rst_n)
        if (!rst_n) prst <= 0;
        else prst <= {prst[0], 1'b1};
    wire prst_n = prst[1];

    // ---------------- 总线: 一拍接受, 下一拍响应 ----------------
    reg response_valid;
    reg [31:0] data_r;
    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i);
    assign rsp_valid_o = response_valid;
    assign data_o = data_r;
    wire fire = req_valid_i && req_ready_o;
    wire wen = fire && we_i;
    wire [3:0] page = addr_i[15:12];

    reg enable, show_window;
    reg [8:0] scroll_x, win_x;
    reg [ 7:0] win_y;
    reg [ 7:0] scroll_y;
    reg [31:0] frame;
    reg [10:0] h;
    reg [9:0] v;
    reg [1:0] blank_s;
    reg [2:0] frame_s;
    reg frame_toggle, blank_pix;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame <= 0;
            blank_s <= 0;
            frame_s <= 0;
            response_valid <= 0;
            data_r <= 0;
            enable <= 0;
            show_window <= 0;
            win_x <= 0;
            win_y <= 0;
            scroll_x <= 0;
            scroll_y <= 0;
        end else begin
            blank_s <= {blank_s[0], blank_pix};
            frame_s <= {frame_s[1:0], frame_toggle};
            if (frame_s[2] != frame_s[1]) frame <= frame + 1'b1;
            if (response_valid && rsp_ready_i) response_valid <= 0;
            if (fire) begin
                response_valid <= 1;
                data_r <= 0;
            end
            if (fire && !we_i && page == 0)
                case (addr_i[11:2])
                    0: data_r <= {30'b0, show_window, enable};
                    1: data_r <= {8'b0, scroll_y, 7'b0, scroll_x};
                    2: data_r <= {31'b0, blank_s[1]};
                    3: data_r <= frame;
                    4: data_r <= {8'b0, win_y, 7'b0, win_x};
                    default: data_r <= 0;
                endcase
            if (wen && page == 0)
                case (addr_i[11:2])
                    0: {show_window, enable} <= data_i[1:0];
                    1: {scroll_y, scroll_x} <= {data_i[23:16], data_i[8:0]};
                    4: {win_y, win_x} <= {data_i[23:16], data_i[8:0]};
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

    dpram2c #(
        .DW(16),
        .DP(256)
    ) u_palette (  // 0x2000_1000: 256 色, RGB565
        .wclk(clk),
        .rclk(pix_clk),
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
    localparam [10:0] H_LEFT = LEFT, H_SCALE = SCALE;
    localparam [9:0] V_SCALE = SCALE;
    wire [10:0] scaled_x = (h - H_LEFT) / H_SCALE;
    wire [9:0] scaled_y = v / V_SCALE;
    wire [8:0] lx = scaled_x[8:0];
    wire [7:0] ly = scaled_y[7:0];
    // 行缓存: 两行轮换, 显示第 n 行时渲染第 n+1 行
    dpram2c #(.DW(8), .DP(1024)) u_line (
        .wclk(clk), .we(lb_we), .waddr(lb_waddr), .wdata(lb_wdata),
        .rclk(pix_clk), .raddr({ly[0], lx}), .rdata(lb_rdata)
    );

    // 行号与请求一起保持到确认; 两次请求相隔至少 64 us。
    reg render_req;
    reg [7:0] render_line;
    reg [2:0] req_s;
    reg render_ack;
    reg [1:0] ack_s;
    wire start = req_s[2] != render_ack;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin req_s <= 0; render_ack <= 0; end
        else begin
            req_s <= {req_s[1:0], render_req};
            if (start) render_ack <= req_s[2];
        end
    end
    wire [7:0] next_line = v == V_TOTAL - 3 ? 8'd0 : ly + 8'd1;

    video_render u_render (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .line(render_line),
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

    // 配置用握手快照跨域, 源数据保持到确认; 不逐位采样多位坐标。
    wire [18:0] cfg = {show_window, enable, win_y, win_x};
    reg [18:0] cfg_hold, cfg_pix;
    reg cfg_req, cfg_ack;
    reg [1:0] cfg_ack_s;
    reg [2:0] cfg_req_s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cfg_hold <= 0; cfg_req <= 0; cfg_ack_s <= 0; end
        else begin
            cfg_ack_s <= {cfg_ack_s[0], cfg_ack};
            if (cfg_ack_s[1] == cfg_req && cfg_hold != cfg) begin
                cfg_hold <= cfg;
                cfg_req <= ~cfg_req;
            end
        end
    end
    always @(posedge pix_clk or negedge prst_n) begin
        if (!prst_n) begin cfg_req_s <= 0; cfg_ack <= 0; cfg_pix <= 0; end
        else begin
            cfg_req_s <= {cfg_req_s[1:0], cfg_req};
            if (cfg_req_s[2] != cfg_ack) begin cfg_pix <= cfg_hold; cfg_ack <= cfg_req_s[2]; end
        end
    end

    wire picture = h >= LEFT && h < LEFT + 320 * SCALE && v < V_ACT;
    wire [8:0] wx = lx - cfg_pix[8:0];
    wire [8:0] wy = {1'b0, ly} - {1'b0, cfg_pix[16:9]};
    assign win_raddr = wy[6:0] * 15'd160 + {6'b0, wx};
    reg [7:0] win_q;
    reg [1:0] active_d, picture_d, window_d, hs_d, vs_d;
    reg primed;
    wire [23:0] win888 = {
        {2{win_q[7:5]}}, win_q[7:6], {2{win_q[4:2]}}, win_q[4:3], {4{win_q[1:0]}}
    };
    wire [23:0] rgb888 = {
        color[15:11], color[15:13], color[10:5], color[10:9], color[4:0], color[4:2]
    };
    wire hs = (h >= H_ACT + H_FP && h < H_ACT + H_FP + H_SYNC) ^ !MODE_720P;
    wire vs = (v >= V_ACT + V_FP && v < V_ACT + V_FP + V_SYNC) ^ !MODE_720P;
    always @(posedge pix_clk or negedge prst_n) begin
        if (!prst_n) begin
            h <= 0; v <= 0; primed <= 0;
            render_req <= 0; render_line <= 0; ack_s <= 0; frame_toggle <= 0; blank_pix <= 0;
            active_d <= 0; picture_d <= 0; window_d <= 0;
            hs_d <= {2{!MODE_720P}}; vs_d <= {2{!MODE_720P}};
            de <= 0; hsync_n <= !MODE_720P; vsync_n <= !MODE_720P; rgb <= 0; win_q <= 0;
        end else begin
            ack_s <= {ack_s[0], render_ack};
            h <= h == H_TOTAL - 1 ? 11'd0 : h + 1'b1;
            if (h == H_TOTAL - 1) begin
                v <= v == V_TOTAL - 1 ? 10'd0 : v + 1'b1;
                if (v == V_TOTAL - 1) begin primed <= 1; blank_pix <= 0; end
                if (v == V_ACT - 1) begin frame_toggle <= ~frame_toggle; blank_pix <= 1; end
            end
            // 第 0 行在末尾三行消隐里预画; 显示行 n 时画 n+1。
            if (h == 0 && ((v < V_ACT - SCALE && v % V_SCALE == 0) || v == V_TOTAL - 3)
                && ack_s[1] == render_req) begin
                render_line <= next_line;
                render_req <= ~render_req;
            end
            active_d <= {active_d[0], h < H_ACT && v < V_ACT};
            picture_d <= {picture_d[0], picture && primed && cfg_pix[17]};
            window_d <= {window_d[0], cfg_pix[18] && wx < 160 && wy < 120};
            hs_d <= {hs_d[0], hs}; vs_d <= {vs_d[0], vs};
            win_q <= win_rdata;
            de <= active_d[1]; hsync_n <= hs_d[1]; vsync_n <= vs_d[1];
            rgb <= !picture_d[1] ? 24'h0 : window_d[1] ? win888 : rgb888;
        end
    end
endmodule
