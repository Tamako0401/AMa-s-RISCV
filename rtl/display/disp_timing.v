// 720p 扫描计数 (pclk 域, 74.25 MHz): CEA-861 1280x720@60, 一行 1650 个像素时钟, 一帧 750 行。
// 逻辑行 n (640x360) 显示在物理行 2n、2n+1。每两条物理行开头翻转一次 ev_tgl, 同时给出 ev_pair = v / 2;
// 渲染端 (clk 域) 同步 ev_tgl 看到翻转时再读 ev_pair, 这时它已经稳定 (两次翻转之间隔 3300 个像素时钟)。
module disp_timing (
    input wire pclk,
    input wire rst_n,
    output reg [10:0] h,
    output reg [9:0] v,
    output reg ev_tgl,
    output reg [8:0] ev_pair
);
    localparam H_TOTAL = 1650, V_TOTAL = 750;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            h <= 0;
            v <= 0;
            ev_tgl <= 0;
            ev_pair <= 0;
        end else begin
            h <= h == H_TOTAL - 1 ? 11'd0 : h + 1'b1;
            if (h == H_TOTAL - 1) v <= v == V_TOTAL - 1 ? 10'd0 : v + 1'b1;
            if (h == 0 && !v[0]) begin
                ev_tgl  <= !ev_tgl;
                ev_pair <= v[9:1];
            end
        end
    end
endmodule
