// 裁剪: 像素流里只留 (X0, Y0) 起 W x H 的一块, 其余丢掉; 输出比输入晚 1 拍。
// 电脑最低只给 800x600, 裁出正中 640x480 交给 box4 (见 vision.v)。
module crop #(
    parameter X0 = 80,
    parameter Y0 = 60,
    parameter W  = 640,
    parameter H  = 480
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
    reg [11:0] x_r, y_r;
    wire [11:0] x = in_sof ? 12'd0 : x_r;
    wire [11:0] y = in_sof ? 12'd0 : y_r;
    wire keep = x >= X0 && x < X0 + W && y >= Y0 && y < Y0 + H;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_r <= 0;
            y_r <= 0;
            out_valid <= 0;
            out_sof <= 0;
            out_eol <= 0;
        end else begin
            if (in_valid) begin
                x_r <= in_eol ? 12'd0 : x + 1'b1;
                y_r <= in_eol ? y + 1'b1 : y;
            end
            out_valid <= in_valid && keep;
            out_sof   <= in_valid && x == X0 && y == Y0;
            out_eol   <= in_valid && keep && x == X0 + W - 1;
            out_data  <= in_data;
        end
    end
endmodule
