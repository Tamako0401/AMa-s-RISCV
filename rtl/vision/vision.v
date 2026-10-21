// 视觉输入 (外设子总线 0x4000_5000): 输入适配 -> 裁剪 -> 4x4 均值缩小 -> 小窗存储 / 颜色跟踪,
// 全部在输入的像素时钟下; 小窗读口和寄存器在系统时钟下。
// 各级之间是像素流 (docs/vision.md), 换相机只换适配器, 换算法只换中间某一级。
// 寄存器 (偏移): 0x0 COLOR 读写 {tol, cr, cb}; 0x4 COUNT / 0x8 SUM_X / 0xC SUM_Y 只读, 上一帧的颜色跟踪结果;
//                0x10 FRAME 只读, 每出一帧结果加 1; 0x14 CENTER 只读 {Cr, Cb}, 上一帧画面正中 8x8 的平均颜色。
module vision #(
    // 输入 800x600 (电脑最低只给这个), 裁出正中 640x480, 缩成 160x120 正好填满小窗
    parameter IN_W = 800,
    parameter IN_H = 600
) (
    input wire clk,  // 系统时钟, 小窗读口和寄存器
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

    wire c_valid, c_sof, c_eol;
    wire [23:0] c_data;
    crop #(
        .X0((IN_W - 640) / 2),
        .Y0((IN_H - 480) / 2),
        .W (640),
        .H (480)
    ) u_crop (
        .clk(vin_pclk),
        .rst_n(prst_n),
        .in_valid(a_valid),
        .in_sof(a_sof),
        .in_eol(a_eol),
        .in_data(a_data),
        .out_valid(c_valid),
        .out_sof(c_sof),
        .out_eol(c_eol),
        .out_data(c_data)
    );

    wire s_valid, s_sof, s_eol;
    wire [23:0] s_data;
    box4 #(
        .W(640)
    ) u_scale (
        .clk(vin_pclk),
        .rst_n(prst_n),
        .in_valid(c_valid),
        .in_sof(c_sof),
        .in_eol(c_eol),
        .in_data(c_data),
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

    // 颜色跟踪的设置在系统时钟下写, 像素时钟下直接用 (改的那一帧结果可能不准)
    reg [7:0] cb, cr, tol;
    wire [14:0] t_count;
    wire [21:0] t_sum_x, t_sum_y;
    wire [7:0] t_center_cb, t_center_cr;
    wire t_done;
    color_track #(
        .W(160),
        .H(120)
    ) u_color (
        .clk(vin_pclk),
        .rst_n(prst_n),
        .in_valid(s_valid),
        .in_sof(s_sof),
        .in_eol(s_eol),
        .in_data(s_data),
        .cb(cb),
        .cr(cr),
        .tol(tol),
        .count(t_count),
        .sum_x(t_sum_x),
        .sum_y(t_sum_y),
        .center_cb(t_center_cb),
        .center_cr(t_center_cr),
        .done(t_done)
    );

    // 结果跨到系统时钟: done 同步过来, 翻转后再取结果 (结果保持一整帧, 这时早已稳定)
    reg [ 2:0] done_s;
    reg [14:0] count;
    reg [21:0] sum_x, sum_y;
    reg [15:0] center;
    reg [31:0] frame;

    // 总线: 一拍接受, 下一拍响应
    reg response_valid;
    reg [31:0] data_r;
    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i);
    assign rsp_valid_o = response_valid;
    assign data_o = data_r;
    wire fire = req_valid_i && req_ready_o;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_s <= 0;
            count <= 0;
            sum_x <= 0;
            sum_y <= 0;
            center <= 0;
            frame <= 0;
            cb <= 0;
            cr <= 0;
            tol <= 0;
            response_valid <= 0;
            data_r <= 0;
        end else begin
            done_s <= {done_s[1:0], t_done};
            if (done_s[2] != done_s[1]) begin
                count  <= t_count;
                sum_x  <= t_sum_x;
                sum_y  <= t_sum_y;
                center <= {t_center_cr, t_center_cb};
                frame  <= frame + 1;
            end
            if (response_valid && rsp_ready_i) response_valid <= 0;
            if (fire) begin
                response_valid <= 1;
                data_r <= 0;
            end
            if (fire && !we_i)
                case (addr_i[11:2])
                    0: data_r <= {8'b0, tol, cr, cb};
                    1: data_r <= {17'b0, count};
                    2: data_r <= {10'b0, sum_x};
                    3: data_r <= {10'b0, sum_y};
                    4: data_r <= frame;
                    5: data_r <= {16'b0, center};
                    default: data_r <= 0;
                endcase
            if (fire && we_i && addr_i[11:2] == 0) {tol, cr, cb} <= data_i[23:0];
        end
    end
endmodule
