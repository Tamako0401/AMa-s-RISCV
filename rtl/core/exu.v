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

// 执行模块
// 纯组合逻辑电路
module exu (

    input wire clk,
    input wire rst_n,

    // clint
    input  wire        int_assert_i,   // 中断发生标志
    input  wire [31:0] int_addr_i,     // 中断跳转地址
    input  wire        int_stall_i,    // 暂停标志
    output wire        inst_ecall_o,   // ecall指令
    output wire        inst_ebreak_o,  // ebreak指令
    output wire        inst_mret_o,    // mret指令

    // mem
    input  wire [31:0] mem_rdata_i,             // 内存输入数据
    input  wire        mem_req_ready_i,
    input  wire        mem_rsp_valid_i,
    output wire [31:0] mem_wdata_o,             // 写内存数据
    output wire [31:0] mem_addr_o,              // 读、写内存地址
    output wire        mem_we_o,                // 是否要写内存
    output wire [ 3:0] mem_sel_o,               // 字节位
    output wire        mem_req_valid_o,
    output wire        mem_rsp_ready_o,
    output wire        mem_access_misaligned_o,

    // gpr_reg
    output wire [31:0] reg_wdata_o,  // 写寄存器数据
    output wire        reg_we_o,     // 是否要写通用寄存器
    output wire [ 4:0] reg_waddr_o,  // 写通用寄存器地址
    // load 结果晚一拍写回 (寄存器堆第二个写口) 和译码级要避开的目的寄存器, 见 exu_mem
    output wire        load_we_o,
    output wire [ 4:0] load_waddr_o,
    output wire [31:0] load_wdata_o,
    output wire [ 4:0] load_ex_rd_o,
    output wire [ 4:0] load_wait_rd_o,

    // csr_reg
    input  wire [31:0] csr_rdata_i,
    output wire [31:0] csr_raddr_o,  // 读CSR寄存器地址
    output wire [31:0] csr_wdata_o,  // 写CSR寄存器数据
    output wire        csr_we_o,     // 是否要写CSR寄存器
    output wire [31:0] csr_waddr_o,  // 写CSR寄存器地址

    // to pipe_ctrl
    output wire        hold_flag_o,  // 是否暂停标志
    output wire        jump_flag_o,  // 是否重定向(预测错或必须冲刷)
    output wire [31:0] jump_addr_o,  // 重定向目标地址

    // BTB 更新: 分支/jal 解析时把结果写回
    output wire        btb_upd_en_o,
    output wire [31:0] btb_upd_pc_o,
    output wire [31:0] btb_upd_target_o,
    output wire        btb_upd_taken_o,
    output wire [ 1:0] btb_upd_kind_o,

    // RAS 提交栈: 执行到调用时压入返回地址, 执行到返回时弹出
    output wire        ras_push_o,
    output wire        ras_pop_o,
    output wire [31:0] ras_addr_o,

    // from idu_exu
    input wire [`DECINFO_WIDTH-1:0] dec_info_bus_i,
    input wire [              31:0] dec_imm_i,
    input wire [              31:0] dec_pc_i,
    input wire [              31:0] next_pc_i,
    input wire [               4:0] rd_waddr_i,
    input wire [              31:0] reg1_rdata_i,    // 通用寄存器1输入数据
    input wire [              31:0] reg2_rdata_i,    // 通用寄存器2输入数据
    input wire                      rd_we_i,
    input wire [               4:0] rs1_raddr_i,
    input wire                      pred_taken_i,  // 取指时 BTB 是否预测跳转
    input wire [              31:0] pred_rs1_i  // 预测的 jalr 要对上的 rs1 (= 预测目标 - imm, ID 算好)

);

    // dispatch to ALU
    wire [31:0] alu_op1_o;
    wire [31:0] alu_op2_o;
    wire req_alu_o;
    wire alu_op_lui_o;
    wire alu_op_auipc_o;
    wire alu_op_add_o;
    wire alu_op_sub_o;
    wire alu_op_sll_o;
    wire alu_op_slt_o;
    wire alu_op_sltu_o;
    wire alu_op_xor_o;
    wire alu_op_srl_o;
    wire alu_op_sra_o;
    wire alu_op_or_o;
    wire alu_op_and_o;
    // dispatch to BJP
    wire [31:0] bjp_jump_op1_o;
    wire [31:0] bjp_jump_op2_o;
    wire req_bjp_o;
    wire bjp_op_jump_o;
    wire bjp_op_beq_o;
    wire bjp_op_bne_o;
    wire bjp_op_blt_o;
    wire bjp_op_bltu_o;
    wire bjp_op_bge_o;
    wire bjp_op_bgeu_o;
    // dispatch to MULDIV
    wire req_muldiv_o;
    wire [31:0] muldiv_op1_o;
    wire [31:0] muldiv_op2_o;
    wire muldiv_op_mul_o;
    wire muldiv_op_mulh_o;
    wire muldiv_op_mulhsu_o;
    wire muldiv_op_mulhu_o;
    wire muldiv_op_div_o;
    wire muldiv_op_divu_o;
    wire muldiv_op_rem_o;
    wire muldiv_op_remu_o;
    // dispatch to CSR
    wire req_csr_o;
    wire [31:0] csr_op1_o;
    wire [31:0] csr_addr_o;
    wire csr_csrrw_o;
    wire csr_csrrs_o;
    wire csr_csrrc_o;
    // dispatch to MEM
    wire req_mem_o;
    wire [31:0] mem_addr;
    wire [31:0] mem_rs2_data_o;
    wire mem_op_lb_o;
    wire mem_op_lh_o;
    wire mem_op_lw_o;
    wire mem_op_lbu_o;
    wire mem_op_lhu_o;
    wire mem_op_sb_o;
    wire mem_op_sh_o;
    wire mem_op_sw_o;
    // dispatch to SYS
    wire sys_op_nop_o;
    wire sys_op_mret_o;
    wire sys_op_ecall_o;
    wire sys_op_ebreak_o;
    wire sys_op_fence_o;

    exu_dispatch u_exu_dispatch (
        // input
        .clk(clk),
        .rst_n(rst_n),
        .dec_info_bus_i(dec_info_bus_i),
        .dec_imm_i(dec_imm_i),
        .dec_pc_i(dec_pc_i),
        .rs1_rdata_i(reg1_rdata_i),
        .rs2_rdata_i(reg2_rdata_i),
        // dispatch to ALU
        .alu_op1_o(alu_op1_o),
        .alu_op2_o(alu_op2_o),
        .req_alu_o(req_alu_o),
        .alu_op_lui_o(alu_op_lui_o),
        .alu_op_auipc_o(alu_op_auipc_o),
        .alu_op_add_o(alu_op_add_o),
        .alu_op_sub_o(alu_op_sub_o),
        .alu_op_sll_o(alu_op_sll_o),
        .alu_op_slt_o(alu_op_slt_o),
        .alu_op_sltu_o(alu_op_sltu_o),
        .alu_op_xor_o(alu_op_xor_o),
        .alu_op_srl_o(alu_op_srl_o),
        .alu_op_sra_o(alu_op_sra_o),
        .alu_op_or_o(alu_op_or_o),
        .alu_op_and_o(alu_op_and_o),
        // dispatch to BJP
        .bjp_jump_op1_o(bjp_jump_op1_o),
        .bjp_jump_op2_o(bjp_jump_op2_o),
        .req_bjp_o(req_bjp_o),
        .bjp_op_jump_o(bjp_op_jump_o),
        .bjp_op_beq_o(bjp_op_beq_o),
        .bjp_op_bne_o(bjp_op_bne_o),
        .bjp_op_blt_o(bjp_op_blt_o),
        .bjp_op_bltu_o(bjp_op_bltu_o),
        .bjp_op_bge_o(bjp_op_bge_o),
        .bjp_op_bgeu_o(bjp_op_bgeu_o),
        // dispatch to MULDIV
        .req_muldiv_o(req_muldiv_o),
        .muldiv_op1_o(muldiv_op1_o),
        .muldiv_op2_o(muldiv_op2_o),
        .muldiv_op_mul_o(muldiv_op_mul_o),
        .muldiv_op_mulh_o(muldiv_op_mulh_o),
        .muldiv_op_mulhsu_o(muldiv_op_mulhsu_o),
        .muldiv_op_mulhu_o(muldiv_op_mulhu_o),
        .muldiv_op_div_o(muldiv_op_div_o),
        .muldiv_op_divu_o(muldiv_op_divu_o),
        .muldiv_op_rem_o(muldiv_op_rem_o),
        .muldiv_op_remu_o(muldiv_op_remu_o),
        // dispatch to CSR
        .req_csr_o(req_csr_o),
        .csr_op1_o(csr_op1_o),
        .csr_addr_o(csr_addr_o),
        .csr_csrrw_o(csr_csrrw_o),
        .csr_csrrs_o(csr_csrrs_o),
        .csr_csrrc_o(csr_csrrc_o),
        // dispatch to MEM
        .req_mem_o(req_mem_o),
        .mem_addr_o(mem_addr),
        .mem_rs2_data_o(mem_rs2_data_o),
        .mem_op_lb_o(mem_op_lb_o),
        .mem_op_lh_o(mem_op_lh_o),
        .mem_op_lw_o(mem_op_lw_o),
        .mem_op_lbu_o(mem_op_lbu_o),
        .mem_op_lhu_o(mem_op_lhu_o),
        .mem_op_sb_o(mem_op_sb_o),
        .mem_op_sh_o(mem_op_sh_o),
        .mem_op_sw_o(mem_op_sw_o),
        // dispatch to SYS
        .sys_op_nop_o(sys_op_nop_o),
        .sys_op_mret_o(sys_op_mret_o),
        .sys_op_ecall_o(sys_op_ecall_o),
        .sys_op_ebreak_o(sys_op_ebreak_o),
        .sys_op_fence_o(sys_op_fence_o)
    );

    assign inst_ecall_o  = sys_op_ecall_o;
    assign inst_ebreak_o = sys_op_ebreak_o;
    assign inst_mret_o   = sys_op_mret_o;

    wire [31:0] alu_res_o;
    wire [31:0] bjp_res_o;

    // 分支比较用自己的比较器, 直接比 rs1/rs2。原来经过共享 ALU 的操作数选择 (和 CSR 读数据同一个与或),
    // 是 "分支解析 -> 冲刷 -> fetch_pc" 这条 sys_clk 最差路径的大头。
    // 操作码已经按 op_bjp 门控过 (exu_dispatch), 不是分支时结果为 0
    wire br_eq = (reg1_rdata_i == reg2_rdata_i);
    wire br_lt = ($signed(reg1_rdata_i) < $signed(reg2_rdata_i));
    wire br_ltu = (reg1_rdata_i < reg2_rdata_i);
    wire bjp_cmp_res_o = (bjp_op_beq_o & br_eq) | (bjp_op_bne_o & ~br_eq) |
                         (bjp_op_blt_o & br_lt) | (bjp_op_bge_o & ~br_lt) |
                         (bjp_op_bltu_o & br_ltu) | (bjp_op_bgeu_o & ~br_ltu);
    wire [31:0] csr_op1 = csr_csrrc_o ? (~csr_op1_o) : csr_op1_o;
    wire [31:0] csr_op2 = csr_csrrw_o ? (32'h0) : csr_rdata_i;

    exu_alu_datapath u_exu_alu_datapath (
        .clk(clk),
        .rst_n(rst_n),
        // ALU
        .req_alu_i(req_alu_o),
        .alu_op1_i(alu_op1_o),
        .alu_op2_i(alu_op2_o),
        .alu_op_add_i(alu_op_add_o | alu_op_lui_o | alu_op_auipc_o),
        .alu_op_sub_i(alu_op_sub_o),
        .alu_op_sll_i(alu_op_sll_o),
        .alu_op_slt_i(alu_op_slt_o),
        .alu_op_sltu_i(alu_op_sltu_o),
        .alu_op_xor_i(alu_op_xor_o),
        .alu_op_srl_i(alu_op_srl_o),
        .alu_op_sra_i(alu_op_sra_o),
        .alu_op_or_i(alu_op_or_o),
        .alu_op_and_i(alu_op_and_o),
        // BJP
        .req_bjp_i(req_bjp_o),
        .bjp_op_jump_i(bjp_op_jump_o),
        .bjp_jump_op1_i(bjp_jump_op1_o),
        .bjp_jump_op2_i(bjp_jump_op2_o),
        // CSR
        .req_csr_i(req_csr_o),
        .csr_op1_i(csr_op1),
        .csr_op2_i(csr_op2),
        .csr_csrrw_i(csr_csrrw_o),
        .csr_csrrs_i(csr_csrrs_o),
        .csr_csrrc_i(csr_csrrc_o),

        .alu_res_o(alu_res_o),
        .bjp_res_o(bjp_res_o)
    );

    wire mem_mem_we_o;
    wire [31:0] mem_wdata;
    wire mem_stall_o;

    exu_mem u_exu_mem (
        .clk(clk),
        .rst_n(rst_n),
        .req_mem_i(req_mem_o),
        .mem_rd_i(rd_waddr_i),
        .mem_addr_i(mem_addr),
        .mem_rs2_data_i(mem_rs2_data_o),
        .mem_req_ready_i(mem_req_ready_i),
        .mem_rsp_valid_i(mem_rsp_valid_i),
        .mem_rdata_i(mem_rdata_i),
        .mem_op_lb_i(mem_op_lb_o),
        .mem_op_lh_i(mem_op_lh_o),
        .mem_op_lw_i(mem_op_lw_o),
        .mem_op_lbu_i(mem_op_lbu_o),
        .mem_op_lhu_i(mem_op_lhu_o),
        .mem_op_sb_i(mem_op_sb_o),
        .mem_op_sh_i(mem_op_sh_o),
        .mem_op_sw_i(mem_op_sw_o),
        .mem_access_misaligned_o(mem_access_misaligned_o),
        .mem_stall_o(mem_stall_o),
        .mem_addr_o(mem_addr_o),
        .mem_wdata_o(mem_wdata),
        .mem_mem_we_o(mem_mem_we_o),
        .mem_sel_o(mem_sel_o),
        .mem_req_valid_o(mem_req_valid_o),
        .mem_rsp_ready_o(mem_rsp_ready_o),
        .load_we_o(load_we_o),
        .load_waddr_o(load_waddr_o),
        .load_wdata_o(load_wdata_o),
        .load_ex_rd_o(load_ex_rd_o),
        .load_wait_rd_o(load_wait_rd_o)
    );

    wire [31:0] muldiv_reg_wdata_o;
    wire muldiv_reg_we_o;
    wire muldiv_stall_o;

    exu_muldiv u_exu_muldiv (
        .clk(clk),
        .rst_n(rst_n),
        .muldiv_op1_i(muldiv_op1_o),
        .muldiv_op2_i(muldiv_op2_o),
        .muldiv_op_mul_i(muldiv_op_mul_o),
        .muldiv_op_mulh_i(muldiv_op_mulh_o),
        .muldiv_op_mulhsu_i(muldiv_op_mulhsu_o),
        .muldiv_op_mulhu_i(muldiv_op_mulhu_o),
        .muldiv_op_div_i(muldiv_op_div_o),
        .muldiv_op_divu_i(muldiv_op_divu_o),
        .muldiv_op_rem_i(muldiv_op_rem_o),
        .muldiv_op_remu_i(muldiv_op_remu_o),
        .muldiv_reg_wdata_o(muldiv_reg_wdata_o),
        .muldiv_reg_we_o(muldiv_reg_we_o),
        .muldiv_stall_o(muldiv_stall_o)
    );

    wire commit_reg_we_o;

    exu_commit u_exu_commit (
        .clk(clk),
        .rst_n(rst_n),
        .req_muldiv_i(req_muldiv_o),
        .muldiv_reg_we_i(muldiv_reg_we_o),
        .muldiv_reg_waddr_i(rd_waddr_i),
        .muldiv_reg_wdata_i(muldiv_reg_wdata_o),
        .req_mem_i(req_mem_o),
        .req_csr_i(req_csr_o),
        .csr_reg_we_i(req_csr_o),
        .csr_reg_waddr_i(rd_waddr_i),
        .csr_reg_wdata_i(csr_rdata_i),
        .req_bjp_i(req_bjp_o),
        .bjp_reg_we_i(bjp_op_jump_o),
        .bjp_reg_wdata_i(next_pc_i),
        .bjp_reg_waddr_i(rd_waddr_i),
        .rd_we_i(rd_we_i),
        .rd_waddr_i(rd_waddr_i),
        .alu_reg_wdata_i(alu_res_o),
        .reg_we_o(commit_reg_we_o),
        .reg_waddr_o(reg_waddr_o),
        .reg_wdata_o(reg_wdata_o)
    );

    assign reg_we_o = commit_reg_we_o;

    // 分支相关
    wire is_jalr = bjp_op_jump_o && dec_info_bus_i[`DECINFO_BJP_OP1RS1];
    wire is_jal = bjp_op_jump_o && ~dec_info_bus_i[`DECINFO_BJP_OP1RS1];
    wire is_cond_branch = req_bjp_o && ~bjp_op_jump_o;
    wire bjp_taken = bjp_cmp_res_o | bjp_op_jump_o;
    wire [31:0] bjp_target = is_jalr ? {bjp_res_o[31:1], 1'b0} : bjp_res_o;

    // 调用: jal/jalr 写 ra 或 t0; 返回: jalr x0, 0(ra 或 t0)。与 RISC-V 规范里的 RAS 提示一致
    wire rd_link = (rd_waddr_i == 5'd1) || (rd_waddr_i == 5'd5);
    wire rs1_link = (rs1_raddr_i == 5'd1) || (rs1_raddr_i == 5'd5);
    wire is_call = bjp_op_jump_o && rd_link;
    wire is_ret = is_jalr && (rd_waddr_i == 5'd0) && rs1_link && (dec_imm_i == 32'h0);
    // imm 为奇数的 jalr 不预测 (见下面的核对); 正常代码里不会出现
    wire jalr_pred = is_jalr && !dec_imm_i[0];

    // 条件分支和 jal 只看"跳不跳": 同一静态分支的目标地址是固定的(B 型立即数 + PC),
    // 所以预测跳转且实际也跳时, 取指走的一定是对的路径。
    // jalr 的目标随寄存器变 (ret 由 RAS 预测, 其它用 BTB 记下的上次目标), 要核对取指走的目标
    // 等于 (rs1 + imm) & ~1。ID 已经算好 pred_rs1 = 预测目标 - imm, 这里只比 rs1, 不经过目标加法器;
    // 预测目标和 imm 都是偶数, 所以比 [31:1] 就等价。
    wire jalr_ok = pred_taken_i && jalr_pred && (reg1_rdata_i[31:1] == pred_rs1_i[31:1]);
    wire pred_ok = is_jalr ? jalr_ok : (pred_taken_i == bjp_taken);
    wire hold_flag = muldiv_stall_o | mem_stall_o;

    // 预测对就不冲刷, 让取指已经填好的目标路径继续往下走
    assign jump_flag_o = sys_op_fence_o | int_assert_i | ~pred_ok;
    assign jump_addr_o = int_assert_i ? int_addr_i :
                         sys_op_fence_o ? next_pc_i :
                         ~bjp_taken ? next_pc_i :
                         bjp_target;
    assign hold_flag_o = hold_flag;

    // 训练条件分支、jal 和 jalr。ret 的目标由 RAS 给, 其它 jalr 预测成上次的目标
    // (远调用 auipc+jalr 的目标固定, 函数指针也常常连续调同一个)。
    // EX 被暂停时同一条指令会停留多拍, 用 ~hold_flag 保证只训练一次。
    assign btb_upd_en_o = (is_jal | is_cond_branch | jalr_pred) & ~hold_flag;
    assign btb_upd_pc_o = dec_pc_i;
    assign btb_upd_target_o = bjp_target;
    assign btb_upd_taken_o = bjp_taken;
    assign btb_upd_kind_o = is_ret ? `BTB_KIND_RET : is_call ? `BTB_KIND_CALL : `BTB_KIND_NONE;

    assign ras_push_o = is_call & ~hold_flag;
    assign ras_pop_o = is_ret & ~hold_flag;
    assign ras_addr_o = next_pc_i;

    assign csr_raddr_o = csr_addr_o;
    assign csr_waddr_o = csr_addr_o;
    assign csr_we_o = req_csr_o;
    assign csr_wdata_o = alu_res_o;

    assign mem_we_o = mem_mem_we_o;
    assign mem_wdata_o = mem_wdata;

endmodule
