// ST7789 (240x320, RGB565) SPI 面板行为模型 — 仅用于仿真。
//
// 它只看真实引脚: CS_N / DC / SCK / MOSI / RST_N, 不引用 SoC 内部任何信号,
// 因此能独立验证"CPU -> RIB -> 外设子总线 -> SPI -> 屏幕"这整条链路,
// 包括最容易被忽略的 SPI 模式、字节序和窗口命令。
//
// 采样约定: 模式 0 与模式 3 都在 SCK 的**上升沿**采样 MOSI(模式 3 空闲为高,
// 上升沿是其第二个边沿; spi.v 在上升沿之前的那个边沿才更新 MOSI, 所以这里采
// 样不会撞上竞争)。驱动用的是模式 3。
//
// CS 由驱动一直拉低, 所以字节边界只能靠 8 位计数 + DC 电平区分。
//
// 支持的命令: 0x2A CASET / 0x2B RASET / 0x2C RAMWR 会真正维护 GRAM;
// 其余命令只结束 RAMWR 状态, 参数被忽略。
`timescale 1ns/1ps
module st7789_model #(
    parameter W = 240,
    parameter H = 320
)(
    input wire rst_n,       // 面板复位引脚, 低有效
    input wire cs_n,        // 片选, 低有效
    input wire dc,          // 0 = 命令, 1 = 数据
    input wire sck,         // SCK
    input wire mosi         // MOSI
);

    // 显存
    reg [15:0] gram [0:W*H-1];

    localparam [1:0] ST_NONE   = 2'd0;
    localparam [1:0] ST_CASET  = 2'd1;
    localparam [1:0] ST_RASET  = 2'd2;
    localparam [1:0] ST_RAMWR  = 2'd3;

    reg [1:0]  st = ST_NONE;
    reg [2:0]  bit_cnt = 0;
    reg [7:0]  shift = 0;
    reg [7:0]  cur_cmd = 0;
    integer    param_cnt = 0;
    reg [15:0] p0 = 0, p1 = 0;

    integer xs = 0, xe = 0, ys = 0, ye = 0;     // 当前窗口
    integer cx = 0, cy = 0;                     // 当前写入位置
    reg        pix_hi_ok = 0;
    reg [7:0]  pix_hi = 0;

    // 统计, 供测试台核对
    integer pixels   = 0;      // 写进 GRAM 的像素数
    integer cmd_cnt  = 0;      // 收到的命令字节数
    integer data_cnt = 0;      // 收到的数据字节数
    reg [7:0] last_cmd = 0;
    integer colmod = -1;       // 0x3A 的参数
    integer madctl = -1;       // 0x36 的参数
    integer ramwr_cnt = 0;     // 0x2C 出现次数

    task handle_cmd(input [7:0] c);
        begin
            cur_cmd = c;
            param_cnt = 0;
            p0 = 0;
            p1 = 0;
            cmd_cnt = cmd_cnt + 1;
            last_cmd = c;
            case (c)
                8'h2A: st = ST_CASET;
                8'h2B: st = ST_RASET;
                8'h2C: begin
                    st = ST_RAMWR;
                    cx = xs;
                    cy = ys;
                    pix_hi_ok = 0;
                    ramwr_cnt = ramwr_cnt + 1;
                end
                default: st = ST_NONE;
            endcase
        end
    endtask

    task handle_data(input [7:0] d);
        begin
            data_cnt = data_cnt + 1;
            case (st)
                ST_CASET: begin
                    case (param_cnt)
                        0: p0 = {p0[7:0], d};
                        1: begin p0 = {p0[7:0], d}; xs = p0; end
                        2: p1 = {p1[7:0], d};
                        3: begin p1 = {p1[7:0], d}; xe = p1; end
                        default: ;
                    endcase
                    param_cnt = param_cnt + 1;
                end
                ST_RASET: begin
                    case (param_cnt)
                        0: p0 = {p0[7:0], d};
                        1: begin p0 = {p0[7:0], d}; ys = p0; end
                        2: p1 = {p1[7:0], d};
                        3: begin p1 = {p1[7:0], d}; ye = p1; end
                        default: ;
                    endcase
                    param_cnt = param_cnt + 1;
                end
                ST_RAMWR: begin
                    if (!pix_hi_ok) begin
                        pix_hi = d;
                        pix_hi_ok = 1;
                    end else begin
                        pix_hi_ok = 0;
                        if (cx >= 0 && cx < W && cy >= 0 && cy < H) begin
                            gram[cy*W + cx] = {pix_hi, d};
                            pixels = pixels + 1;
                        end
                        // 窗口内自动推进, 到右下角后回绕
                        if (cx < xe) cx = cx + 1;
                        else begin
                            cx = xs;
                            if (cy < ye) cy = cy + 1;
                            else cy = ys;
                        end
                    end
                end
                default: begin
                    // 其它命令的参数: 记下我们关心的
                    if (cur_cmd == 8'h3A && param_cnt == 0) colmod = d;
                    if (cur_cmd == 8'h36 && param_cnt == 0) madctl = d;
                    param_cnt = param_cnt + 1;
                end
            endcase
        end
    endtask

    // SCK 上升沿采样 MOSI, 每 8 位组成一个字节
    always @ (posedge sck) begin
        if (cs_n === 1'b0 && rst_n === 1'b1) begin
            shift = {shift[6:0], mosi};
            if (bit_cnt == 3'd7) begin
                bit_cnt = 0;
                if (dc === 1'b0) handle_cmd(shift);
                else             handle_data(shift);
            end else begin
                bit_cnt = bit_cnt + 1;
            end
        end
    end

    // 片选拉高或面板复位: 丢弃半截字节
    always @ (posedge cs_n or negedge rst_n) begin
        bit_cnt   = 0;
        shift     = 8'h00;
        pix_hi_ok = 0;
    end


    // *********************** 报告 ***********************
    // 把 GRAM 缩成 ASCII 图: 每 4 列取 1 字符, 每 8 行取 1 行。
    // 用色相而不是亮度, 这样"红/绿/蓝/白/黑"一眼可辨。
    function [7:0] glyph(input [15:0] c);
        reg [4:0] r;
        reg [5:0] g;
        reg [4:0] b;
        begin
            r = c[15:11];
            g = c[10:5];
            b = c[4:0];
            if (r < 5'd4 && g < 6'd4 && b < 5'd4)      glyph = " ";
            else if (r > 5'd20 && g > 6'd40 && b > 5'd20) glyph = "#";   // 白
            else if (r >= g && r >= b)                  glyph = "R";
            else if (g >= r && g >= b)                  glyph = "G";
            else                                        glyph = "B";
        end
    endfunction

    task render;
        integer ry, rx;
        begin
            $display("    +%0s+", {60{"-"}});
            for (ry = 0; ry < H; ry = ry + 8) begin
                $write("    |");
                for (rx = 0; rx < W; rx = rx + 4)
                    $write("%c", glyph(gram[ry*W + rx]));
                $display("|");
            end
            $display("    +%0s+", {60{"-"}});
        end
    endtask

endmodule
