// handnet 加速器 (外设子总线 0x4000_6000): 一层一层跑完整张网络, 权重在片上 ROM。
//
// 数据通路: 16 路 int8 乘加并行 (一个 128 位字 = 16 个通道), int32 累加;
//           之后定点化 (三级流水, 每拍进一个输出通道), 乘数/偏置也是每通道一个。
//           两种模式 —— 普通卷积 (16 个输出通道并行, 同一个输入字节广播)
//           和 depthwise (16 个通道各取自己那个字节)。
// 存储: 输入图像 RAM 19200 字 x 32 位 (一个字一个像素, BGR + 0);
//       特征缓冲 A/B 若干 128 位字, 层与层之间乒乓; 层表见 nn_layers.v (脚本生成)。
// 时序: 每个 (输出像素, 通道组) 一拍一个抽头 (16 次乘加), 再约 18 拍定点化 (16 个通道 + 流水 2 拍)。
//       整网约 75 万拍 (50 MHz 下 15 ms)。
//
// 寄存器 (偏移, 见 docs/nn.md):
//   0x00 CTRL     bit0 写 1 开始一次推理 (忙时忽略); bit1 写 1 清除 DONE
//   0x04 STATUS   bit0 忙, bit1 完成, [7:4] 当前层号
//   0x08 IN       写: 一个像素 {8'b0, R, G, B}, 写完像素地址自增
//   0x0C IN_ADDR  读写: 下一个要写的像素 (0 .. 19199)
//   0x10 OUT_ADDR 读写: 要读的输出字 (0 .. 299)
//   0x14 OUT      只读: 一个输出字, 低字节是热力图 logit, 然后是 dx、dy、握拳
//   0x18 CYCLE    只读: 上一次推理用了多少拍
//   0x1C VERSION  只读: 0x4e4e_0001
//   0x20 IN_PIX   只读: 输入像素个数 (19200)
//
// OUT 走的是特征缓冲的读口, 只在空闲 (STATUS.bit0 = 0) 时有效。
module nn (
    input wire clk,
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

    output wire busy_o,
    output wire done_o
);
    `include "nn_model.vh"

    localparam FAW = $clog2(`NN_A_WORDS + `NN_B_WORDS);
    localparam IAW = $clog2(`NN_IN_PIX);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_SETUP = 3'd1;
    localparam [2:0] S_PIX = 3'd2;
    localparam [2:0] S_TAP = 3'd3;
    localparam [2:0] S_RQ = 3'd4;
    localparam [2:0] S_WRITE = 3'd5;

    integer j;

    // ---------------- 层表 ----------------
    wire cfg_mode, cfg_stride2, cfg_relu, cfg_src_in, cfg_dst_b;
    wire [1:0] cfg_k;
    wire [6:0] cfg_cin, cfg_cout;
    wire [7:0] cfg_in_w, cfg_in_h, cfg_out_w, cfg_out_h;
    wire [10:0] cfg_w_base;
    wire [9:0] cfg_bm_base;
    wire [5:0] cfg_sh;
    wire signed [7:0] cfg_zout, cfg_pad_q;

    reg [3:0] layer;
    nn_layers u_layers (
        .idx     (layer),
        .mode    (cfg_mode),
        .k       (cfg_k),
        .stride2 (cfg_stride2),
        .cin     (cfg_cin),
        .cout    (cfg_cout),
        .in_w    (cfg_in_w),
        .in_h    (cfg_in_h),
        .out_w   (cfg_out_w),
        .out_h   (cfg_out_h),
        .relu    (cfg_relu),
        .src_in  (cfg_src_in),
        .dst_b   (cfg_dst_b),
        .w_base  (cfg_w_base),
        .bm_base (cfg_bm_base),
        .sh      (cfg_sh),
        .zout    (cfg_zout),
        .pad_q   (cfg_pad_q)
    );

    // ---------------- 引擎状态 ----------------
    reg [2:0] state;
    reg busy_r, done_r;
    reg [31:0] cyc;
    reg start_req;

    reg [7:0] py, px;
    reg [1:0] cg;
    reg signed [18:0] row_y;     // py*stride - pad
    reg signed [20:0] row_base;  // row_y * 输入行宽
    reg signed [8:0] col_x;      // px*stride - pad
    reg [12:0] out_pix;

    reg [5:0] ti, ty, tx;
    reg issue_done, use_v;
    reg [3:0] byte_sel_r;
    reg in_range_r;

    reg [4:0] rq_n, rq_m;

    reg signed [31:0] acc[0:15];
    reg [127:0] out_word;

    reg [1:0] cshift_in, cshift_out;
    wire [5:0] k_last = (cfg_k == 2'd3) ? 6'd2 : 6'd0;  // 核内最后一个下标 (k-1)
    wire [5:0] cin_last = cfg_cin[5:0] - 6'd1;          // 最后一个输入通道
    wire [7:0] cgroups_x = {1'b0, (cfg_cout + 7'd15)} >> 4;
    reg [2:0] cgroups_out;
    reg src_b, dst_b;

    // ---------------- 地址 ----------------
    wire signed [20:0] iw_s = $signed({13'd0, cfg_in_w});
    wire signed [20:0] ih_s = $signed({13'd0, cfg_in_h});
    wire signed [20:0] row_y21 = $signed({{2{row_y[18]}}, row_y});
    wire signed [20:0] col_x21 = $signed({{12{col_x[8]}}, col_x});
    wire signed [20:0] ty21 = $signed({15'd0, ty});
    wire signed [20:0] tx21 = $signed({15'd0, tx});
    wire signed [20:0] iy = row_y21 + ty21;
    wire signed [20:0] ix = col_x21 + tx21;
    wire in_range = (iy >= 21'sd0) && (iy < ih_s) && (ix >= 21'sd0) && (ix < iw_s);

    // ty 只可能是 0/1/2: 用选择器代替乘法
    wire signed [20:0] ty_off = (ty == 6'd0) ? 21'sd0
                              : (ty == 6'd1) ? iw_s
                              : $signed({iw_s[19:0], 1'b0});
    wire signed [20:0] addr_pix = row_base + ty_off + col_x21 + tx21;

    // 抽头序号 = 输入通道 * k*k + 核内位置; k 只有 1 和 3 两种
    wire [13:0] t_index_x = (cfg_k == 2'd3)
        ? ({8'd0, ti} * 14'd9 + {8'd0, ty} * 14'd3 + {8'd0, tx})
        : {8'd0, ti};
    wire [9:0] t_index = t_index_x[9:0];
    wire [11:0] w_addr_x = {1'b0, cfg_w_base} + ({2'd0, t_index} << cshift_out) + {10'd0, cg};
    wire [10:0] bm_addr_x = {1'b0, cfg_bm_base} + {5'd0, cg, 4'd0} + {6'd0, rq_n};
    wire [1:0] rd_group = cfg_mode ? cg : ti[5:4];
    wire [12:0] src_base = src_b ? `NN_A_WORDS : 13'd0;
    wire [12:0] dst_base = dst_b ? `NN_A_WORDS : 13'd0;
    // 像素地址 * 每像素的字数 (cin/16 是 1/2/4, 用移位) + 通道组
    wire [19:0] f_addr_x = cfg_src_in
        ? 20'd0
        : ({7'd0, src_base} + ({5'd0, addr_pix[14:0]} << cshift_in) + {18'd0, rd_group});
    wire [12:0] f_raddr_eng = f_addr_x[12:0];
    wire [17:0] out_addr_x = {5'd0, dst_base} + ({5'd0, out_pix} << cshift_out) + {16'd0, cg};
    wire [12:0] out_addr = out_addr_x[12:0];
    wire [IAW-1:0] in_raddr = addr_pix[IAW-1:0];

    wire [127:0] act_raw = cfg_src_in ? {96'd0, in_rdata} : f_rdata;
    wire [127:0] act_q = in_range_r ? act_raw : {16{cfg_pad_q}};

    // ---------------- 定点化 (三级流水, 一拍进一个输出通道) ----------------
    // nn_bm.mem 的一个字: 低 32 位是定点乘数, 高 32 位是偏置 (见 model/nn_export.py)
    // 级 1: 选累加器 + 偏置 (33 位够); 级 2: 乘定点乘数, 33x32 取低 64 位, 和原先 64x64
    // 截成 64 位的结果相同; 级 3 (组合, 写 out_word): 舍入、移位、加零点、限幅。
    // 原来五步串在一拍里, 是整片 sys 时钟的最差路径。
    wire signed [31:0] acc_sel = acc[rq_m[3:0]];
    wire signed [31:0] b_sel = bm_data[63:32];
    reg rq1_v, rq2_v;
    reg [3:0] rq1_m, rq2_m;
    reg signed [32:0] rq1_sum;
    reg signed [31:0] rq1_mul;
    reg signed [63:0] rq2_prod;
    wire signed [64:0] prod_65 = rq1_sum * rq1_mul;
    wire signed [63:0] rnd = (cfg_sh == 6'd0) ? 64'sd0 : (64'sd1 << (cfg_sh - 6'd1));
    wire signed [63:0] z_64 = $signed({{56{cfg_zout[7]}}, cfg_zout});
    wire signed [63:0] shifted = ((rq2_prod + rnd) >>> cfg_sh) + z_64;
    wire signed [63:0] lo_64 = cfg_relu ? z_64 : -64'sd128;
    wire signed [63:0] clamped = (shifted < lo_64) ? lo_64 : (shifted > 64'sd127) ? 64'sd127 : shifted;
    wire [7:0] rq_byte = clamped[7:0];
    wire [7:0] oc_sel = {2'd0, cg, 4'd0} + {4'd0, rq2_m};
    wire rq_valid = oc_sel < {1'b0, cfg_cout};

    // ---------------- 存储 ----------------
    reg [IAW-1:0] in_waddr;
    reg in_we;
    reg [31:0] in_wdata;
    wire [31:0] in_rdata;

    reg [FAW-1:0] f_waddr;
    reg f_we;
    reg [127:0] f_wdata;
    wire [FAW-1:0] f_raddr_cpu;
    wire [127:0] f_rdata;
    wire [127:0] w_data;
    wire [63:0] bm_data;

    reg [IAW-1:0] in_addr;
    reg [12:0] out_addr_reg;
    wire [FAW-1:0] f_raddr = (state == S_IDLE) ? f_raddr_cpu : f_raddr_eng;

    dpram #(
        .DW(32),
        .DP(`NN_IN_PIX)
    ) u_in_ram (
        .clk(clk),
        .we(in_we),
        .waddr(in_waddr),
        .wdata(in_wdata),
        .raddr(in_raddr),
        .rdata(in_rdata)
    );

    dpram #(
        .DW(128),
        .DP(`NN_A_WORDS + `NN_B_WORDS)
    ) u_feat (
        .clk(clk),
        .we(f_we),
        .waddr(f_waddr),
        .wdata(f_wdata),
        .raddr(f_raddr),
        .rdata(f_rdata)
    );

    nn_rom #(
        .DW(128),
        .DP(`NN_W_WORDS),
        .INIT_FILE("rtl/nn/nn_w.mem")
    ) u_wrom (
        .clk(clk),
        .addr(w_addr_x[9:0]),
        .data(w_data)
    );

    nn_rom #(
        .DW(64),
        .DP(`NN_BM_WORDS),
        .INIT_FILE("rtl/nn/nn_bm.mem")
    ) u_bmrom (
        .clk(clk),
        .addr(bm_addr_x[8:0]),
        .data(bm_data)
    );

    // ---------------- 总线 ----------------
    reg response_valid;
    reg rd_from_out;
    reg [31:0] data_r;

    wire [11:0] reg_off = addr_i[11:0];
    wire fire = req_valid_i && req_ready_o;
    wire is_out = (reg_off == 12'h014);

    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i);
    assign rsp_valid_o = response_valid;
    assign data_o = rd_from_out ? f_rdata[31:0] : data_r;
    assign busy_o = busy_r;
    assign done_o = done_r;
    assign f_raddr_cpu = `NN_OUT_BASE + out_addr_reg[FAW-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            response_valid <= 1'b0;
            rd_from_out <= 1'b0;
            data_r <= 32'h0;
            in_we <= 1'b0;
            in_waddr <= {IAW{1'b0}};
            in_wdata <= 32'h0;
            in_addr <= {IAW{1'b0}};
            out_addr_reg <= 13'd0;
            start_req <= 1'b0;
            done_r <= 1'b0;
            busy_r <= 1'b0;
            cyc <= 32'd0;
            state <= S_IDLE;
            layer <= 4'd0;
            f_we <= 1'b0;
            f_waddr <= {FAW{1'b0}};
            f_wdata <= 128'h0;
            py <= 8'd0;
            px <= 8'd0;
            cg <= 2'd0;
            row_y <= 19'sd0;
            row_base <= 21'sd0;
            col_x <= 9'sd0;
            out_pix <= 13'd0;
            ti <= 6'd0;
            ty <= 6'd0;
            tx <= 6'd0;
            issue_done <= 1'b0;
            use_v <= 1'b0;
            byte_sel_r <= 4'd0;
            in_range_r <= 1'b0;
            rq_n <= 5'd0;
            rq_m <= 5'd0;
            rq1_v <= 1'b0;
            rq2_v <= 1'b0;
            rq1_m <= 4'd0;
            rq2_m <= 4'd0;
            rq1_sum <= 33'sd0;
            rq1_mul <= 32'sd0;
            rq2_prod <= 64'sd0;
            out_word <= 128'h0;
            cshift_in <= 2'd0;
            cshift_out <= 2'd0;
            cgroups_out <= 3'd1;
            src_b <= 1'b0;
            dst_b <= 1'b0;
            for (j = 0; j < 16; j = j + 1) acc[j] <= 32'sd0;
        end else begin
            in_we <= 1'b0;
            f_we <= 1'b0;

            // ---- 总线读响应 ----
            if (response_valid && rsp_ready_i) begin
                response_valid <= 1'b0;
                rd_from_out <= 1'b0;
            end
            if (fire) begin
                response_valid <= 1'b1;
                rd_from_out <= !we_i && is_out;
                if (we_i) begin
                    case (reg_off)
                        12'h000: begin  // CTRL
                            if (data_i[0] && !busy_r) begin
                                start_req <= 1'b1;
                                done_r <= 1'b0;
                            end
                            if (data_i[1]) done_r <= 1'b0;
                        end
                        12'h008: begin  // IN
                            in_we <= 1'b1;
                            in_waddr <= in_addr;
                            // 存成模型要的定点数: q = pixel - 128 (XOR 0x80), 通道顺序 B,
                            // G, R (和 model/handnet.py 的 BGR 一致)
                            in_wdata <= {8'b0, data_i[23:16] ^ 8'h80, data_i[15:8] ^ 8'h80,
                                         data_i[7:0] ^ 8'h80};
                            in_addr <= in_addr + 1'b1;
                        end
                        12'h00c: in_addr <= data_i[IAW-1:0];      // IN_ADDR
                        12'h010: out_addr_reg <= data_i[12:0];    // OUT_ADDR
                        default: ;
                    endcase
                end else begin
                    case (reg_off)
                        12'h004: data_r <= {24'd0, layer, 2'b0, done_r, busy_r};  // STATUS
                        12'h00c: data_r <= {{32 - IAW{1'b0}}, in_addr};
                        12'h010: data_r <= {{19{1'b0}}, out_addr_reg};
                        12'h018: data_r <= cyc;
                        12'h01c: data_r <= 32'h4e4e_0001;
                        12'h020: data_r <= `NN_IN_PIX;
                        default: data_r <= 32'h0;
                    endcase
                end
            end

            // ---- 引擎 ----
            if (busy_r) cyc <= cyc + 32'd1;
            case (state)
                S_IDLE: begin
                    if (start_req) begin
                        start_req <= 1'b0;
                        layer <= 4'd0;
                        state <= S_SETUP;
                        busy_r <= 1'b1;
                        cyc <= 32'd0;
                    end
                end
                S_SETUP: begin
                    py <= 8'd0;
                    px <= 8'd0;
                    cg <= 2'd0;
                    out_pix <= 13'd0;
                    col_x <= (cfg_k == 2'd3) ? -9'sd1 : 9'sd0;
                    row_y <= (cfg_k == 2'd3) ? -19'sd1 : 19'sd0;
                    row_base <= (cfg_k == 2'd3) ? (21'sd0 - iw_s) : 21'sd0;
                    cshift_in <= ((cfg_mode ? cfg_cout : cfg_cin) > 7'd32) ? 2'd2
                               : ((cfg_mode ? cfg_cout : cfg_cin) > 7'd16) ? 2'd1 : 2'd0;
                    cshift_out <= (cfg_cout > 7'd32) ? 2'd2 : (cfg_cout > 7'd16) ? 2'd1 : 2'd0;
                    cgroups_out <= cgroups_x[2:0];
                    src_b <= cfg_src_in ? 1'b0 : ~cfg_dst_b;
                    dst_b <= cfg_dst_b;
                    state <= S_PIX;
                end
                S_PIX: begin
                    for (j = 0; j < 16; j = j + 1) acc[j] <= 32'sd0;
                    out_word <= 128'h0;
                    ti <= 6'd0;
                    ty <= 6'd0;
                    tx <= 6'd0;
                    issue_done <= 1'b0;
                    use_v <= 1'b0;
                    state <= S_TAP;
                end
                S_TAP: begin
                    if (use_v) begin
                        for (j = 0; j < 16; j = j + 1) begin
                            if (cfg_mode) begin
                                acc[j] <= acc[j] + $signed(act_q[8*j+:8]) * $signed(w_data[8*j+:8]);
                            end else begin
                                acc[j] <= acc[j] + $signed(act_q[8*byte_sel_r+:8]) * $signed(w_data[8*j+:8]);
                            end
                        end
                    end
                    if (!issue_done) begin
                        byte_sel_r <= cfg_mode ? 4'd0 : ti[3:0];
                        in_range_r <= in_range;
                        use_v <= 1'b1;
                        if ((tx == k_last) && (ty == k_last) && (cfg_mode || (ti == cin_last))) begin
                            issue_done <= 1'b1;
                        end else if (tx != k_last) begin
                            tx <= tx + 6'd1;
                        end else begin
                            tx <= 6'd0;
                            if (ty != k_last) begin
                                ty <= ty + 6'd1;
                            end else begin
                                ty <= 6'd0;
                                ti <= ti + 6'd1;
                            end
                        end
                    end else if (use_v) begin
                        use_v <= 1'b0;
                        rq_n <= 5'd0;
                        rq_m <= 5'd0;
                        state <= S_RQ;
                    end
                end
                S_RQ: begin
                    // use_v: 乘数/偏置 ROM 这一拍的读数有效 (rq_n 上一拍发的地址)
                    rq1_v <= use_v;
                    rq2_v <= rq1_v;
                    if (use_v) begin
                        rq1_m <= rq_m[3:0];
                        rq1_sum <= $signed({acc_sel[31], acc_sel}) + $signed({b_sel[31], b_sel});
                        rq1_mul <= $signed(bm_data[31:0]);
                        rq_m <= rq_m + 5'd1;
                    end
                    if (rq1_v) begin
                        rq2_m <= rq1_m;
                        rq2_prod <= prod_65[63:0];
                    end
                    if (rq2_v) out_word[8*rq2_m+:8] <= rq_valid ? rq_byte : 8'h0;
                    if (rq_n != 5'd16) begin
                        rq_n <= rq_n + 5'd1;
                        use_v <= 1'b1;
                    end else begin
                        use_v <= 1'b0;
                        if (!use_v && !rq1_v && rq2_v) state <= S_WRITE;
                    end
                end
                S_WRITE: begin
                    f_we <= 1'b1;
                    f_waddr <= out_addr[FAW-1:0];
                    f_wdata <= out_word;
                    // out_pix 是像素序号 (不是通道组序号), 通道组由 cg 单独加
                    if (cg + 2'd1 != cgroups_out[1:0]) begin
                        cg <= cg + 2'd1;
                        state <= S_PIX;
                    end else begin
                        cg <= 2'd0;
                        out_pix <= out_pix + 13'd1;
                        if (px + 8'd1 != cfg_out_w) begin
                            px <= px + 8'd1;
                            col_x <= col_x + (cfg_stride2 ? 9'sd2 : 9'sd1);
                            state <= S_PIX;
                        end else begin
                            px <= 8'd0;
                            col_x <= (cfg_k == 2'd3) ? -9'sd1 : 9'sd0;
                            if (py + 8'd1 != cfg_out_h) begin
                                py <= py + 8'd1;
                                row_y <= row_y + (cfg_stride2 ? 19'sd2 : 19'sd1);
                                row_base <= row_base
                                    + (cfg_stride2 ? $signed({iw_s[19:0], 1'b0}) : iw_s);
                                state <= S_PIX;
                            end else if (layer + 4'd1 == `NN_LAYERS) begin
                                busy_r <= 1'b0;
                                done_r <= 1'b1;
                                state <= S_IDLE;
                            end else begin
                                layer <= layer + 4'd1;
                                state <= S_SETUP;
                            end
                        end
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
