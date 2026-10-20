// 外设子总线: 一个 RIB 从设备口 -> N 个外设口, 按 addr[15:12] 选择, 每个外设 4 KiB.
//
// 上游接 rib 的一个从设备槽位; 下游各口的信号与 rtl/perips/*.v 的总线端口逐位对应.
// 下游信号按口拼接: 第 k 个口占 [k*32 +: 32]、[k*4 +: 4] 或 [k].
//
// 行为:
// - 同一时刻只有一笔访问 (与 rib 一致): 请求握手时记下目标口, 响应按记下的口送回;
// - 外设看到的地址只保留低 12 位 (口内偏移);
// - 访问没有外设的口 (addr[15:12] >= N): 立刻接受, 下一拍返回 0, 写入被丢弃, 不会卡住.
module periph_bus #(
    parameter N = 3  // 外设口个数, 1 ~ 16
) (
    input wire clk,
    input wire rst_n,

    // 上游: 接 rib 的从设备槽位
    input wire [31:0] addr_i,
    input wire [31:0] data_i,
    input wire [3:0] sel_i,
    input wire we_i,
    output wire [31:0] data_o,
    input wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input wire rsp_ready_i,

    // 下游: 接各个外设
    output wire [N*32-1:0] p_addr_o,
    output wire [N*32-1:0] p_data_o,
    output wire [N*4-1:0] p_sel_o,
    output wire [N-1:0] p_we_o,
    output wire [N-1:0] p_req_valid_o,
    input wire [N-1:0] p_req_ready_i,
    input wire [N-1:0] p_rsp_valid_i,
    output wire [N-1:0] p_rsp_ready_o,
    input wire [N*32-1:0] p_data_i
);

    // 未完成访问的状态
    reg        busy;  // 1: 已接受请求, 等待响应被取走
    reg        miss;  // 1: 这笔访问没有命中外设
    reg  [3:0] target;  // 这笔访问的目标口

    wire [3:0] idx = addr_i[15:12];
    wire       hit = idx < N;

    // ---------------- 请求: 只送给 idx 指向的口 ----------------
    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : g_req
            wire sel_k = req_valid_i && !busy && hit && idx == k;
            assign p_addr_o[k*32+:32] = sel_k ? {20'h0, addr_i[11:0]} : 32'h0;
            assign p_data_o[k*32+:32] = sel_k ? data_i : 32'h0;
            assign p_sel_o[k*4+:4]    = sel_k ? sel_i : 4'h0;
            assign p_we_o[k]          = sel_k && we_i;
            assign p_req_valid_o[k]   = sel_k;
        end
    endgenerate

    assign req_ready_o = rst_n && !busy && (hit ? p_req_ready_i[idx] : 1'b1);
    wire req_fire = req_valid_i && req_ready_o;

    // ---------------- 响应: 按记下的目标口送回 ----------------
    assign rsp_valid_o = busy && (miss || p_rsp_valid_i[target]);
    assign data_o = (busy && !miss) ? p_data_i[target*32+:32] : 32'h0;
    generate
        for (k = 0; k < N; k = k + 1) begin : g_rsp
            assign p_rsp_ready_o[k] = busy && !miss && target == k && rsp_ready_i;
        end
    endgenerate
    wire rsp_fire = rsp_valid_o && rsp_ready_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy   <= 1'b0;
            miss   <= 1'b0;
            target <= 4'h0;
        end else if (req_fire) begin
            busy   <= 1'b1;
            miss   <= !hit;
            target <= idx;
        end else if (rsp_fire) begin
            busy <= 1'b0;
        end
    end

endmodule
