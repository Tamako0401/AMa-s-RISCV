// Imported from JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G
// Source commit: 00a3334d7c98f57a6d429a5e18910a7e2e88390b
// Local changes: see third_party/tinyriscv-manifest.json and docs/cpu-baseline.md.
/*
 Copyright 2019 Blue Liang, liangkangnan@163.com

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

// tinyriscv处理器核顶层模块
// RESET_PC 默认 = 哈佛式指令存储器(ROM)基址 0x0000_0000, 见 docs/cpu-baseline.md。
module tinyriscv_core #(
    parameter [31:0] RESET_PC = 32'h00000000
) (

    input wire clk,
    input wire rst_n,

    output wire [31:0] dbus_addr_o,
    input wire [31:0] dbus_data_i,
    output wire [31:0] dbus_data_o,
    output wire [3:0] dbus_sel_o,
    output wire dbus_we_o,
    output wire dbus_req_valid_o,
    input wire dbus_req_ready_i,
    input wire dbus_rsp_valid_i,
    output wire dbus_rsp_ready_o,

    output wire [31:0] ibus_addr_o,       // 取指地址
    input  wire [31:0] ibus_data_i,       // 取到的指令内容
    output wire [31:0] ibus_data_o,
    output wire [ 3:0] ibus_sel_o,
    output wire        ibus_we_o,
    output wire        ibus_req_valid_o,
    input  wire        ibus_req_ready_i,
    input  wire        ibus_rsp_valid_i,
    output wire        ibus_rsp_ready_o,

    input wire                  jtag_halt_i,
    input wire [`INT_WIDTH-1:0] int_i         // 中断输入信号

);

    // ifu模块输出信号
    wire [31:0] ifetch_inst_o;
    wire [31:0] ifetch_pc_o;
    wire ifetch_inst_valid_o;
    wire ifetch_pred_taken_o;
    wire [31:0] ifetch_pred_target_o;

    // BTB: 取指查表 + EX 训练
    wire [31:0] btb_lookup_pc, btb_lookup_target, btb_upd_pc, btb_upd_target;
    wire btb_lookup_taken, btb_upd_en, btb_upd_taken;
    wire [1:0] btb_lookup_kind, btb_upd_kind;
    wire btb_use;
    wire if_pred_taken_o;
    wire [31:0] if_pred_target_o;

    // RAS: 取指投机压栈/弹栈, EX 提交
    wire [31:0] ras_top, ras_cmt_addr;
    wire ras_cmt_push, ras_cmt_pop;
    wire btb_is_ret = (btb_lookup_kind == `BTB_KIND_RET);
    // ret 的预测目标取 RAS 栈顶, 其它取 BTB 记下的目标
    wire [31:0] pred_target = btb_is_ret ? ras_top : btb_lookup_target;

    // ifu_idu模块输出信号
    wire [31:0] if_inst_o;
    wire [31:0] if_inst_addr_o;
    wire [`INT_WIDTH-1:0] if_int_flag_o;

    // idu模块输出信号
    wire [31:0] id_inst_o;
    wire [31:0] id_inst_addr_o;
    wire [`DECINFO_WIDTH-1:0] id_dec_info_bus_o;
    wire [31:0] id_dec_imm_o;
    wire [31:0] id_dec_pc_o;
    wire [4:0] id_rs1_raddr_o;
    wire [4:0] id_rs2_raddr_o;
    wire [4:0] id_rd_waddr_o;
    wire id_rd_we_o;
    wire id_stall_o;
    wire [31:0] id_rs1_rdata_o;
    wire [31:0] id_rs2_rdata_o;

    // idu_exu模块输出信号
    wire [31:0] ie_inst_o;
    wire [31:0] ie_inst_addr_o;
    wire [`DECINFO_WIDTH-1:0] ie_dec_info_bus_o;
    wire [31:0] ie_dec_imm_o;
    wire [31:0] ie_dec_pc_o;
    wire [31:0] ie_rs1_rdata_o;
    wire [31:0] ie_rs2_rdata_o;
    wire [4:0] ie_rd_waddr_o;
    wire ie_rd_we_o;
    wire ie_pred_taken_o;
    wire [31:0] ie_pred_rs1_o;

    // exu模块输出信号
    wire [31:0] ex_mem_wdata_o;
    wire [31:0] ex_mem_addr_o;
    wire ex_mem_we_o;
    wire [3:0] ex_mem_sel_o;
    wire ex_mem_req_valid_o;
    wire ex_mem_rsp_ready_o;
    wire ex_mem_access_misaligned_o;
    wire [31:0] ex_reg_wdata_o;
    wire ex_reg_we_o;
    wire [4:0] ex_reg_waddr_o;
    wire ex_hold_flag_o;
    wire ex_mem_stall_o;
    wire ex_load_we;
    wire [4:0] ex_load_waddr;
    wire [31:0] ex_load_wdata;
    wire [4:0] ex_load_ex_rd;
    wire [4:0] ex_load_wait_rd;
    wire ex_jump_flag_o;
    wire [31:0] ex_jump_addr_o;
    wire [31:0] ex_csr_wdata_o;
    wire ex_csr_we_o;
    wire [31:0] ex_csr_waddr_o;
    wire [31:0] ex_csr_raddr_o;
    wire ex_inst_ecall_o;
    wire ex_inst_ebreak_o;
    wire ex_inst_mret_o;

    // gpr_reg模块输出信号
    wire [31:0] regs_rdata1_o;
    wire [31:0] regs_rdata2_o;

    // csr_reg模块输出信号
    wire [31:0] csr_ex_data_o;
    wire [31:0] csr_clint_data_o;
    wire [31:0] csr_mtvec_o;
    wire [31:0] csr_mepc_o;
    wire [31:0] csr_mstatus_o;

    // pipe_ctrl模块输出信号
    wire [31:0] ctrl_flush_addr_o;
    wire ctrl_flush_o;
    wire [`STALL_WIDTH-1:0] ctrl_stall_o;

    // clint模块输出信号
    wire clint_csr_we_o;
    wire [31:0] clint_csr_waddr_o;
    wire [31:0] clint_csr_wdata_o;
    wire clint_stall_flag_o;
    wire [31:0] clint_int_addr_o;
    wire clint_int_assert_o;

    assign dbus_addr_o = ex_mem_addr_o;
    assign dbus_data_o = ex_mem_wdata_o;
    assign dbus_we_o = ex_mem_we_o;
    assign dbus_sel_o = ex_mem_sel_o;
    assign dbus_req_valid_o = ex_mem_req_valid_o;
    assign dbus_rsp_ready_o = ex_mem_rsp_ready_o;


    ifu #(
        .RESET_PC(RESET_PC)
    ) u_ifu (
        .clk(clk),
        .rst_n(rst_n),
        .flush_addr_i(ctrl_flush_addr_o),
        .stall_i(ctrl_stall_o),
        .flush_i(ctrl_flush_o),
        .jtag_halt_i(jtag_halt_i),
        .inst_o(ifetch_inst_o),
        .pc_o(ifetch_pc_o),
        .inst_valid_o(ifetch_inst_valid_o),
        .pred_taken_o(ifetch_pred_taken_o),
        .pred_target_o(ifetch_pred_target_o),
        .btb_pc_o(btb_lookup_pc),
        .btb_taken_i(btb_lookup_taken),
        .btb_target_i(pred_target),
        .btb_use_o(btb_use),
        .ibus_addr_o(ibus_addr_o),
        .ibus_data_i(ibus_data_i),
        .ibus_data_o(ibus_data_o),
        .ibus_sel_o(ibus_sel_o),
        .ibus_we_o(ibus_we_o),
        .req_valid_o(ibus_req_valid_o),
        .req_ready_i(ibus_req_ready_i),
        .rsp_valid_i(ibus_rsp_valid_i),
        .rsp_ready_o(ibus_rsp_ready_o)
    );

    btb #(
        .ENTRIES(128),
        .IDX_W(7)
    ) u_btb (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_pc(btb_lookup_pc),
        .lookup_taken(btb_lookup_taken),
        .lookup_target(btb_lookup_target),
        .lookup_kind(btb_lookup_kind),
        .upd_en(btb_upd_en),
        .upd_pc(btb_upd_pc),
        .upd_target(btb_upd_target),
        .upd_taken(btb_upd_taken),
        .upd_kind(btb_upd_kind)
    );

    wire btb_pred_use = btb_use && btb_lookup_taken;

    ras #(
        .DEPTH(4),
        .AW(2)
    ) u_ras (
        .clk(clk),
        .rst_n(rst_n),
        .flush_i(ctrl_flush_o),
        .spec_push_i(btb_pred_use && (btb_lookup_kind == `BTB_KIND_CALL)),
        .spec_pop_i(btb_pred_use && btb_is_ret),
        .spec_addr_i(btb_lookup_pc + 32'd4),
        .top_o(ras_top),
        .cmt_push_i(ras_cmt_push),
        .cmt_pop_i(ras_cmt_pop),
        .cmt_addr_i(ras_cmt_addr)
    );

    // load 的结果在请求之后才写回 (见 exu_mem): 译码级的指令要读或写一个还没写回的 load 目的寄存器时,
    // 留在 ID 一拍 (EX 收到气泡)。写也要等, 否则 load 晚到的写回会盖掉它。冲刷时 ID 里的指令作废, 不用等。
    // 响应到的那一拍不用停: 寄存器堆读口旁路第二个写口。
    function automatic load_hit(input [4:0] r, input [4:0] rs1, input [4:0] rs2, input [4:0] rd);
        load_hit = (r != 5'd0) && (r == rs1 || r == rs2 || r == rd);
    endfunction
    wire load_use_stall = !ctrl_flush_o &&
        (load_hit(ex_load_ex_rd, id_rs1_raddr_o, id_rs2_raddr_o, id_rd_waddr_o) ||
         load_hit(ex_load_wait_rd, id_rs1_raddr_o, id_rs2_raddr_o, id_rd_waddr_o));

    pipe_ctrl u_pipe_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .stall_from_id_i(id_stall_o | load_use_stall),
        .stall_from_ex_i(ex_hold_flag_o),
        .stall_from_jtag_i(1'b0),
        .stall_from_clint_i(clint_stall_flag_o),
        .jump_assert_i(ex_jump_flag_o),
        .jump_addr_i(ex_jump_addr_o),
        .flush_o(ctrl_flush_o),
        .stall_o(ctrl_stall_o),
        .flush_addr_o(ctrl_flush_addr_o)
    );

    gpr_reg u_gpr_reg (
        .clk(clk),
        .rst_n(rst_n),
        .we_i(ex_reg_we_o),
        .waddr_i(ex_reg_waddr_o),
        .wdata_i(ex_reg_wdata_o),
        .load_we_i(ex_load_we),
        .load_waddr_i(ex_load_waddr),
        .load_wdata_i(ex_load_wdata),
        .raddr1_i(id_rs1_raddr_o),
        .rdata1_o(regs_rdata1_o),
        .raddr2_i(id_rs2_raddr_o),
        .rdata2_o(regs_rdata2_o)
    );

    csr_reg u_csr_reg (
        .clk(clk),
        .rst_n(rst_n),
        .exu_we_i(ex_csr_we_o),
        .exu_raddr_i(ex_csr_raddr_o),
        .exu_waddr_i(ex_csr_waddr_o),
        .exu_wdata_i(ex_csr_wdata_o),
        .exu_rdata_o(csr_ex_data_o),
        .clint_we_i(clint_csr_we_o),
        .clint_waddr_i(clint_csr_waddr_o),
        .clint_wdata_i(clint_csr_wdata_o),
        .mtvec_o(csr_mtvec_o),
        .mepc_o(csr_mepc_o),
        .mstatus_o(csr_mstatus_o)
    );

    ifu_idu u_ifu_idu (
        .clk(clk),
        .rst_n(rst_n),
        .inst_i(ifetch_inst_o),
        .inst_addr_i(ifetch_pc_o),
        .stall_i(ctrl_stall_o),
        .flush_i(ctrl_flush_o),
        .inst_valid_i(ifetch_inst_valid_o),
        .pred_taken_i(ifetch_pred_taken_o),
        .pred_target_i(ifetch_pred_target_o),
        .inst_o(if_inst_o),
        .inst_addr_o(if_inst_addr_o),
        .pred_taken_o(if_pred_taken_o),
        .pred_target_o(if_pred_target_o)
    );

    idu u_idu (
        .clk(clk),
        .rst_n(rst_n),
        .inst_i(if_inst_o),
        .rs1_rdata_i(regs_rdata1_o),
        .rs2_rdata_i(regs_rdata2_o),
        .inst_o(id_inst_o),
        .inst_addr_i(if_inst_addr_o),
        .rs1_rdata_o(id_rs1_rdata_o),
        .rs2_rdata_o(id_rs2_rdata_o),
        .stall_o(id_stall_o),
        .dec_info_bus_o(id_dec_info_bus_o),
        .dec_imm_o(id_dec_imm_o),
        .dec_pc_o(id_dec_pc_o),
        .rs1_raddr_o(id_rs1_raddr_o),
        .rs2_raddr_o(id_rs2_raddr_o),
        .rd_waddr_o(id_rd_waddr_o),
        .rd_we_o(id_rd_we_o)
    );

    idu_exu u_idu_exu (
        .clk(clk),
        .rst_n(rst_n),
        .inst_i(id_inst_o),
        .stall_i(ctrl_stall_o),
        .flush_i(ctrl_flush_o),
        .dec_info_bus_i(id_dec_info_bus_o),
        .dec_imm_i(id_dec_imm_o),
        .dec_pc_i(id_dec_pc_o),
        .rs1_rdata_i(id_rs1_rdata_o),
        .rs2_rdata_i(id_rs2_rdata_o),
        .rd_waddr_i(id_rd_waddr_o),
        .rd_we_i(id_rd_we_o),
        .pred_taken_i(if_pred_taken_o),
        // jalr 要对上的 rs1, 在 ID 先减掉 imm, EX 核对时就不用经过加法器
        .pred_rs1_i(if_pred_target_o - id_dec_imm_o),
        .inst_o(ie_inst_o),
        .dec_info_bus_o(ie_dec_info_bus_o),
        .dec_imm_o(ie_dec_imm_o),
        .dec_pc_o(ie_dec_pc_o),
        .rs1_rdata_o(ie_rs1_rdata_o),
        .rs2_rdata_o(ie_rs2_rdata_o),
        .rd_waddr_o(ie_rd_waddr_o),
        .rd_we_o(ie_rd_we_o),
        .pred_taken_o(ie_pred_taken_o),
        .pred_rs1_o(ie_pred_rs1_o)
    );

    exu u_exu (
        .clk(clk),
        .rst_n(rst_n),
        .reg1_rdata_i(ie_rs1_rdata_o),
        .reg2_rdata_i(ie_rs2_rdata_o),
        .mem_rdata_i(dbus_data_i),
        .mem_req_ready_i(dbus_req_ready_i),
        .mem_rsp_valid_i(dbus_rsp_valid_i),
        .mem_wdata_o(ex_mem_wdata_o),
        .mem_addr_o(ex_mem_addr_o),
        .mem_we_o(ex_mem_we_o),
        .mem_sel_o(ex_mem_sel_o),
        .mem_req_valid_o(ex_mem_req_valid_o),
        .mem_rsp_ready_o(ex_mem_rsp_ready_o),
        .mem_access_misaligned_o(ex_mem_access_misaligned_o),
        .reg_wdata_o(ex_reg_wdata_o),
        .reg_we_o(ex_reg_we_o),
        .reg_waddr_o(ex_reg_waddr_o),
        .load_we_o(ex_load_we),
        .load_waddr_o(ex_load_waddr),
        .load_wdata_o(ex_load_wdata),
        .load_ex_rd_o(ex_load_ex_rd),
        .load_wait_rd_o(ex_load_wait_rd),
        .hold_flag_o(ex_hold_flag_o),
        .mem_stall_o(ex_mem_stall_o),
        .jump_flag_o(ex_jump_flag_o),
        .jump_addr_o(ex_jump_addr_o),
        .btb_upd_en_o(btb_upd_en),
        .btb_upd_pc_o(btb_upd_pc),
        .btb_upd_target_o(btb_upd_target),
        .btb_upd_taken_o(btb_upd_taken),
        .btb_upd_kind_o(btb_upd_kind),
        .ras_push_o(ras_cmt_push),
        .ras_pop_o(ras_cmt_pop),
        .ras_addr_o(ras_cmt_addr),
        .rs1_raddr_i(ie_inst_o[19:15]),
        .pred_taken_i(ie_pred_taken_o),
        .pred_rs1_i(ie_pred_rs1_o),
        .int_assert_i(clint_int_assert_o),
        .int_addr_i(clint_int_addr_o),
        .inst_ecall_o(ex_inst_ecall_o),
        .inst_ebreak_o(ex_inst_ebreak_o),
        .inst_mret_o(ex_inst_mret_o),
        .int_stall_i(clint_stall_flag_o),
        .csr_raddr_o(ex_csr_raddr_o),
        .csr_rdata_i(csr_ex_data_o),
        .csr_wdata_o(ex_csr_wdata_o),
        .csr_we_o(ex_csr_we_o),
        .csr_waddr_o(ex_csr_waddr_o),
        .dec_info_bus_i(ie_dec_info_bus_o),
        .dec_imm_i(ie_dec_imm_o),
        .dec_pc_i(ie_dec_pc_o),
        .next_pc_i(ie_dec_pc_o + 32'd4),
        .rd_waddr_i(ie_rd_waddr_o),
        .rd_we_i(ie_rd_we_o)
    );

    clint u_clint (
        .clk(clk),
        .rst_n(rst_n),
        .int_flag_i(int_i),
        .inst_ecall_i(ex_inst_ecall_o),
        .inst_ebreak_i(ex_inst_ebreak_o),
        .inst_mret_i(ex_inst_mret_o),
        .inst_addr_i(ie_dec_pc_o),
        .jump_flag_i(ex_jump_flag_o),
        .mem_access_misaligned_i(ex_mem_access_misaligned_o),
        .csr_mtvec_i(csr_mtvec_o),
        .csr_mepc_i(csr_mepc_o),
        .csr_mstatus_i(csr_mstatus_o),
        .csr_we_o(clint_csr_we_o),
        .csr_waddr_o(clint_csr_waddr_o),
        .csr_wdata_o(clint_csr_wdata_o),
        .stall_flag_o(clint_stall_flag_o),
        .int_addr_o(clint_int_addr_o),
        .int_assert_o(clint_int_assert_o)
    );

    // 上板 ILA (PDS Fabric Debugger) 的探针: 综合会把下面这些信号改名或并掉, 打一拍寄存并加保留属性,
    // 让 Inserter 里能按 ila_ 前缀找到。全部晚一拍, 彼此对齐; 和 tests/soc/coremark_perf_tb.sv 的探针一一对应。
    /* verilator lint_off UNUSEDSIGNAL */
    (* syn_keep = 1, syn_preserve = 1, syn_noprune = 1 *) reg ila_flush, ila_load_use, ila_hold, ila_mem_stall;
    (* syn_keep = 1, syn_preserve = 1, syn_noprune = 1 *) reg ila_if_valid, ila_dreq, ila_drsp;
    (* syn_keep = 1, syn_preserve = 1, syn_noprune = 1 *) reg [15:0] ila_if_pc, ila_ex_pc;
    always @(posedge clk) begin
        ila_flush <= ctrl_flush_o;
        ila_load_use <= load_use_stall;
        ila_hold <= ex_hold_flag_o;
        ila_mem_stall <= ex_mem_stall_o;
        ila_if_valid <= ifetch_inst_valid_o;
        ila_dreq <= dbus_req_valid_o & dbus_req_ready_i;
        ila_drsp <= dbus_rsp_valid_i;
        ila_if_pc <= ifetch_pc_o[15:0];
        ila_ex_pc <= ie_dec_pc_o[15:0];
    end
    // Fabric Inserter 不列出没有负载的网: 全部异或进一个保留的汇点寄存器, 让每根探针都有负载
    (* syn_keep = 1, syn_preserve = 1, syn_noprune = 1 *) reg ila_sink;
    always @(posedge clk)
        ila_sink <= ^{ila_flush, ila_load_use, ila_hold, ila_mem_stall, ila_if_valid, ila_dreq, ila_drsp, ila_if_pc, ila_ex_pc};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
