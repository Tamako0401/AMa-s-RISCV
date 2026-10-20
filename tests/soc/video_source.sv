// 视频源模型 (相当于电脑 + HDMI 接收芯片) — 仅用于仿真。
// 自己产生 25 MHz 像素时钟, 按 640x480@60 的时序输出 de 和 RGB888。
// 画面: 默认是 pattern() 算出的测试图; +vin=<文件> 时改为文件里的 640x480 RGB888 (每像素 3 字节, R G B)。
`timescale 1ns / 1ps
module video_source #(
    parameter W = 640,
    parameter H = 480,
    parameter H_TOTAL = 800,
    parameter V_TOTAL = 525
) (
    output reg pclk = 0,
    output reg de = 0,
    output reg [23:0] rgb = 0
);
    always #20 pclk = ~pclk;

    reg [23:0] image[0:W*H-1];
    integer from_file = 0;
    integer h = 0, v = 0;

    // 测试图: 横向红色渐变, 纵向绿色渐变, 蓝色是 32 像素的棋盘格
    function automatic [23:0] pattern(input integer x, input integer y);
        pattern = {x[8:1], y[8:1], x[5] ^ y[5] ? 8'hFF : 8'h00};
    endfunction

    initial begin
        string path;
        integer fd, i;
        if ($value$plusargs("vin=%s", path)) begin
            fd = $fopen(path, "rb");
            if (fd == 0) $fatal(1, "video_source: 打不开 %0s", path);
            for (i = 0; i < W * H; i = i + 1)
            image[i] = {8'($fgetc(fd)), 8'($fgetc(fd)), 8'($fgetc(fd))};
            $fclose(fd);
            from_file = 1;
        end
    end

    always @(negedge pclk) begin
        de  <= h < W && v < H;
        rgb <= h < W && v < H ? (from_file ? image[v*W+h] : pattern(h, v)) : 24'h0;
        h   <= h == H_TOTAL - 1 ? 0 : h + 1;
        if (h == H_TOTAL - 1) v <= v == V_TOTAL - 1 ? 0 : v + 1;
    end
endmodule
