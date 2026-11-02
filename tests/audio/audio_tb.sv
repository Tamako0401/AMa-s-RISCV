`timescale 1ns / 1ps
// 声音外设 (rtl/perips/audio.v): 经总线写寄存器, 测试台自己当 I2S 接收端解码 BCLK / LRCK / DOUT,
// 核对槽格式 (32 位槽、一位延迟、16 位高位对齐补 0、左右相同)、采样率、BCLK 周期、
// 方波的频率 / 音量 / 占空比、两个声道相加、噪声 (长 / 短周期)、LEN 自停、EXACT 整数分频和关掉后时钟停。
module audio_tb;
    reg clk = 0;
    always #10 clk = ~clk;  // 50 MHz
    reg rst_n = 0;
    reg [31:0] addr = 0, wdata = 0;
    reg [3:0] sel = 4'hf;
    reg we = 0, valid = 0, rsp_ready = 0;
    wire ready, rsp_valid;
    wire [31:0] rdata;
    wire bclk, lrck, dout;
    audio dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(addr),
        .data_i(wdata),
        .sel_i(sel),
        .we_i(we),
        .data_o(rdata),
        .req_valid_i(valid),
        .req_ready_o(ready),
        .rsp_valid_o(rsp_valid),
        .rsp_ready_i(rsp_ready),
        .bclk(bclk),
        .lrck(lrck),
        .dout(dout)
    );

    task static check(input bit ok, input string message);
        if (!ok) begin
            $display("FAIL audio: %s", message);
            $fatal(1);
        end
    endtask

    reg [31:0] result;
    task static access (input bit write_en, input logic [31:0] offset, input logic [31:0] value);
        @(negedge clk);
        addr = offset;
        wdata = value;
        we = write_en;
        valid = 1;
        @(posedge clk);
        check(ready === 1'b1, "request ready");
        #1;
        check(rsp_valid === 1'b1, "registered response");
        result = rdata;
        @(negedge clk);
        valid = 0;
        rsp_ready = 1;
        @(posedge clk);
        @(negedge clk);
        rsp_ready = 0;
    endtask
    task static wr(input logic [31:0] offset, input logic [31:0] value);
        access (1, offset, value);
    endtask
    task static read_check(input logic [31:0] offset, input logic [31:0] expected);
        access (0, offset, 0);
        check(result === expected, $sformatf("read %h got %h expected %h", offset, result, expected
              ));
    endtask
    // 声道 n 的寄存器
    function automatic [31:0] ch(input integer n, input integer field);
        ch = 32'h10 + 32'h10 * n + 4 * field;
    endfunction

    // ---------------- I2S 接收端 ----------------
    // 每个 BCLK 上升沿采一位; LRCK 在某个上升沿看到变了, 这一位还是上一个槽的最后一位 (一位延迟)。
    localparam MAXF = 50000;
    integer nframes = 0, nbits = 0, slots = 0;
    reg started = 0, prev_lrck = 1;
    reg [31:0] word = 0;
    reg signed [15:0] left;
    integer s[0:MAXF-1];
    realtime t[0:MAXF-1];
    realtime last_rise = 0, min_period = 1e9, max_period = 0;
    always @(posedge bclk) begin
        if (last_rise > 0) begin
            if ($realtime - last_rise < min_period) min_period = $realtime - last_rise;
            if ($realtime - last_rise > max_period) max_period = $realtime - last_rise;
        end
        last_rise = $realtime;
        word = {word[30:0], dout};
        nbits = nbits + 1;
        if (lrck !== prev_lrck) begin
            if (started) begin
                check(nbits == 32, $sformatf("slot length %0d", nbits));
                check(word[15:0] == 0, "padding not zero");
                if (!prev_lrck) left = word[31:16];  // 左槽
                else begin
                    check($signed(word[31:16]) == left, "left/right differ");
                    if (nframes < MAXF) begin
                        s[nframes] = left;
                        t[nframes] = $realtime;
                    end
                    nframes = nframes + 1;
                end
                slots = slots + 1;
            end
            started = 1;
            nbits   = 0;
        end
        prev_lrck = lrck;
    end

    // 抓 n 帧: 返回起始帧号; 先丢 4 帧, 让刚写的寄存器走到输出 (晚 1~2 帧)
    integer first;
    task static capture(input integer n);
        integer start;
        start = nframes;
        wait (nframes >= start + 4);
        first = nframes;
        min_period = 1e9;
        max_period = 0;
        if (first + n > MAXF) $fatal(1, "capture buffer");
        wait (nframes >= first + n);
    endtask

    // 统计: 值都在 allowed 里 (最多 4 个), 正的帧数, 正负翻转次数
    integer highs, flips;
    task static stats(input integer n, input integer a, input integer b);
        integer i;
        highs = 0;
        flips = 0;
        for (i = first; i < first + n; i = i + 1) begin
            check(s[i] == a || s[i] == b, $sformatf(
                  "frame %0d sample %0d not %0d/%0d", i, s[i], a, b));
            if (s[i] > 0) highs = highs + 1;
            if (i > first && (s[i] > 0) != (s[i-1] > 0)) flips = flips + 1;
        end
    endtask

    // 启停总时钟时同步复位接收端状态, 保留已收样本。
    task static stop_audio;
        wr(0, 0);
        started = 0;
        prev_lrck = 1;
        nbits = 0;
        word = 0;
        last_rise = 0;
    endtask

    // 预填后启动, 不丢启动流水线: 第一帧静音, 后面逐样本核对。
    task static pcm_sequence(input integer div_value, input integer volume);
        integer start, d, k, expected, value;
        stop_audio();
        wr('h50, 0);
        wr('h50, (div_value << 4) | 1);
        wr('h5c, volume);
        wr('h54, 'h807ffe01);  // +1, -2, +127, -128
        read_check('h58, 4);
        start = nframes;
        wr(0, 1);
        d = div_value == 0 ? 1 : div_value;
        wait (nframes >= start + 1 + 4 * d + d);
        check(s[start] == 0, "PCM startup pipeline");
        for (k = 0; k < 4 * d; k = k + 1) begin
            case (k / d)
                0: value = 1;
                1: value = -2;
                2: value = 127;
                default: value = -128;
            endcase
            expected = value * volume;
            check(s[start+1+k] == expected, $sformatf(
                  "PCM DIV=%0d vol=%0d sample %0d got %0d expected %0d",
                  div_value,
                  volume,
                  k,
                  s[start+1+k],
                  expected
                  ));
        end
        check(s[start+1+4*d] == 0, "PCM underrun silence");
        stop_audio();
        wr('h50, 0);
        // 欠载计数独立累计, 每组检查前复位整个外设。
    endtask

    task static reset_audio;
        stop_audio();
        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
    endtask

    integer i, n, flips1, nonzero;
    realtime span;
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        read_check(0, 0);
        read_check(4, 0);
        read_check(ch(0, 2), 128);
        repeat (2000) @(posedge clk);
        check(!started && bclk === 1'b0, "BCLK stopped while disabled");

        // 1. 方波 1000 Hz (FREQ = 1000 × 65536 / 48000 = 1365 → 999.76 Hz), 音量 100 (幅度 3200), 占空比 50%
        wr(ch(0, 0), 1365);
        wr(ch(0, 1), 100);
        read_check(ch(0, 0), 1365);
        read_check(ch(0, 1), 100);
        wr(0, 1);
        capture(4800);  // 0.1 s
        stats(4800, 3200, -3200);
        check(flips >= 199 && flips <= 201, $sformatf("1000 Hz: %0d flips in 0.1 s", flips));
        check(highs >= 2390 && highs <= 2410, $sformatf("duty 50%%: %0d high", highs));
        span = t[first+4800-1] - t[first-1];
        check(span > 100e6 - 30 && span < 100e6 + 30, $sformatf(
              "sample rate: 4800 frames in %0t", span));
        check(min_period >= 319 && max_period <= 361, $sformatf(
              "BCLK period %0t..%0t", min_period, max_period));
        access (0, 4, 0);
        check(result >= first + 4800, "SAMPLES counts frames");
        access (0, 8, 0);
        check(result == 3200 || result == -3200, "MIX reads the last sample");

        // 2. 占空比 25%, 音量 255 (幅度 8160)
        wr(ch(0, 2), 64);
        wr(ch(0, 1), 255);
        capture(4800);
        stats(4800, 8160, -8160);
        check(highs >= 1190 && highs <= 1210, $sformatf("duty 25%%: %0d high", highs));

        // 3. 两个声道相加: 1000 Hz × 3200 + 440 Hz (FREQ 601 → 440.2 Hz) × 1600
        wr(ch(0, 2), 128);
        wr(ch(0, 1), 100);
        wr(ch(1, 0), 601);
        wr(ch(1, 1), 50);
        capture(4800);
        flips1 = 0;
        for (i = first; i < first + 4800; i = i + 1) begin
            check(s[i] == 4800 || s[i] == 1600 || s[i] == -1600 || s[i] == -4800, $sformatf(
                  "mix sample %0d", s[i]));
            // 拆出 1 号声道: 减掉 0 号声道 (幅度大的那个定正负)
            if (i > first && ((s[i] - (s[i] > 0 ? 3200 : -3200)) > 0) != ((s[i-1] - (s[i-1] > 0 ? 3200 : -3200)) > 0))
                flips1 = flips1 + 1;
        end
        check(flips1 >= 87 && flips1 <= 89, $sformatf("440 Hz in mix: %0d flips", flips1));
        wr(ch(0, 1), 0);
        wr(ch(1, 1), 0);
        capture(8);
        for (i = first; i < first + 8; i = i + 1) check(s[i] == 0, "VOL 0 is silent");

        // 4. 噪声: 每 2 帧走一步。长周期 (32767 步) 正负各约一半; 短周期 93 步, 样本 186 帧一轮
        wr(ch(3, 0), 16'h8000);
        wr(ch(3, 1), 100);
        capture(4800);
        stats(4800, 3200, -3200);
        check(highs > 2000 && highs < 2800 && flips > 1000, $sformatf(
              "noise: %0d high, %0d flips", highs, flips));
        n = 0;
        for (i = first; i < first + 4800 - 186; i = i + 1) if (s[i] != s[i+186]) n = n + 1;
        check(n > 500, "long noise is not 186-periodic");
        wr(ch(3, 2), 1);
        capture(4800);
        stats(4800, 3200, -3200);
        for (i = first + 400; i < first + 4800 - 186; i = i + 1)
        check(s[i] == s[i+186], $sformatf("short noise period at %0d", i));
        check(flips > 100, "short noise toggles");
        wr(ch(3, 1), 0);

        // 5. LEN: 放 480 帧 (10 ms) 自己停, VOL 读回 0
        wr(ch(2, 0), 1365);
        wr(ch(2, 3), 480);
        wr(ch(2, 1), 100);
        capture(1200);
        nonzero = 0;
        for (i = first - 4; i < first + 1200; i = i + 1) if (s[i] != 0) nonzero = nonzero + 1;
        check(nonzero >= 476 && nonzero <= 481, $sformatf("LEN 480: %0d frames sounded", nonzero));
        read_check(ch(2, 1), 0);
        read_check(ch(2, 3), 0);

        // 6. EXACT: BCLK = clk / 16 = 3.125 MHz, 一帧 1024 拍 (48.828 kHz), 没有抖动
        wr(ch(0, 1), 100);
        wr(0, 3);
        read_check(0, 3);
        capture(4800);
        stats(4800, 3200, -3200);
        span = t[first+4800-1] - t[first-1];
        check(span > 4800 * 20480 - 1 && span < 4800 * 20480 + 1, $sformatf("EXACT rate: %0t", span
              ));
        check(min_period == 320 && max_period == 320, $sformatf(
              "EXACT BCLK %0t..%0t", min_period, max_period));

        // 7. 关掉: 时钟停
        wr(0, 0);
        n = slots;
        repeat (5000) @(posedge clk);
        check(slots == n && bclk === 1'b0, "disabled: no more slots");

        // 8. PCM 字节序、符号、DIV=0/1/3/15、音量和欠载补零 (真实 I2S 解码)
        reset_audio();
        read_check('h50, 'h30);
        read_check('h5c, 0);
        pcm_sequence(0, 255);
        reset_audio();
        pcm_sequence(1, 17);
        reset_audio();
        pcm_sequence(3, 255);
        reset_audio();
        pcm_sequence(15, 0);

        // 9. 深度、满时整字丢弃、非整字写忽略、读写指针绕回, 启动前无欠载
        reset_audio();
        wr('h50, 'h11);
        wr('h5c, 1);
        sel = 1;
        wr('h54, 'hffffffff);
        sel = 15;
        read_check('h58, 0);
        for (i = 0; i < 512; i = i + 1) wr('h54, 'h04030201);
        read_check('h58, 2048);
        wr('h54, 'hffffffff);
        read_check('h58, 2048);
        n = nframes;
        wr(0, 1);
        wait (nframes >= n + 5);
        for (i = 0; i < 4; i = i + 1) check(s[n+1+i] == i + 1, "FIFO full preserves oldest");
        // 连续边播边补 128 个字, 跨过写指针的 512 字边界
        for (i = 0; i < 128; i = i + 1) begin
            wait (dut.pcm_level <= 2044);
            wr('h54, 'h04030201);
        end
        wait (nframes >= n + 2565);
        for (i = 0; i < 2560; i = i + 1)
        check(s[n+1+i] == (i % 4) + 1, $sformatf("FIFO wrap sample %0d", i));
        stop_audio();
        access (0, 'h58, 0);
        check(result[15:0] == 0 && result[31:16] != 0, "FIFO drained and underrun counted");

        // 10. 欠载按 DIV 取样节奏计数, 禁用 PCM 清 FIFO/当前样本但保留诊断计数
        reset_audio();
        wr('h50, 'h31);
        wr(0, 1);
        wait (dut.samples == 10);
        stop_audio();
        read_check('h58, 4 << 16);  // 帧 1/4/7/10 各欠载一次
        wr('h54, 'h04030201);
        wr('h50, 'h30);
        read_check('h58, 4 << 16);
        wr('h54, 'hffffffff);
        read_check('h58, 4 << 16);
        // 诊断计数边界, 避免仿真 65536 次欠载
        dut.pcm_under = 16'hfffe;
        wr('h50, 'h11);
        n = nframes;
        wr(0, 1);
        wait (nframes >= n + 4);
        stop_audio();
        read_check('h58, 'hffff0000);

        // 11. PCM 与波形相加的正/负饱和, 同时检查不超限时正常相加
        reset_audio();
        wr(ch(0, 0), 1);
        wr(ch(0, 1), 255);
        wr(ch(0, 2), 255);
        wr('h50, 'hf1);
        wr('h5c, 255);
        wr('h54, 'h7f7f7f7f);
        n = nframes;
        wr(0, 1);
        wait (nframes >= n + 6);
        check(s[n+2] == 32767, "positive saturation");
        stop_audio();
        wr(ch(0, 2), 0);
        wr('h50, 0);
        wr('h50, 'hf1);
        wr('h54, 'h80808080);
        n = nframes;
        wr(0, 1);
        wait (nframes >= n + 6);
        check(s[n+2] == -32768, "negative saturation");
        wr('h5c, 1);
        capture(4);
        check(s[first] == -8288, "PCM plus square within range");
        stop_audio();

        $display(
            "PASS audio: I2S slots, 48 kHz, square freq/volume/duty, mix, noise, LEN, EXACT, PCM FIFO/DIV/volume/underrun/saturation");
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "audio timeout");
    end
endmodule
