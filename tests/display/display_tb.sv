// 新显示 (rtl/display/) 的整帧比对: 只有 display, 没有 CPU。
// +data=<目录>: game/tools/refmodel.py export 写的 writes.hex (依次走总线写, 最后一项是提交)、window.hex (小窗)、
// expect.hex (参考模型画的 1280x720 RGB888)。提交生效后收一整帧, 和 expect.hex 逐点比, 一个点都不能差。
// 不一致时把收到的画面存成 <目录>/got.ppm (+ppm=1 时也存), 和 expect.png 对着看。
`timescale 1ns / 1ps
module display_tb;
    localparam W = 1280, H = 720;
    localparam [31:0] REG_COMMIT = 32'h1C, REG_LINE_MAX = 32'h28, REG_OVERRUN = 32'h2C;
    localparam [31:0] REG_DROPPED = 32'h30;

    reg clk = 0, pclk = 0, rst_n = 0;
    always #10 clk = ~clk;  // 50 MHz
    always #6.734 pclk = ~pclk;  // 74.25 MHz

    reg [31:0] addr = 0, wdata = 0;
    reg we = 0, req_valid = 0;
    wire [31:0] rdata;
    wire req_ready, rsp_valid;
    wire pclk_o, hsync_n, vsync_n, de;
    wire [23:0] rgb;
    wire [14:0] win_raddr;
    reg [7:0] win_rdata;
    reg [7:0] window[0:160*120-1];
    always @(posedge clk) win_rdata <= window[win_raddr];

    display u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(addr),
        .data_i(wdata),
        .sel_i(4'hF),
        .we_i(we),
        .data_o(rdata),
        .req_valid_i(req_valid),
        .req_ready_o(req_ready),
        .rsp_valid_o(rsp_valid),
        .rsp_ready_i(1'b1),
        .pclk(pclk),
        .pclk_o(pclk_o),
        .hsync_n(hsync_n),
        .vsync_n(vsync_n),
        .de(de),
        .rgb(rgb),
        .win_raddr(win_raddr),
        .win_rdata(win_rdata)
    );
    video_sink #(
        .W(W),
        .H(H)
    ) u_sink (
        .pclk(pclk_o),
        .hsync_n(hsync_n),
        .vsync_n(vsync_n),
        .de(de),
        .rgb(rgb)
    );

    task automatic bus(input logic [31:0] a, input logic [31:0] d, input logic write,
                       output logic [31:0] q);
        @(negedge clk);
        addr = a;
        wdata = d;
        we = write;
        req_valid = 1;
        do @(posedge clk); while (!req_ready);
        @(negedge clk);
        req_valid = 0;
        we = 0;
        while (!rsp_valid) @(negedge clk);
        q = rdata;
    endtask

    reg [63:0] writes[0:65535];
    reg [23:0] expect_px[0:W*H-1];
    string dir;
    integer i, n, bad, frames0, ppm;
    reg [31:0] q, line_max, overrun, dropped;

    task automatic save_ppm(input string path);
        integer f, k;
        begin
            f = $fopen(path, "wb");
            $fwrite(f, "P6\n%0d %0d\n255\n", W, H);
            for (k = 0; k < W * H; k = k + 1)
            $fwrite(f, "%c%c%c", u_sink.fb[k][23:16], u_sink.fb[k][15:8], u_sink.fb[k][7:0]);
            $fclose(f);
        end
    endtask

    initial begin
        if (!$value$plusargs("data=%s", dir)) $fatal(1, "Missing +data=<目录>");
        $readmemh({dir, "/writes.hex"}, writes);
        $readmemh({dir, "/window.hex"}, window);
        $readmemh({dir, "/expect.hex"}, expect_px);
        repeat (5) @(negedge clk);
        rst_n = 1;

        for (n = 0; writes[n][63:32] != 32'hFFFFFFFF; n = n + 1)
        bus(writes[n][63:32], writes[n][31:0], 1, q);
        $display("[display_tb] 写了 %0d 次, 等提交生效", n);
        do bus(REG_COMMIT, 0, 0, q); while (q[0]);  // 下一个场消隐才生效
        // 提交之后每帧都一样; 收满两帧, 取第二帧 (第一帧可能是提交前开始的)
        frames0 = u_sink.frames;
        wait (u_sink.frames == frames0 + 2);

        bad = 0;
        for (i = 0; i < W * H; i = i + 1)
        if (u_sink.fb[i] !== expect_px[i]) begin
            if (bad < 10)
                $display(
                    "[display_tb] (%0d, %0d) 逻辑 (%0d, %0d): 收到 %06x, 应为 %06x",
                    i % W,
                    i / W,
                    i % W / 2,
                    i / W / 2,
                    u_sink.fb[i],
                    expect_px[i]
                );
            bad = bad + 1;
        end
        bus(REG_LINE_MAX, 0, 0, line_max);
        bus(REG_OVERRUN, 0, 0, overrun);
        bus(REG_DROPPED, 0, 0, dropped);
        $display(
            "[result] 不一致的点 %0d, 最忙一行 %0d 拍, 超时 %0d 行, 丢掉对象 %0d",
            bad, line_max, overrun, dropped);
        if (!$value$plusargs("ppm=%d", ppm)) ppm = 0;
        if (bad || ppm) begin
            save_ppm({dir, "/got.ppm"});
            $display("[display_tb] 收到的画面 -> %s/got.ppm", dir);
        end
        if (bad || u_sink.bad_lines)
            $fatal(
                1,
                "画面和参考模型不一致 (%0d 点), 宽度不对的行 %0d",
                bad,
                u_sink.bad_lines
            );
        $finish;
    end

    initial begin
        #200_000_000;  // 200 ms, 十几帧
        $fatal(1, "超时");
    end
endmodule
