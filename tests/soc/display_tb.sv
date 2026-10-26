`timescale 1ns / 1ps
// 新显示的 SoC 级整帧比对: CPU 走 rib s3 把 refmodel.py export --soc 生成的重放脚本
// (display_check.c + script.c) 写进显示并提交, 测试台用 video_sink 收满两帧, 和
// expect.hex 逐点比 -- 标准同 tests/display (一个点都不能差), 但写的人、提交握手、
// 轮询都是真的 CPU + 总线。场景: bg / sprites / affine / overflow (小窗关的四个;
// 小窗要视觉输入, 留给以后接 video_source)。
//
// 程序就绪后从结束信箱 0x1000_0000 依次报 最忙一行 / 超时行 / 丢掉对象, 第 4 次写
// 0x600D600D 表示画面在出。这里不把信箱当"程序结束" -- 比对要收帧, 时钟不能停。
// +data=<目录>: refmodel 写的 expect.hex (比对用), 不一致时存 got.ppm 到同目录。
module display_tb;
    localparam W = 1280, H = 720;
    localparam [31:0] MAILBOX = 32'h10000000;

    reg clk = 0;
    always #10 clk = ~clk;  // 50 MHz
    reg pixel_clk = 0;
    always #6.734006734 pixel_clk = ~pixel_clk;  // 74.25 MHz
    reg rst_n = 0;

    wire video_pclk, hsync_n, vsync_n, de;
    wire [23:0] rgb;

    soc_top #(
        .VIDEO_720P(1),
        .DISPLAY_NEW(1)
    ) u_soc (
        .clk  (clk),
        .rst_n(rst_n),
        .io_o (),
        .io_oe(),
        .io_i ({128{1'b1}}),  // UART RX 空闲 = 1; 没有外设用引脚
        .video_clk(pixel_clk),
        .video_pclk(video_pclk),
        .video_hsync_n(hsync_n),
        .video_vsync_n(vsync_n),
        .video_de(de),
        .video_rgb(rgb),
        .vin_pclk(1'b0),  // 没有视觉输入 (场景都关小窗)
        .vin_de(1'b0),
        .vin_rgb(24'h0)
    );

    video_sink #(
        .W(W),
        .H(H)
    ) u_sink (
        .pclk   (video_pclk),
        .hsync_n(hsync_n),
        .vsync_n(vsync_n),
        .de     (de),
        .rgb    (rgb)
    );

    // 结束信箱: 看 CPU 的数据总线写 (同 soc_tb 的观察法)
    wire [31:0] da = u_soc.u_core.dbus_addr_o;
    wire [31:0] dw = u_soc.u_core.dbus_data_o;
    wire dwe = u_soc.u_core.dbus_we_o;
    wire dv = u_soc.u_core.dbus_req_valid_o;
    wire dr = u_soc.u_core.dbus_req_ready_i;

    reg [31:0] report_[0:2];
    integer reports = 0;
    always @(posedge clk)
        if (rst_n && dv && dr && dwe && da == MAILBOX) begin
            if (reports < 3)
                report_[reports] = dw;
            else if (dw !== 32'h600D600D)
                $fatal(1, "结束信箱第 %0d 次写 %h (前 3 次应是统计, 第 4 次 0x600D600D)", reports, dw);
            reports = reports + 1;
        end

    reg [23:0] expect_px[0:W*H-1];
    string dir;
    integer i, bad, frames0;

    task static save_ppm(input string path);
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
        string rom_path, ram_path;
        if (!$value$plusargs("data=%s", dir)) $fatal(1, "缺 +data=<目录>");
        $readmemh({dir, "/expect.hex"}, expect_px);
        // 程序镜像预载进 soc_top 内部的 rom/ram (同 soc_tb; 实机由综合初值/引导加载完成)
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "缺 +rom=hex");
        $readmemh(rom_path, u_soc.u_rom.mem);
        if ($value$plusargs("ram=%s", ram_path))
            $readmemh(ram_path, u_soc.u_ram.u_gen_ram.ram);
        repeat (5) @(negedge clk);
        rst_n = 1;

        wait (reports >= 4);
        $display("[display_tb] CPU 写完提交: 最忙一行 %0d 拍, 超时 %0d 行, 丢掉 %0d 个", report_[0], report_[1], report_[2]);
        // 提交之后每帧都一样; 收满两帧取第二帧 (第一帧可能是提交前开始的)
        frames0 = u_sink.frames;
        wait (u_sink.frames == frames0 + 2);

        bad = 0;
        for (i = 0; i < W * H; i = i + 1)
            if (u_sink.fb[i] !== expect_px[i]) begin
                if (bad < 10)
                    $display("[display_tb] (%0d, %0d): 收到 %06x, 应为 %06x", i % W, i / W, u_sink.fb[i], expect_px[i]);
                bad = bad + 1;
            end
        if (bad) begin
            save_ppm({dir, "/got.ppm"});
            $display("[display_tb] 收到的画面 -> %s/got.ppm", dir);
        end
        $display("[result] 不一致的点 %0d, 最忙一行 %0d 拍, 超时 %0d 行, 丢掉对象 %0d", bad, report_[0], report_[1], report_[2]);
        if (bad || u_sink.bad_lines)
            $fatal(1, "画面和参考模型不一致 (%0d 点), 宽度不对的行 %0d", bad, u_sink.bad_lines);
        if (report_[1] !== 0)
            $fatal(1, "有 %0d 行没画完 (超时)", report_[1]);
        $finish;
    end

    initial begin
        #200_000_000;  // 200 ms: CPU 写 ~8 千次 (慢) + 提交等一帧 + 收两帧
        $fatal(1, "超时 (信箱 %0d 次, 帧数 %0d)", reports, u_sink.frames);
    end
endmodule
