// 视觉输入: 输入适配 -> 4x4 均值缩小 -> 小窗存储, 全部在输入的像素时钟下; 只有小窗的读口在系统时钟下。
// 各级之间是像素流 (docs/vision.md), 换相机只换适配器, 换算法只换中间某一级。
module vision #(
    parameter IN_W = 640  // 输入宽度; 640x480 缩成 160x120 正好填满小窗
) (
    input wire clk,   // 系统时钟, 小窗读口
    input wire rst_n,

    input wire vin_pclk,
    input wire vin_de,
    input wire [23:0] vin_rgb,

    input  wire [14:0] win_raddr,
    output wire [ 7:0] win_rdata
);
    // 复位同步到输入时钟: 异步拉低, 同步放开
    reg [1:0] prst;
    always @(posedge vin_pclk or negedge rst_n) begin
        if (!rst_n) prst <= 2'b00;
        else prst <= {prst[0], 1'b1};
    end
    wire prst_n = prst[1];

    wire a_valid, a_sof, a_eol;
    wire [23:0] a_data;
    hdmi_rx_adapter u_adapter (
        .clk(vin_pclk),
        .rst_n(prst_n),
        .de(vin_de),
        .rgb(vin_rgb),
        .out_valid(a_valid),
        .out_sof(a_sof),
        .out_eol(a_eol),
        .out_data(a_data)
    );

    wire s_valid, s_sof, s_eol;
    wire [23:0] s_data;
    box4 #(
        .W(IN_W)
    ) u_scale (
        .clk(vin_pclk),
        .rst_n(prst_n),
        .in_valid(a_valid),
        .in_sof(a_sof),
        .in_eol(a_eol),
        .in_data(a_data),
        .out_valid(s_valid),
        .out_sof(s_sof),
        .out_eol(s_eol),
        .out_data(s_data)
    );

    window_store #(
        .W(160),
        .H(120)
    ) u_window (
        .clk(vin_pclk),
        .rst_n(prst_n),
        .in_valid(s_valid),
        .in_sof(s_sof),
        .in_eol(s_eol),
        .in_data(s_data),
        .rclk(clk),
        .raddr(win_raddr),
        .rdata(win_rdata)
    );
endmodule
