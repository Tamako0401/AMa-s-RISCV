// 视频接收端模型 (相当于 HDMI 发送芯片 + 显示器) — 仅用于仿真。
// 在 pclk 上升沿采样, de 有效的像素依次填进 fb; de 每结束一次换一行, 场同步开始时换一帧。
// +video=<文件>: 每帧结束把画面按 RGB565 小端写进文件 (sim/view.py 读它)。
`timescale 1ns / 1ps
module video_sink #(
    parameter W = 640,
    parameter H = 480
) (
    input wire pclk,
    input wire hsync_n,
    input wire vsync_n,
    input wire de,
    input wire [23:0] rgb
);
    reg [23:0] fb[0:W*H-1];
    integer x = 0, y = 0;
    integer frames = 0;  // 收完的帧数
    integer bad_lines = 0;  // 宽度不是 W 的行
    reg de_q = 0, vsync_q = 1;

    string path;
    integer enabled;
    initial enabled = $value$plusargs("video=%s", path);

    task static write_frame;
        integer fd, i;
        reg [23:0] p;
        begin
            fd = $fopen(path, "wb");
            for (i = 0; i < W * H; i = i + 1) begin
                p = fb[i];
                $fwrite(fd, "%c%c", {p[12:10], p[7:3]}, {p[23:19], p[15:13]});
            end
            $fclose(fd);
        end
    endtask

    always @(posedge pclk) begin
        if (!vsync_n && vsync_q) begin
            frames = frames + 1;
            if (enabled) write_frame();
            y = 0;
        end
        vsync_q <= vsync_n;
        if (de) begin
            if (x < W && y < H) fb[y*W+x] = rgb;
            x = x + 1;
        end else if (de_q) begin
            if (x != W) bad_lines = bad_lines + 1;
            x = 0;
            y = y + 1;
        end
        de_q <= de;
    end
endmodule
