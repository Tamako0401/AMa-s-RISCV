// Y 分桶: 扫一遍 Y 范围表 (一拍一个精灵), 把和逻辑行 line 相交 (top <= line < bottom) 的精灵编号按表的顺序
// 写进对象列表 {line[0], 第几个}; 最多 128 个, 多的丢掉并计数。列表两份按行号奇偶轮换: 渲染读这一行时, 这里写下下一行。
module disp_scan (
    input wire clk,
    input wire rst_n,
    input wire go,
    input wire [8:0] line,
    input wire [9:0] count,  // 精灵表里有几个
    output wire busy,

    output wire [ 8:0] yr_raddr,
    input  wire [25:0] yr_rdata,

    output reg list_we,
    output reg [7:0] list_waddr,
    output reg [8:0] list_wdata,
    output reg [7:0] count0,  // 偶数行的列表有几项
    output reg [7:0] count1,
    output reg dropped  // 丢掉一个 (一拍的脉冲)
);
    reg issuing, got;
    reg [9:0] i, n;
    reg [8:0] got_i, ln;
    reg [7:0] j;
    assign yr_raddr = i[8:0];
    assign busy = issuing || got;

    wire signed [12:0] top = yr_rdata[25:13];
    wire signed [12:0] bottom = yr_rdata[12:0];
    wire signed [12:0] y = {4'b0, ln};
    wire hit = got && top <= y && y < bottom;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issuing <= 0;
            got <= 0;
            list_we <= 0;
            dropped <= 0;
            count0 <= 0;
            count1 <= 0;
        end else begin
            list_we <= 0;
            dropped <= 0;
            if (go) begin
                issuing <= count != 0;
                i <= 0;
                n <= count;
                ln <= line;
                j <= 0;
                if (count == 0) begin
                    if (line[0]) count1 <= 0;
                    else count0 <= 0;
                end
            end else if (issuing) begin
                i <= i + 1'b1;
                if (i == n - 1) issuing <= 0;
            end
            got   <= issuing && !go;
            got_i <= i[8:0];
            if (hit) begin
                if (j[7]) dropped <= 1;
                else begin
                    list_we <= 1;
                    list_waddr <= {ln[0], j[6:0]};
                    list_wdata <= got_i;
                    j <= j + 1'b1;
                end
            end
            // 最后一个看完: 记下这一行的列表长度
            if (got && !issuing) begin
                if (ln[0]) count1 <= hit && !j[7] ? j + 1'b1 : j;
                else count0 <= hit && !j[7] ? j + 1'b1 : j;
            end
        end
    end
endmodule
