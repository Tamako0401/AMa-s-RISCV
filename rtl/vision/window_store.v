// 把像素流存成 W x H 的小图 (RGB332, 每像素 1 字节), 超出部分丢掉; 另一侧按 rclk 读, 给视频输出的小窗用。
// 写和读不同步, 读到的可能是新旧两帧各一部分 (小窗看不出来)。
module window_store #(
    parameter W  = 160,
    parameter H  = 120,
    parameter AW = $clog2(W * H)
) (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    input wire [23:0] in_data,

    input wire rclk,
    input wire [AW-1:0] raddr,  // y * W + x
    output wire [7:0] rdata
);
    reg [AW-1:0] x_r, y_r;
    wire [AW-1:0] x = in_sof ? 0 : x_r;
    wire [AW-1:0] y = in_sof ? 0 : y_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_r <= 0;
            y_r <= 0;
        end else if (in_valid) begin
            x_r <= in_eol ? 0 : x + 1'b1;
            y_r <= in_eol ? y + 1'b1 : y;
        end
    end

    dpram2c #(
        .DW(8),
        .DP(W * H)
    ) u_ram (
        .wclk(clk),
        .we(in_valid && x < W && y < H),
        .waddr(y * W + x),
        .wdata({in_data[23:21], in_data[15:13], in_data[7:6]}),
        .rclk(rclk),
        .raddr(raddr),
        .rdata(rdata)
    );
endmodule
