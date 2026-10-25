// 精灵表: 两份 (前台给渲染读, 后台给 CPU 写), swap 时交换 (场消隐里, 见 display.v)。
// 每个精灵两个字: w0 {scale[31:24], y[23:12], x[11:0]}, w1 {angle[31:24], alpha[20:16], flags[15:10], image[9:0]}。
// Y 范围表: CPU 写 w1 时, 用刚写的 w0 (所以先写 w0 再写 w1) 和图案的边长算出外框的上下边 {top, bottom} (13 位有符号),
// 给 disp_scan 找和每一行相交的对象。外框边长 D: 不旋转 = S; AFFINE = S * scale / 16 * 3 / 2 (整数除法)。
// 图案编号超出图案表 (尺寸码 0) 时 D = 0, 哪一行都不相交, 不会画。
module disp_sprites (
    input  wire clk,
    input  wire rst_n,
    input  wire swap,
    output reg  front,

    input wire we,
    input wire [8:0] waddr,
    input wire wword,  // 0: w0, 1: w1
    input wire [31:0] wdata,
    input wire size_we,  // 图案表写入时, 这里存一份尺寸码
    input wire [9:0] size_waddr,
    input wire [2:0] size_wdata,

    input wire [8:0] raddr,
    output wire [63:0] rdata,  // {w1, w0}, 下一拍有效
    input wire [8:0] yr_raddr,
    output wire [25:0] yr_rdata  // {top, bottom}, 下一拍有效
);
    localparam AFFINE = 4;  // flags 的位

    reg [31:0] last_w0;
    reg pend, pend_bank;
    reg [8:0] pend_idx;
    reg [31:0] pend_w0, pend_w1;
    wire [2:0] code;

    dpram #(
        .DW(32),
        .DP(1024)
    ) u_w0 (
        .clk(clk),
        .we(we && !wword),
        .waddr({!front, waddr}),
        .wdata(wdata),
        .raddr({front, raddr}),
        .rdata(rdata[31:0])
    );
    dpram #(
        .DW(32),
        .DP(1024)
    ) u_w1 (
        .clk(clk),
        .we(we && wword),
        .waddr({!front, waddr}),
        .wdata(wdata),
        .raddr({front, raddr}),
        .rdata(rdata[63:32])
    );
    dpram #(
        .DW(3),
        .DP(1024)
    ) u_size (
        .clk(clk),
        .we(size_we),
        .waddr(size_waddr),
        .wdata(size_wdata),
        .raddr(wdata[9:0]),
        .rdata(code)
    );

    // 尺寸码到了 (写 w1 的下一拍): 算外框
    wire [2:0] lg = code + 3'd2;
    wire [13:0] scaled = {6'b0, pend_w0[31:24]} << lg;
    wire [9:0] quarter = scaled[13:4];
    wire [11:0] tripled = {2'b0, quarter} + {1'b0, quarter, 1'b0};
    wire [10:0] side = code == 0 || code > 4 ? 11'd0 : pend_w1[10+AFFINE] ? tripled[11:1] : 11'd1 << lg;
    wire signed [12:0] y = {pend_w0[23], pend_w0[23:12]};
    wire signed [12:0] top = y - $signed({3'b0, side[10:1]});
    wire signed [12:0] bottom = top + $signed({2'b0, side});

    dpram #(
        .DW(26),
        .DP(1024)
    ) u_yrange (
        .clk(clk),
        .we(pend),
        .waddr({pend_bank, pend_idx}),
        .wdata({top, bottom}),
        .raddr({front, yr_raddr}),
        .rdata(yr_rdata)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            front <= 0;
            pend  <= 0;
        end else begin
            if (swap) front <= !front;
            if (we && !wword) last_w0 <= wdata;
            pend <= we && wword;
            if (we && wword) begin
                pend_bank <= !front;
                pend_idx  <= waddr;
                pend_w0   <= last_w0;
                pend_w1   <= wdata;
            end
        end
    end
endmodule
