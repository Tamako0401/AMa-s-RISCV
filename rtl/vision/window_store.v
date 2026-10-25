// 把像素流存成 W x H 的小图 (RGB332, 每像素 1 字节), 超出部分丢掉; 另一侧按 rclk 读, 给视频输出的小窗用。
// 只发布验证通过的完整帧; 切换缓冲未与显示帧对齐, 小窗仍可能在换帧处撕裂。
module window_store #(
    parameter W  = 160,
    parameter H  = 120,
    parameter AW = $clog2(W * H)
) (
    input wire clk,
    input wire rst_n,
    input wire frame_commit,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    input wire [23:0] in_data,

    input wire rclk,
    input wire [AW-1:0] raddr,  // y * W + x
    output wire [7:0] rdata
);
    reg [AW-1:0] x_r, y_r;
    wire [AW-1:0] x = in_sof ? 0 : x_r;
    wire [AW-1:0] y = in_sof ? 0 : y_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_r <= 0;
            y_r <= 0;
        end else if (in_valid) begin
            x_r <= in_eol ? 0 : x + 1'b1;
            y_r <= in_eol ? y + 1'b1 : y;
        end
    end

    // 双缓冲: 过渡帧只写后台, 验证整帧后才能发布给显示端。
    // 每份拆成 2048x8 的块, 避免 19200 深度补到 32768。
    localparam BLOCKS = (W * H + 2047) / 2048;
    reg back, front, published;
    reg [1:0] front_s, published_s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin back <= 1; front <= 0; published <= 0; end
        else if (frame_commit) begin front <= back; back <= ~back; published <= 1; end
    end
    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) begin front_s <= 0; published_s <= 0; end
        else begin front_s <= {front_s[0], front}; published_s <= {published_s[0], published}; end
    end
    wire [AW-1:0] waddr = y * W + x;
    wire [7:0] q[0:2*BLOCKS-1];
    localparam BW = $clog2(2*BLOCKS);
    reg [BW-1:0] block_q;
    localparam [BW-1:0] BANK_BLOCKS = BLOCKS;
    wire [AW-1:0] block_addr = raddr >> 11;
    wire [BW-1:0] read_block = block_addr[BW-1:0];
    reg valid_q;
    always @(posedge rclk) begin
        block_q <= (front_s[1] ? BANK_BLOCKS : {BW{1'b0}}) + read_block;
        valid_q <= published_s[1] && raddr < W * H;
    end
    assign rdata = valid_q ? q[block_q] : 8'd0;
    genvar n;
    generate for (n = 0; n < 2 * BLOCKS; n = n + 1) begin : g_ram
        dpram2c #(.DW(8), .DP(2048)) u_ram (
            .wclk(clk), .we(in_valid && x < W && y < H && (back ? n >= BLOCKS : n < BLOCKS)
                            && (waddr >> 11) == (n % BLOCKS)),
            .waddr(waddr[10:0]), .wdata({in_data[23:21], in_data[15:13], in_data[7:6]}),
            .rclk(rclk), .raddr(raddr[10:0]), .rdata(q[n])
        );
    end endgenerate
endmodule
