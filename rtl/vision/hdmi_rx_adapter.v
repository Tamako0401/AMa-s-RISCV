// HDMI 接收芯片 (MS7200) 的并行输出 -> 像素流 (约定见 docs/vision.md)。
// 只用 de 和像素: de 断开超过 GAP 个时钟 (比任何行消隐都长) 就认为进了场消隐, 下一个有效像素是帧首;
// 这样不用管各分辨率的同步极性。比输入晚 2 拍。
module hdmi_rx_adapter #(
    parameter GAP = 4096
) (
    input wire clk,  // 芯片送来的像素时钟
    input wire rst_n,
    input wire de,
    input wire [23:0] rgb,

    output reg out_valid,
    output reg out_sof,
    output reg out_eol,
    output reg [23:0] out_data
);
    reg de_q;
    reg [23:0] rgb_q;
    reg [12:0] idle;  // de 断开了多少拍, 到 GAP 封顶
    reg frame_gap;  // 上一个有效像素之后出现过场消隐

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_q <= 0;
            idle <= 0;
            frame_gap <= 1;
            out_valid <= 0;
            out_sof <= 0;
            out_eol <= 0;
        end else begin
            // 第 1 拍: 寄存输入 (进 IO 寄存器)
            de_q <= de;
            rgb_q <= rgb;
            // 第 2 拍: de_q 是当前像素, de 是下一个, 用来判断行尾
            out_valid <= de_q;
            out_data <= rgb_q;
            out_sof <= de_q && frame_gap;
            out_eol <= de_q && !de;
            if (de_q) begin
                idle <= 0;
                frame_gap <= 0;
            end else if (idle != GAP) begin
                idle <= idle + 1'b1;
            end else begin
                frame_gap <= 1;
            end
        end
    end
endmodule
