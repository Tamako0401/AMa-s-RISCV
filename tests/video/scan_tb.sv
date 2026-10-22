// 不依赖固件的双时钟扫描检查, 64 个精灵同时命中一行。
`timescale 1ns / 1ps
module scan_tb;
    parameter MODE_720P = 0;
    localparam W = MODE_720P ? 1280 : 640, H = MODE_720P ? 720 : 480;
    localparam SCALE = MODE_720P ? 3 : 2, LEFT = MODE_720P ? 160 : 0;
    localparam HT = MODE_720P ? 1650 : 800, VT = MODE_720P ? 750 : 525;
    reg clk = 0, pix_clk = 0, rst_n = 0;
    always #10 clk = ~clk;
    always #(MODE_720P ? 6.734006734 : 20) pix_clk = ~pix_clk;
    reg [31:0] addr = 0, data = 0;
    reg valid = 0, we = 0;
    wire ready, rsp;
    wire [31:0] rdata;
    wire pclk, hs, vs, de;
    wire [23:0] rgb;
    video #(.MODE_720P(MODE_720P)) dut (
        .clk(clk), .pix_clk(pix_clk), .rst_n(rst_n), .addr_i(addr), .data_i(data), .sel_i(4'hf),
        .we_i(we), .data_o(rdata), .req_valid_i(valid), .req_ready_o(ready),
        .rsp_valid_o(rsp), .rsp_ready_i(1'b1),
        .pclk(pclk), .hsync_n(hs), .vsync_n(vs), .de(de), .rgb(rgb),
        .win_raddr(), .win_rdata(8'h1c)
    );
    video_sink #(.W(W), .H(H), .SYNC_POSITIVE(MODE_720P)) sink (
        .pclk(pclk), .hsync_n(hs), .vsync_n(vs), .de(de), .rgb(rgb));
    task automatic access(input bit wr, input integer a, input integer d);
        @(negedge clk); addr = a; data = d; we = wr; valid = 1;
        do @(posedge clk); while (!ready);
        @(negedge clk); valid = 0;
        if (!rsp) $fatal(1, "没有总线响应");
    endtask
    integer i, x, y, lx, ly, elapsed = 0, worst = 0;
    reg [23:0] want;
    always @(posedge clk) if (rst_n) begin
        if (dut.start) elapsed = 0;
        else elapsed = elapsed + 1;
        if (dut.lb_we) begin
            if (elapsed > worst) worst = elapsed;
            if (elapsed > 1733) $fatal(1, "渲染超时 %0d", elapsed);
        end
    end
    // 每个行、场同步的持续拍数和周期都检查。
    integer ticks = 0, last_hs = -1, last_vs = -1, hs_width = 0, vs_width = 0;
    reg hs_q = !MODE_720P, vs_q = !MODE_720P;
    always @(posedge pclk) if (rst_n) begin
        ticks++;
        if (hs == MODE_720P) hs_width++;
        if (vs == MODE_720P) vs_width++;
        if (hs == MODE_720P && hs_q != MODE_720P) begin
            if (last_hs >= 0 && ticks - last_hs != HT) $fatal(1, "行周期");
            last_hs = ticks;
        end
        if (hs != MODE_720P && hs_q == MODE_720P) begin
            if (hs_width != (MODE_720P ? 40 : 96)) $fatal(1, "行同步宽度");
            hs_width = 0;
        end
        if (vs == MODE_720P && vs_q != MODE_720P) begin
            if (last_vs >= 0 && ticks - last_vs != HT*VT) $fatal(1, "帧周期");
            last_vs = ticks;
        end
        if (vs != MODE_720P && vs_q == MODE_720P) begin
            if (vs_width != HT*(MODE_720P ? 5 : 2)) $fatal(1, "场同步宽度");
            vs_width = 0;
        end
        hs_q = hs; vs_q = vs;
    end
    initial begin
        repeat (6) @(negedge clk); rst_n = 1;
        access(1, 'h1004, 'hf800); access(1, 'h1008, 'h001f);
        for (i = 0; i < 48; i++) access(1, 'h8000 + i*4, i < 8 || i >= 16 ? 'h11111111 : 'h22222222);
        for (i = 0; i < 2048; i++) access(1, 'h4000 + i*4, i%2);
        for (i = 0; i < 64; i++) access(1, 'h2000 + i*4, 'h80080000 | (16<<9));
        access(1, 4, (5<<16)|3); access(1, 16, (8<<16)|152); access(1, 0, 3);
        wait (sink.frames >= 3); #1;
        if (sink.bad_lines || sink.y != 0) $fatal(1, "有效尺寸错误");
        for (y = 0; y < H; y++) for (x = 0; x < W; x++) begin
            lx = (x-LEFT)/SCALE; ly = y/SCALE;
            want = ((lx+3)/8)%2 ? 24'h0000ff : 24'hff0000;
            if (lx < 16 && ly >= 16 && ly < 32) want = 24'hff0000;
            if (lx >= 152 && lx < 312 && ly >= 8 && ly < 128) want = 24'h00ff00;
            if (x < LEFT || x >= W-LEFT) want = 0;
            if (sink.fb[y*W+x] !== want)
                $fatal(1, "(%0d,%0d) 实际 %06h 期望 %06h", x, y, sink.fb[y*W+x], want);
        end
        access(0, 8, 0); if (rdata != 1) $fatal(1, "STATUS 场消隐跨域");
        access(0, 12, 0); if (rdata != 3) $fatal(1, "FRAME 跨域 %0d", rdata);
        $display("[result] %0dx%0d 全像素/同步/FRAME/STATUS, 最坏渲染 %0d 拍", W, H, worst);
        $finish;
    end
    initial begin #60000000; $fatal(1, "超时"); end
endmodule
