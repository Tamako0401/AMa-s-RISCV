// 旋转缩放的精灵画一行: 一拍一个点, 从 x0 起画 n 个点, 凑满一格 (或到头) 交出一格。
// 图案坐标 (Q12, 半像素) 由 disp_render 算好行首的 u2、v2, 沿这一行每走一点 u2 += 2 pa, v2 -= 2 pb;
// 图案点 (u2 >> 13, v2 >> 13), 翻转在图案坐标上做 (u = S-1-u), 出了 0..S-1 或色号 0 不画。
module disp_affine (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [9:0] x0,
    input wire [10:0] n,  // 点数, >= 1
    input wire signed [31:0] u2,
    input wire signed [31:0] v2,
    input wire signed [19:0] du,  // 2 pa
    input wire signed [19:0] dv,  // 2 pb (v2 每点减它)
    input wire [2:0] lg,  // 图案边长 S = 1 << lg, 3~6
    input wire [12:0] base,
    input wire flip_x,
    input wire flip_y,
    output wire busy,

    output wire [12:0] pat_raddr,
    input  wire [63:0] pat_rdata,

    output reg cell_valid,
    output reg [6:0] cell_x,
    output reg [63:0] cell_idx,
    output reg [7:0] cell_mask
);
    reg issuing, got;
    reg [10:0] left;
    reg [9:0] px, got_x;
    reg signed [31:0] u, v;
    reg signed [31:0] su, sv;
    reg [ 2:0] g;
    reg [12:0] b;
    reg fx, fy;
    reg got_in, got_last;
    reg [ 2:0] got_byte;
    reg [63:0] acc;
    reg [ 7:0] acc_mask;
    assign busy = issuing || got;

    // 这一拍的点在图案里的位置
    wire signed [18:0] uu = u[31:13];
    wire signed [18:0] vv = v[31:13];
    wire signed [18:0] side = 19'sd1 <<< g;
    wire signed [18:0] uf = fx ? side - 19'sd1 - uu : uu;
    wire signed [18:0] vf = fy ? side - 19'sd1 - vv : vv;
    wire in_box = uf >= 0 && uf < side && vf >= 0 && vf < side;
    assign pat_raddr = b + ({4'b0, vf[5:0], 3'b0} >> (3'd6 - g)) + {10'b0, uf[5:3]};

    // 到的点放进这一格
    wire [ 7:0] idx = pat_rdata[{got_byte, 3'b0}+:8];
    wire [63:0] acc_next = acc | ({56'b0, idx} << {got_x[2:0], 3'b0});
    wire [ 7:0] mask_next = acc_mask | ({7'b0, got_in && idx != 0} << got_x[2:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issuing <= 0;
            got <= 0;
            cell_valid <= 0;
            acc <= 0;
            acc_mask <= 0;
        end else begin
            cell_valid <= 0;
            if (start) begin
                issuing <= 1;
                left <= n;
                px <= x0;
                u <= u2;
                v <= v2;
                su <= {{12{du[19]}}, du};
                sv <= {{12{dv[19]}}, dv};
                g <= lg;
                b <= base;
                fx <= flip_x;
                fy <= flip_y;
            end else if (issuing) begin
                left <= left - 1'b1;
                px <= px + 1'b1;
                u <= u + su;
                v <= v - sv;
                if (left == 1) issuing <= 0;
            end
            got <= issuing;
            got_x <= px;
            got_in <= in_box;
            got_byte <= uf[2:0];
            got_last <= left == 1;
            if (got) begin
                if (got_x[2:0] == 7 || got_last) begin
                    cell_valid <= 1;
                    cell_x <= got_x[9:3];
                    cell_idx <= acc_next;
                    cell_mask <= mask_next;
                    acc <= 0;
                    acc_mask <= 0;
                end else begin
                    acc <= acc_next;
                    acc_mask <= mask_next;
                end
            end
        end
    end
endmodule
