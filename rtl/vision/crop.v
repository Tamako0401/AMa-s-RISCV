// 测量完整帧后居中裁剪; 连续两帧尺寸一致才启用, 配置只在 SOF 切换。
// 输出是待验证帧, 接收端必须等 frame_commit 才发布 (高度变化到下一 SOF 才知道)。
module crop #(
    parameter W = 640, parameter H = 480
) (
    input wire clk, input wire rst_n,
    input wire in_valid, input wire in_sof, input wire in_eol,
    input wire [23:0] in_data,
    output reg out_valid, output reg out_sof, output reg out_eol,
    output reg [23:0] out_data,
    output wire frame_commit,
    output reg [11:0] measured_w, output reg [11:0] measured_h,
    output reg supported, output reg stable, output reg measured_toggle
);
    reg [11:0] x_r, y_r, line_w, x0, y0;
    reg seen, bad, active, cropped;
    wire [11:0] x = in_sof ? 12'd0 : x_r;
    wire [11:0] y = in_sof ? 12'd0 : y_r;
    wire complete = seen && !bad && x_r == 0 && line_w != 0 && y_r != 0;
    wire fits = line_w >= W && y_r >= H;
    wire same = complete && supported && line_w == measured_w && y_r == measured_h;
    assign frame_commit = in_valid && in_sof && same && fits && active && cropped;
    wire keep = active && !bad && x >= x0 && x < x0 + W && y >= y0 && y < y0 + H;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_r <= 0; y_r <= 0; line_w <= 0; x0 <= 0; y0 <= 0;
            seen <= 0; bad <= 0; active <= 0; cropped <= 0;
            measured_w <= 0; measured_h <= 0; supported <= 0; stable <= 0; measured_toggle <= 0;
            out_valid <= 0; out_sof <= 0; out_eol <= 0; out_data <= 0;
        end else begin
            out_valid <= in_valid && !in_sof && keep;
            out_sof <= in_valid && keep && x == x0 && y == y0;
            out_eol <= in_valid && keep && x == x0 + W - 1;
            out_data <= in_data;
            if (in_valid) begin
                if (in_sof) begin
                    if (seen) begin
                        measured_w <= line_w; measured_h <= y_r;
                        supported <= complete && fits; stable <= same && fits;
                        measured_toggle <= ~measured_toggle;
                    end
                    active <= same && fits;
                    x0 <= fits ? (line_w - W) / 2 : 0;
                    y0 <= fits ? (y_r - H) / 2 : 0;
                    seen <= 1; bad <= 0; cropped <= 0; line_w <= 0;
                    // 原点也是裁剪原点时, 当拍使用新配置。
                    out_valid <= same && fits && line_w == W && y_r == H;
                    out_sof <= same && fits && line_w == W && y_r == H;
                    out_eol <= 0;
                end
                if (!in_sof && keep && x == x0 + W - 1 && y == y0 + H - 1) cropped <= 1;
                x_r <= in_eol ? 12'd0 : x + 1'b1;
                y_r <= in_eol ? y + 1'b1 : y;
                if (in_eol) begin
                    if (y == 0) line_w <= x + 1'b1;
                    else if (x + 1'b1 != line_w) bad <= 1;
                end
                // 计数超界也按不支持处理, 不允许回绕后误锁定。
                if (x == 4095 || y == 4095) bad <= 1;
            end
        end
    end
endmodule
