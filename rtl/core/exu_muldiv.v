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


module exu_muldiv (

    input wire clk,
    input wire rst_n,

    input wire [31:0] muldiv_op1_i,
    input wire [31:0] muldiv_op2_i,
    input wire muldiv_op_mul_i,
    input wire muldiv_op_mulh_i,
    input wire muldiv_op_mulhsu_i,
    input wire muldiv_op_mulhu_i,
    input wire muldiv_op_div_i,
    input wire muldiv_op_divu_i,
    input wire muldiv_op_rem_i,
    input wire muldiv_op_remu_i,

    output wire [31:0] muldiv_reg_wdata_o,
    output wire muldiv_reg_we_o,
    output wire muldiv_stall_o

);

    // 除法操作
    wire div_ready;
    wire op_div = muldiv_op_div_i | muldiv_op_divu_i | muldiv_op_rem_i | muldiv_op_remu_i;
    wire div_start = op_div & (!div_ready);
    wire [3:0] div_op = {muldiv_op_div_i, muldiv_op_divu_i, muldiv_op_rem_i, muldiv_op_remu_i};
    wire [31:0] div_result;

    divider u_divider (
        .clk(clk),
        .rst_n(rst_n),
        .dividend_i(muldiv_op1_i),
        .divisor_i(muldiv_op2_i),
        .start_i(div_start),
        .op_i(div_op),
        .result_o(div_result),
        .ready_o(div_ready)
    );

    // 乘法操作: 两拍。第一拍把操作数按有无符号扩成 33 位做带符号乘法, 乘积寄存;
    // 第二拍只取高/低 32 位写回。原来第一拍只寄存操作数, 第二拍要先求补、乘、再对 64 位结果求补,
    // 整串接着写回和 ID 的旁路, 是 sys_clk 的最差路径。
    wire op_mul = muldiv_op_mul_i | muldiv_op_mulh_i | muldiv_op_mulhsu_i | muldiv_op_mulhu_i;

    wire mul_ready_r;
    wire mul_ready = (~mul_ready_r) & op_mul;
    gen_rst_0_dff #(1) mul_ready_ff (
        clk,
        rst_n,
        mul_ready,
        mul_ready_r
    );

    wire mul_start = (~mul_ready_r) & op_mul;

    wire op1_signed = muldiv_op_mulh_i | muldiv_op_mulhsu_i;
    wire op2_signed = muldiv_op_mulh_i;
    wire signed [32:0] mul_a = {op1_signed & muldiv_op1_i[31], muldiv_op1_i};
    wire signed [32:0] mul_b = {op2_signed & muldiv_op2_i[31], muldiv_op2_i};
    wire signed [65:0] mul_prod = mul_a * mul_b;

    wire [63:0] mul_res_r;
    gen_en_dff #(64) mul_res_ff (
        clk,
        rst_n,
        mul_start,
        mul_prod[63:0],
        mul_res_r
    );

    wire [31:0] mul_op_res = !op_mul ? 32'h0 : muldiv_op_mul_i ? mul_res_r[31:0] : mul_res_r[63:32];

    // 运算结果
    assign muldiv_reg_wdata_o = div_result | mul_op_res;
    assign muldiv_reg_we_o = div_ready | mul_ready_r;
    assign muldiv_stall_o = div_start | mul_start;

endmodule
