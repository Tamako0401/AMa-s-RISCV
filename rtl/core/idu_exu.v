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

// 将译码结果向执行模块传递
module idu_exu (

    input wire clk,
    input wire rst_n,

    input wire [`STALL_WIDTH-1:0] stall_i,  // 流水线暂停
    input wire                    flush_i,  // 流水线冲刷

    input wire [31:0] inst_i,
    input wire [`DECINFO_WIDTH-1:0] dec_info_bus_i,
    input wire [31:0] dec_imm_i,
    input wire [31:0] dec_pc_i,
    input wire [31:0] rs1_rdata_i,
    input wire [31:0] rs2_rdata_i,
    input wire [4:0] rd_waddr_i,
    input wire rd_we_i,
    input wire pred_taken_i,
    input wire [31:0] pred_rs1_i,

    output wire [31:0] inst_o,
    output wire [`DECINFO_WIDTH-1:0] dec_info_bus_o,
    output wire [31:0] dec_imm_o,
    output wire [31:0] dec_pc_o,
    output wire [31:0] rs1_rdata_o,
    output wire [31:0] rs2_rdata_o,
    output wire [4:0] rd_waddr_o,
    output wire rd_we_o,
    output wire pred_taken_o,
    output wire [31:0] pred_rs1_o

);

    wire en = !stall_i[`STALL_EX] | flush_i;
    // 冲刷, 或 ID 停住而 EX 照走 (等 load 结果) 时, 送进 EX 的是气泡
    wire bubble = flush_i | stall_i[`STALL_ID];

    wire [`DECINFO_WIDTH-1:0] i_dec_info_bus = bubble ? {`DECINFO_WIDTH{1'b0}} : dec_info_bus_i;
    wire [`DECINFO_WIDTH-1:0] dec_info_bus;
    gen_en_dff #(`DECINFO_WIDTH) info_bus_ff (
        clk,
        rst_n,
        en,
        i_dec_info_bus,
        dec_info_bus
    );
    assign dec_info_bus_o = dec_info_bus;

    wire [31:0] i_dec_imm = bubble ? 32'h0 : dec_imm_i;
    wire [31:0] dec_imm;
    gen_en_dff #(32) imm_ff (
        clk,
        rst_n,
        en,
        i_dec_imm,
        dec_imm
    );
    assign dec_imm_o = dec_imm;

    wire [31:0] i_dec_pc = bubble ? 32'h0 : dec_pc_i;
    wire [31:0] dec_pc;
    gen_en_dff #(32) pc_ff (
        clk,
        rst_n,
        en,
        i_dec_pc,
        dec_pc
    );
    assign dec_pc_o = dec_pc;

    wire [31:0] i_rs1_rdata = bubble ? 32'h0 : rs1_rdata_i;
    wire [31:0] rs1_rdata;
    gen_en_dff #(32) rs1_rdata_ff (
        clk,
        rst_n,
        en,
        i_rs1_rdata,
        rs1_rdata
    );
    assign rs1_rdata_o = rs1_rdata;

    wire [31:0] i_rs2_rdata = bubble ? 32'h0 : rs2_rdata_i;
    wire [31:0] rs2_rdata;
    gen_en_dff #(32) rs2_rdata_ff (
        clk,
        rst_n,
        en,
        i_rs2_rdata,
        rs2_rdata
    );
    assign rs2_rdata_o = rs2_rdata;

    wire [4:0] i_rd_waddr = bubble ? 5'h0 : rd_waddr_i;
    wire [4:0] rd_waddr;
    gen_en_dff #(5) rd_waddr_ff (
        clk,
        rst_n,
        en,
        i_rd_waddr,
        rd_waddr
    );
    assign rd_waddr_o = rd_waddr;

    wire i_pred_taken = bubble ? 1'b0 : pred_taken_i;
    wire pred_taken;
    gen_en_dff #(1) pred_taken_ff (
        clk,
        rst_n,
        en,
        i_pred_taken,
        pred_taken
    );
    assign pred_taken_o = pred_taken;

    // 只在 pred_taken 时有意义, 气泡不用清零
    gen_en_dff #(32) pred_rs1_ff (
        clk,
        rst_n,
        en,
        pred_rs1_i,
        pred_rs1_o
    );

    wire i_rd_we = bubble ? 1'b0 : rd_we_i;
    wire rd_we;
    gen_en_dff #(1) rd_we_ff (
        clk,
        rst_n,
        en,
        i_rd_we,
        rd_we
    );
    assign rd_we_o = rd_we;

    wire [31:0] i_inst = bubble ? 32'h0 : inst_i;
    wire [31:0] inst;
    gen_en_dff #(32) inst_ff (
        clk,
        rst_n,
        en,
        i_inst,
        inst
    );
    assign inst_o = inst;

endmodule
