// 声音 (外设子总线 0x4000_8000): 3 个方波声道 + 1 个噪声声道, 混成 16 位, 标准 I2S 输出 (48 kHz, 64 BCLK 一帧)。
// 寄存器和用法见 docs/audio.md。三根线 BCLK / LRCK / DOUT 是 GPIO 矩阵的输出信号 5 / 6 / 7, 由 C 接到功放的脚上。
//
// I2S: LRCK 低 = 左声道, 左右各 32 位槽; 数据 MSB 先发, LRCK 变后晚一个 BCLK 才发最高位 (一位延迟);
// 在 BCLK 下降沿换数据, 接收方在上升沿采。16 位样本高位对齐, 槽里其余位补 0; 左右声道是同一个样本。
// MAX98357A (I2S 版) 不要 MCLK, 能直接吃。
// BCLK 平均 64 × 48 kHz = 3.072 MHz, 由 50 MHz 相位累加得到 (每 3125 拍 384 个边沿, 同 i2s_beep spike):
// 平均频率精确, 每个边沿抖一个 clk (20 ns)。CTRL.EXACT = 1 时改成 clk / 16 整数分频 (BCLK 3.125 MHz,
// 采样率 48.828 kHz, 没有抖动, 音高高 1.7%), 留给挑时钟的功放。只适用 50 MHz 的 clk。
//
// 每帧 (一个采样) 更新一次声道: 相位 += FREQ; 方波相位高 8 位 < DUTY 输出 +幅度, 否则 -幅度;
// 噪声声道相位溢出一次 LFSR 走一步, 最低位定正负。幅度 = VOL × 32, 四个声道最大 4 × 255 × 32 = 32640, 相加不会溢出。
// FREQ 或 VOL 为 0 的声道输出 0。LEN 不为 0 时每帧减 1, 减到 0 那帧把 VOL 清 0 (音效放完自己停)。
// 混音只是 4 个数相加, 打一拍; 下一帧开头装进移位寄存器, 所以输出比寄存器晚 1~2 帧。没有块 RAM。
module audio (
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

    output reg bclk,
    output reg lrck,
    output reg dout
);
    localparam [12:0] STEP = 13'd384, MOD = 13'd3125;  // 128 × 48000 / 50 MHz = 384 / 3125

    // ---------------- 总线 ----------------
    reg response_valid;
    reg [31:0] data_r;
    wire wen = we_i & req_valid_i & req_ready_o;
    wire ren = (~we_i) & req_valid_i & req_ready_o;
    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i);
    assign rsp_valid_o = response_valid;
    assign data_o = data_r;

    // 地址: [6:4] = 0 全局, 1~4 = 声道 0~3; [3:2] = 声道里的第几个寄存器
    wire [2:0] block = addr_i[6:4];
    wire [1:0] field = addr_i[3:2];
    wire is_ctrl = addr_i[11:2] == 10'h000;

    reg en, exact;
    reg [31:0] samples;  // 出了多少帧
    reg signed [15:0] mix;  // 最近一次混好的样本

    // ---------------- 声道 ----------------
    reg [15:0] freq[0:3];
    reg [7:0] vol[0:3];
    reg [7:0] duty[0:3];  // 噪声声道: bit0 = 短周期 (93 步)
    reg [15:0] len[0:3];
    reg [15:0] phase[0:3];
    reg [14:0] lfsr;
    wire frame_tick;  // 一帧开始 (一拍)

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : g_ch
            wire wr = wen && addr_i[11:7] == 0 && block == g + 1;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    freq[g]  <= 0;
                    vol[g]   <= 0;
                    duty[g]  <= 8'd128;
                    len[g]   <= 0;
                    phase[g] <= 0;
                end else if (wr) begin  // CPU 写优先, 这一帧的计数让一下
                    case (field)
                        0: begin
                            if (sel_i[0]) freq[g][7:0] <= data_i[7:0];
                            if (sel_i[1]) freq[g][15:8] <= data_i[15:8];
                        end
                        1: if (sel_i[0]) vol[g] <= data_i[7:0];
                        2: if (sel_i[0]) duty[g] <= data_i[7:0];
                        default: begin
                            if (sel_i[0]) len[g][7:0] <= data_i[7:0];
                            if (sel_i[1]) len[g][15:8] <= data_i[15:8];
                        end
                    endcase
                end else if (frame_tick) begin
                    phase[g] <= phase[g] + freq[g];
                    if (len[g] != 0) begin
                        len[g] <= len[g] - 1'b1;
                        if (len[g] == 1) vol[g] <= 0;
                    end
                end
            end
        end
    endgenerate

    // 噪声: 15 位 LFSR (同 NES), 相位溢出一次走一步
    wire noise_step = frame_tick && {1'b0, phase[3]} + {1'b0, freq[3]} > 17'h0ffff;
    wire lfsr_fb = lfsr[0] ^ (duty[3][0] ? lfsr[6] : lfsr[1]);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= 15'd1;
        else if (noise_step) lfsr <= {lfsr_fb, lfsr[14:1]};
    end

    // 各声道的输出: ±VOL×32, 都是寄存器值, 下一拍相加。方波: 相位高 8 位 < DUTY 为正; 噪声: LFSR 最低位为正
    wire [63:0] outs;
    generate
        for (g = 0; g < 4; g = g + 1) begin : g_out
            wire [15:0] amp = {3'b000, vol[g], 5'b00000};
            wire high = g == 3 ? lfsr[0] : phase[g][15:8] < duty[g];
            assign outs[g*16+:16] = (vol[g] == 0 || freq[g] == 0) ? 16'd0 : high ? amp : 16'd0 - amp;
        end
    endgenerate

    reg mix_tick;  // frame_tick 的下一拍: 声道刚更新完
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mix_tick <= 0;
            mix <= 0;
            samples <= 0;
        end else begin
            mix_tick <= frame_tick;
            if (mix_tick) begin
                mix <= outs[15:0] + outs[31:16] + outs[47:32] + outs[63:48];
                samples <= samples + 1'b1;
            end
        end
    end

    // ---------------- 寄存器读写 ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en <= 0;
            exact <= 0;
            response_valid <= 0;
            data_r <= 0;
        end else begin
            if (wen && is_ctrl && sel_i[0]) begin
                en <= data_i[0];
                exact <= data_i[1];
            end
            if (response_valid && rsp_ready_i) response_valid <= 0;
            if (req_valid_i && req_ready_o) begin
                response_valid <= 1;
                data_r <= 0;
            end
            if (ren) begin
                if (block == 0)
                    case (field)
                        0: data_r <= {30'b0, exact, en};
                        1: data_r <= samples;
                        2: data_r <= {{16{mix[15]}}, mix};
                        default: data_r <= 0;
                    endcase
                else if (addr_i[11:7] == 0 && block <= 4)
                    case (field)
                        0: data_r <= {16'b0, freq[block-1]};
                        1: data_r <= {24'b0, vol[block-1]};
                        2: data_r <= {24'b0, duty[block-1]};
                        default: data_r <= {16'b0, len[block-1]};
                    endcase
            end
        end
    end

    // ---------------- I2S ----------------
    // BCLK 的每个边沿一个 tick: 平时相位累加 (平均 3.072 MHz), EXACT 时每 8 拍一个 (3.125 MHz)
    reg [11:0] acc;
    wire [12:0] acc_next = {1'b0, acc} + STEP;
    wire [12:0] acc_wrap = acc_next - MOD;
    wire tick = exact ? acc[2:0] == 3'd7 : acc_next >= MOD;

    reg [5:0] pos;  // 正在发一帧里的第几个 BCLK: 0~31 左声道, 32~63 右声道
    wire [5:0] pos_next = pos + 1'b1;
    reg [15:0] sample;  // 这一帧的样本: 左槽开头取 mix, 右槽再发一遍同一个
    reg [15:0] shreg;
    // 新的一帧从这个下降沿开始 (LRCK 变低): 装样本, 声道走一步
    assign frame_tick = en && tick && bclk && pos_next == 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 0;
            bclk <= 0;
            lrck <= 1'b1;
            dout <= 0;
            pos <= 6'd63;
            sample <= 0;
            shreg <= 0;
        end else if (!en) begin  // 关着: 时钟停, 功放没有 BCLK 自己静音
            acc <= 0;
            bclk <= 0;
            lrck <= 1'b1;
            dout <= 0;
            pos <= 6'd63;
            sample <= 0;
            shreg <= 0;
        end else begin
            if (exact) acc <= {9'b0, acc[2:0] + 3'd1};
            else acc <= tick ? acc_wrap[11:0] : acc_next[11:0];
            if (tick) begin
                bclk <= !bclk;
                if (bclk) begin  // 这个 tick 是下降沿
                    pos  <= pos_next;
                    lrck <= pos_next[5];
                    if (pos_next[4:0] == 0) begin
                        dout <= 0;  // LRCK 刚变, 这一位还属于上一个槽的补 0
                        if (!pos_next[5]) begin
                            sample <= mix;
                            shreg  <= mix;
                        end else begin
                            shreg <= sample;
                        end
                    end else begin
                        dout  <= shreg[15];
                        shreg <= {shreg[14:0], 1'b0};
                    end
                end
            end
        end
    end
endmodule
