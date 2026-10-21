// 颜色跟踪: 数一帧里颜色接近目标的点, 给出个数和 x、y 坐标之和 (软件相除得重心)。
// 颜色看 YCbCr 里的 Cb、Cr (和亮度无关), 与 model/color.py 逐位相同:
//   Cb = 128 + ((-43R - 85G + 128B) >> 8), Cr = 128 + ((128R - 107G - 21B) >> 8)
//   命中: |Cb - cb| <= tol 且 |Cr - cr| <= tol
// 128 * 256 加进括号里后中间结果总在 0..65535, 不用有符号数, 取高 8 位就是 Cb/Cr。
// 只统计左上 W x H 内的点。结果在下一帧的 sof 时锁存并翻转 done, 锁存的值保持一整帧。
// 另给出画面正中 8x8 个点的平均 Cb、Cr, 软件拿来标定: 标记放在画面中间, 把这个值设成目标色。
module color_track #(
    parameter W  = 160,
    parameter H  = 120,
    parameter CW = $clog2(W * H + 1),  // 个数的位宽
    parameter SW = $clog2(W * H * W)   // 坐标和的位宽
) (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    input wire [23:0] in_data,

    // 目标颜色和容差: 由别的时钟域写, 软件只在设置时改, 改的那一帧结果可能不准
    input wire [7:0] cb,
    input wire [7:0] cr,
    input wire [7:0] tol,

    output reg [CW-1:0] count,
    output reg [SW-1:0] sum_x,
    output reg [SW-1:0] sum_y,
    output reg [7:0] center_cb,
    output reg [7:0] center_cr,
    output reg done
);
    reg [9:0] x_r, y_r;
    wire [ 9:0] x = in_sof ? 10'd0 : x_r;
    wire [ 9:0] y = in_sof ? 10'd0 : y_r;

    wire [15:0] r = {8'b0, in_data[23:16]};
    wire [15:0] g = {8'b0, in_data[15:8]};
    wire [15:0] b = {8'b0, in_data[7:0]};
    wire [15:0] cb_sum = 16'd32768 - 16'd43 * r - 16'd85 * g + 16'd128 * b;
    wire [15:0] cr_sum = 16'd32768 + 16'd128 * r - 16'd107 * g - 16'd21 * b;

    // 第 1 拍: 算颜色; 第 2 拍: 比较并累加
    reg p_valid, p_sof, p_inside, p_center;
    reg [9:0] p_x, p_y;
    reg [7:0] p_cb, p_cr;
    wire [7:0] dcb = p_cb > cb ? p_cb - cb : cb - p_cb;
    wire [7:0] dcr = p_cr > cr ? p_cr - cr : cr - p_cr;
    wire hit = p_valid && p_inside && dcb <= tol && dcr <= tol;

    wire [SW-1:0] px = {{SW - 10{1'b0}}, p_x};
    wire [SW-1:0] py = {{SW - 10{1'b0}}, p_y};
    reg [CW-1:0] acc_n;
    reg [SW-1:0] acc_x, acc_y;
    reg [13:0] acc_cb, acc_cr;  // 64 个点的和
    wire center = p_valid && p_center;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_r <= 0;
            y_r <= 0;
            p_valid <= 0;
            p_sof <= 0;
            acc_n <= 0;
            acc_x <= 0;
            acc_y <= 0;
            acc_cb <= 0;
            acc_cr <= 0;
            center_cb <= 0;
            center_cr <= 0;
            count <= 0;
            sum_x <= 0;
            sum_y <= 0;
            done <= 0;
        end else begin
            if (in_valid) begin
                x_r <= in_eol ? 10'd0 : x + 1'b1;
                y_r <= in_eol ? y + 1'b1 : y;
            end
            p_valid  <= in_valid;
            p_sof    <= in_valid && in_sof;
            p_inside <= x < W && y < H;
            p_center <= x >= W / 2 - 4 && x < W / 2 + 4 && y >= H / 2 - 4 && y < H / 2 + 4;
            p_x      <= x;
            p_y      <= y;
            p_cb     <= cb_sum[15:8];
            p_cr     <= cr_sum[15:8];

            if (p_sof) begin
                count <= acc_n;
                sum_x <= acc_x;
                sum_y <= acc_y;
                done  <= ~done;
                acc_n <= {{CW - 1{1'b0}}, hit};
                acc_x <= hit ? px : {SW{1'b0}};
                acc_y <= hit ? py : {SW{1'b0}};
            end else if (hit) begin
                acc_n <= acc_n + 1'b1;
                acc_x <= acc_x + px;
                acc_y <= acc_y + py;
            end

            if (p_sof) begin
                center_cb <= acc_cb[13:6];
                center_cr <= acc_cr[13:6];
                acc_cb <= 0;
                acc_cr <= 0;
            end else if (center) begin
                acc_cb <= acc_cb + {6'b0, p_cb};
                acc_cr <= acc_cr + {6'b0, p_cr};
            end
        end
    end
endmodule
