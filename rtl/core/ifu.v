// Imported from JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G
// Source commit: 00a3334d7c98f57a6d429a5e18910a7e2e88390b
// Local changes: see third_party/tinyriscv-manifest.json and docs/cpu-baseline.md.
/*
 Copyright 2020 Blue Liang, liangkangnan@163.com

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

`include "defines.v"

// 取指模块
//
// 预取队列 + 代际(epoch)丢弃，替代原来的 4 状态单笔事务状态机：
//   1. 取指地址自由前进：只要队列还有空间就连续发请求，不等下游把上一条取走；
//   2. PC 跟着指令走：每个请求在标签队列里记下 {epoch, pc}，响应按序配对，
//      交付出去的 (pc, inst) 永远来自同一次取指；
//   3. 重定向不排空：flush 只做 epoch+1、PC 改成目标地址、清空指令队列；
//      在途请求的响应照常接收，epoch 不匹配就丢弃，不需要等总线事务结束。
//
// 总线协议不变：req_valid 拉高后保持到 req_ready 握手，期间地址不变；每次只允许
// 一笔请求处于"已拉高未握手"状态。响应通道恒就绪，否则总线事务永远无法结束。
//
// RESET_PC 默认 = 哈佛式指令存储器(ROM)基址 0x0000_0000, 见 docs/cpu-baseline.md。
// FETCH_DEPTH 必须是 2 的幂。
//
// STALL_WINDOW: 流水线停顿时允许的预取窗口。soc_top 的取指已走 ROM 专用口,
// 不再和访存抢总线, 这个上限在当前 SoC 上不影响结果; 如果取指和数据共用一条
// 单笔事务总线, 把它调小(例如 2)可以避免取指把访存挤在总线外。
module ifu #(
    parameter [31:0] RESET_PC = 32'h00000000,
    parameter FETCH_DEPTH = 4,
    parameter STALL_WINDOW = 2
) (

    input wire clk,
    input wire rst_n,

    input wire                    flush_i,
    input wire [            31:0] flush_addr_i,  // 跳转地址
    input wire [`STALL_WIDTH-1:0] stall_i,       // 流水线暂停标志
    input wire                    jtag_halt_i,

    output wire [31:0] inst_o,
    output wire [31:0] pc_o,
    output wire inst_valid_o,
    output wire        pred_taken_o,  // 本条指令取指时 BTB 是否预测跳转

    // BTB 查表: 用 fetch_pc 查, 命中且预测跳转时下一笔直接从目标取
    output wire [31:0] btb_pc_o,
    input  wire        btb_taken_i,
    input  wire [31:0] btb_target_i,

    output wire [31:0] ibus_addr_o,
    input wire [31:0] ibus_data_i,
    output wire [31:0] ibus_data_o,
    output wire [3:0] ibus_sel_o,
    output wire ibus_we_o,
    output wire req_valid_o,
    input wire req_ready_i,
    input wire rsp_valid_i,
    output wire rsp_ready_o

);

    localparam AW = $clog2(FETCH_DEPTH);  // 队列存储索引位宽
    localparam PTRW = AW + 1;             // 指针多一位，用来区分满和空
    localparam EW = 8;                    // epoch 位宽，够覆盖任何在途事务的生命期

    // 指令队列: 每项 {pred_taken, pc, inst}
    reg [64:0] inst_mem[0:FETCH_DEPTH-1];
    reg [PTRW-1:0] inst_wptr, inst_rptr;

    // 在途请求标签: 每项 {epoch, pred_taken, pc}
    reg [EW+32:0] tag_mem[0:FETCH_DEPTH-1];
    reg [PTRW-1:0] tag_wptr, tag_rptr;

    // 取指地址与代际
    reg [31:0] fetch_pc;
    reg [EW-1:0] epoch;

    // 已经拉高 req_valid、还没被总线接受的请求
    reg req_pending;
    reg [31:0] req_addr;
    reg [EW-1:0] req_epoch;
    reg req_pred_taken;

    wire [PTRW-1:0] inst_cnt = inst_wptr - inst_rptr;
    wire [PTRW-1:0] tag_cnt = tag_wptr - tag_rptr;
    wire inst_empty = (inst_cnt == {PTRW{1'b0}});
    wire tag_empty = (tag_cnt == {PTRW{1'b0}});

    // 已经进入取指通路的指令总数: 队列里 + 在途标签 + 正在握手的请求
    wire [PTRW:0] inflight = {1'b0, inst_cnt} + {1'b0, tag_cnt} + {{PTRW{1'b0}}, req_pending};

    // 队列还有余量就一直取；重定向和 jtag 暂停期间不发起新请求。
    // 流水线停顿时没有指令被消费，把窗口压到 STALL_WINDOW，避免取指把访存挤在总线外。
    localparam [PTRW:0] DEPTH_LIM = FETCH_DEPTH;
    localparam [PTRW:0] STALL_LIM = STALL_WINDOW;
    wire [PTRW:0] issue_limit = stall_i[`STALL_ID] ? STALL_LIM : DEPTH_LIM;
    wire can_issue = rst_n && !jtag_halt_i && (inflight < issue_limit);
    wire issue_start = can_issue && !req_pending && !flush_i;
    wire issue_fire = req_pending && req_ready_i;
    wire issue_next = can_issue && !flush_i;  // 与 issue_fire 同拍启动下一笔

    // 重定向当拍就发目标地址的请求, 省掉一拍。指令队列在 flush 那一拍被清空,
    // 所以容量只看在途标签; 这样队列满时也能立刻发出目标地址。
    wire [PTRW:0] refill_inflight = {1'b0, tag_cnt} + {{PTRW{1'b0}}, req_pending};
    wire can_issue_redirect = rst_n && !jtag_halt_i && (refill_inflight < DEPTH_LIM);
    // 旧请求还没握手就先让它走完, 下一拍再发目标
    wire redirect_now = flush_i && can_issue_redirect && (!req_pending || req_ready_i);

    assign req_valid_o = rst_n && req_pending;
    assign rsp_ready_o = rst_n;  // 永远接收，避免总线事务悬挂
    assign ibus_addr_o = req_pending ? req_addr : fetch_pc;
    assign ibus_data_o = 32'b0;
    assign ibus_sel_o = 4'b1111;
    assign ibus_we_o = 1'b0;

    // 响应按发出顺序配对；epoch 不匹配说明这笔取指在重定向之前，直接丢弃
    wire [EW+32:0] tag_head = tag_mem[tag_rptr[AW-1:0]];
    wire rsp_take = rst_n && rsp_valid_i && !tag_empty;
    wire rsp_match = rsp_take && (tag_head[EW+32:33] == epoch);

    // 队列空且下游这一拍就要拿走时, 直接旁路响应, 省掉"写队列再读出"的一拍。
    // 停顿时下游拿不走, 必须先存进队列, 否则这条指令会丢。
    wire fifo_bypass = rsp_match && inst_empty && !stall_i[`STALL_ID];
    wire [64:0] inst_head = fifo_bypass ? {tag_head[32], tag_head[31:0], ibus_data_i}
                                        : inst_mem[inst_rptr[AW-1:0]];

    assign inst_valid_o = rst_n && !flush_i && !jtag_halt_i && (fifo_bypass || !inst_empty);
    assign inst_o = inst_valid_o ? inst_head[31:0] : `INST_NOP;
    assign pc_o = inst_valid_o ? inst_head[63:32] : fetch_pc;
    assign pred_taken_o = inst_valid_o && inst_head[64];

    // ifu_idu 在 !stall[ID] 或 flush 时锁存；flush 那一拍指令已被丢弃, 不用出队
    wire inst_pop = inst_valid_o && !stall_i[`STALL_ID] && !fifo_bypass;
    // 旁路的那条不进队列, 否则会重复交付
    wire inst_push = rsp_match && !fifo_bypass;

    // 指令队列
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_wptr <= {PTRW{1'b0}};
            inst_rptr <= {PTRW{1'b0}};
        end else if (flush_i) begin
            // 丢弃错误路径上已经取回的指令；标签队列不动，等在途响应回来被 epoch 丢掉
            inst_wptr <= {PTRW{1'b0}};
            inst_rptr <= {PTRW{1'b0}};
        end else begin
            if (inst_push) begin
                inst_mem[inst_wptr[AW-1:0]] <= {tag_head[32], tag_head[31:0], ibus_data_i};
                inst_wptr <= inst_wptr + 1'b1;
            end
            if (inst_pop) inst_rptr <= inst_rptr + 1'b1;
        end
    end

    // 标签队列: 记下请求发出时的 PC 和代际
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_wptr <= {PTRW{1'b0}};
            tag_rptr <= {PTRW{1'b0}};
        end else begin
            if (issue_fire) begin
                tag_mem[tag_wptr[AW-1:0]] <= {req_epoch, req_pred_taken, req_addr};
                tag_wptr <= tag_wptr + 1'b1;
            end
            if (rsp_take) tag_rptr <= tag_rptr + 1'b1;
        end
    end

    // 取指地址: 只在真正发出一笔新请求时前进；重定向时跳到目标地址
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_pc <= RESET_PC;
            epoch    <= {EW{1'b0}};
        end else if (flush_i) begin
            // 目标地址当拍已发出请求时, fetch_pc 指向下一条
            fetch_pc <= redirect_now ? (flush_addr_i + 32'd4) : flush_addr_i;
            epoch    <= epoch + 1'b1;
        end else if (issue_start || (issue_fire && issue_next)) begin
            // BTB 预测跳转时下一笔直接从目标取, 否则顺序 +4
            fetch_pc <= btb_taken_i ? btb_target_i : (fetch_pc + 32'd4);
        end
    end

    // 请求寄存: 拉高后保持到握手，期间地址不变；同拍可以接着发下一笔
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_pending    <= 1'b0;
            req_addr       <= RESET_PC;
            req_epoch      <= {EW{1'b0}};
            req_pred_taken <= 1'b0;
        end else if (redirect_now) begin
            req_pending    <= 1'b1;
            req_addr       <= flush_addr_i;
            req_epoch      <= epoch + 1'b1;
            req_pred_taken <= 1'b0;  // 重定向是确定路径, 不用预测
        end else if (issue_fire) begin
            if (issue_next) begin
                req_pending    <= 1'b1;
                req_addr       <= fetch_pc;
                req_epoch      <= epoch;
                req_pred_taken <= btb_taken_i;
            end else begin
                req_pending <= 1'b0;
            end
        end else if (issue_start) begin
            req_pending    <= 1'b1;
            req_addr       <= fetch_pc;
            req_epoch      <= epoch;
            req_pred_taken <= btb_taken_i;
        end
    end

    assign btb_pc_o = fetch_pc;

endmodule
