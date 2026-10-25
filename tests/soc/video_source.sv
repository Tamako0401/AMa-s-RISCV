// 视频源模型 (相当于电脑 + HDMI 接收芯片) — 仅用于仿真。
// 自己产生 40 MHz 像素时钟, 按 800x600@60 (VESA) 的时序输出 de 和 RGB888 (电脑最低只给 800x600)。
// 画面: 默认是 pattern() 算出的测试图; +vin=<文件> 时改为文件里的 800x600 RGB888 (每像素 3 字节, R G B)。
`timescale 1ns / 1ps
module video_source #(
    parameter W = 800,
    parameter H = 600,
    parameter H_TOTAL = 1056,
    parameter V_TOTAL = 628,
    parameter real HALF_PERIOD = 12.5
) (
    output reg pclk = 0,
    output reg de = 0,
    output reg [23:0] rgb = 0
);
    always #(HALF_PERIOD) pclk = ~pclk;

    reg [23:0] image[0:W*H-1];
    integer from_file = 0;
    integer h = 0, v = 0;
    // 测试台可在帧边界切模式; 文件输入仍按参数 W/H 分配。
    integer active_w = W, active_h = H, active_ht = H_TOTAL, active_vt = V_TOTAL;
    task automatic set_mode(input integer w, input integer height, input integer ht, input integer vt);
        do @(posedge pclk); while (h != 0 || v != 0);
        active_w = w; active_h = height; active_ht = ht; active_vt = vt;
    endtask

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
        de  <= h < active_w && v < active_h;
        rgb <= h < active_w && v < active_h ? (from_file ? image[v*W+h] : pattern(h, v)) : 24'h0;
        h   <= h == active_ht - 1 ? 0 : h + 1;
        if (h == active_ht - 1) v <= v == active_vt - 1 ? 0 : v + 1;
    end
endmodule
