// 4x4 均值缩小 (步长 4 的均值卷积): 像素流进, 宽高各 1/4 的像素流出, RGB888 每通道各自平均。
// 横向: 每 4 个像素累加一次; 纵向: 一行 W/4 个部分和存在 RAM 里, 攒满 4 行输出 (和 >> 4)。
// 输入宽度 W 须是 4 的倍数; 输出比第 4 行的最后一个像素晚 1 拍。
module box4 #(
    parameter W = 640
) (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    input wire [23:0] in_data,

    output reg out_valid,
    output reg out_sof,
    output reg out_eol,
    output reg [23:0] out_data
);
    localparam CW = $clog2(W / 4);

    // 当前像素的位置: x 在行内, row 是 4 行组内第几行, first 表示还在帧的第一组行
    reg [CW+1:0] x_r;
    reg [1:0] row_r;
    reg first_r;
    wire [CW+1:0] x = in_sof ? 0 : x_r;
    wire [1:0] row = in_sof ? 2'd0 : row_r;
    wire first = in_sof || first_r;
    wire [CW-1:0] col = x[CW+1:2];

    // 三个通道并排放在一个宽字里一起加: 每段留足位宽, 段间不会进位
    // 横向和: 每通道 4 个 8 位相加, 每段 10 位
    reg [29:0] hsum_r;
    wire [29:0] pixel = {2'b0, in_data[23:16], 2'b0, in_data[15:8], 2'b0, in_data[7:0]};
    wire [29:0] hsum = x[1:0] == 0 ? pixel : hsum_r + pixel;

    // 纵向部分和: 每通道 4 个横向和相加, 每段 12 位; 本组第 0 行不加旧值
    wire [35:0] vsum_old;
    wire [35:0] hsum12 = {2'b0, hsum[29:20], 2'b0, hsum[19:10], 2'b0, hsum[9:0]};
    wire [35:0] vsum = row == 0 ? hsum12 : vsum_old + hsum12;
    wire col_done = in_valid && x[1:0] == 3;

    dpram #(
        .DW(36),
        .DP(W / 4)
    ) u_sums (
        .clk(clk),
        .we(col_done && row != 3),
        .waddr(col),
        .wdata(vsum),
        .raddr(col),  // 一列的 4 个像素期间地址不变, 第 4 个像素时读数已就绪
        .rdata(vsum_old)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_r <= 0;
            row_r <= 0;
            first_r <= 1;
            out_valid <= 0;
            out_sof <= 0;
            out_eol <= 0;
        end else begin
            out_valid <= col_done && row == 3;
            out_sof   <= col_done && row == 3 && col == 0 && first;
            out_eol   <= col_done && row == 3 && in_eol;
            out_data  <= {vsum[35:28], vsum[23:16], vsum[11:4]};
            if (in_valid) begin
                hsum_r <= hsum;
                x_r <= in_eol ? 0 : x + 1'b1;
                row_r <= in_eol ? row + 1'b1 : row;
                first_r <= in_eol && row == 3 ? 1'b0 : first;
            end
        end
    end
endmodule
