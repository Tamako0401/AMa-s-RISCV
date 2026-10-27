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


module exu_mem (

    input wire clk,
    input wire rst_n,

    input req_mem_i,
    input wire [4:0] mem_rd_i,
    input wire [31:0] mem_addr_i,
    input wire [31:0] mem_rs2_data_i,
    input wire [31:0] mem_rdata_i,
    input wire mem_req_ready_i,
    input wire mem_rsp_valid_i,
    input wire mem_op_lb_i,
    input wire mem_op_lh_i,
    input wire mem_op_lw_i,
    input wire mem_op_lbu_i,
    input wire mem_op_lhu_i,
    input wire mem_op_sb_i,
    input wire mem_op_sh_i,
    input wire mem_op_sw_i,

    output wire mem_access_misaligned_o,
    output wire mem_stall_o,
    output wire [31:0] mem_addr_o,
    output wire [31:0] mem_wdata_o,
    output wire mem_mem_we_o,
    output wire [3:0] mem_sel_o,
    output wire mem_req_valid_o,
    output wire mem_rsp_ready_o,

    // load 的结果在响应那一拍写回 (寄存器堆的第二个写口); 那时指令已经离开 EX
    output wire load_we_o,
    output wire [4:0] load_waddr_o,
    output wire [31:0] load_wdata_o,
    // 结果还没写回的 load 的目的寄存器, 0 表示没有; 译码级据此停顿
    output wire [4:0] load_ex_rd_o,    // EX 里这条 load (本拍不会有结果)
    output wire [4:0] load_wait_rd_o   // 已发出、本拍响应还没到的 load

);


    // 访存请求被接受后 EX 就放行, 不等响应 (总线同一时刻只有一笔在途, 下一条访存在 EX 里等)。
    // pending: 有一笔请求已握手、响应未取走; 若是 load, p_* 记下写回需要的信息。
    reg pending;
    reg p_load;
    reg [4:0] p_rd;
    reg [1:0] p_index;
    reg p_lb, p_lh, p_lbu, p_lhu;
    wire is_load = mem_op_lb_i | mem_op_lh_i | mem_op_lw_i | mem_op_lbu_i | mem_op_lhu_i;
    wire [1:0] mem_addr_index = mem_addr_i[1:0];
    wire mem_addr_index00 = (mem_addr_index == 2'b00);
    wire mem_addr_index01 = (mem_addr_index == 2'b01);
    wire mem_addr_index10 = (mem_addr_index == 2'b10);
    wire mem_addr_index11 = (mem_addr_index == 2'b11);

    assign mem_sel_o[0] = mem_addr_index00 | mem_op_sw_i;
    assign mem_sel_o[1] = mem_addr_index01 | (mem_op_sh_i & mem_addr_index00) | mem_op_sw_i;
    assign mem_sel_o[2] = mem_addr_index10 | mem_op_sw_i;
    assign mem_sel_o[3] = mem_addr_index11 | (mem_op_sh_i & mem_addr_index10) | mem_op_sw_i;

    reg [31:0] sb_res;

    always @(*) begin
        sb_res = 32'h0;
        case (1'b1)
            mem_addr_index00: sb_res = {24'h0, mem_rs2_data_i[7:0]};
            mem_addr_index01: sb_res = {16'h0, mem_rs2_data_i[7:0], 8'h0};
            mem_addr_index10: sb_res = {8'h0, mem_rs2_data_i[7:0], 16'h0};
            mem_addr_index11: sb_res = {mem_rs2_data_i[7:0], 24'h0};
        endcase
    end

    reg [31:0] sh_res;

    always @(*) begin
        sh_res = 32'h0;
        case (1'b1)
            mem_addr_index00: sh_res = {16'h0, mem_rs2_data_i[15:0]};
            mem_addr_index10: sh_res = {mem_rs2_data_i[15:0], 16'h0};
        endcase
    end

    wire [31:0] sw_res = mem_rs2_data_i;

    reg [31:0] mem_wdata;

    always @(*) begin
        mem_wdata = 32'h0;
        case (1'b1)
            mem_op_sb_i: mem_wdata = sb_res;
            mem_op_sh_i: mem_wdata = sh_res;
            mem_op_sw_i: mem_wdata = sw_res;
        endcase
    end

    assign mem_wdata_o = mem_wdata;

    // 响应拍: 按发请求时记下的宽度和地址低位取字节/半字
    wire [7:0] rsp_byte = mem_rdata_i[8*p_index+:8];
    wire [15:0] rsp_half = p_index[1] ? mem_rdata_i[31:16] : mem_rdata_i[15:0];
    reg [31:0] load_data;

    always @(*) begin
        case (1'b1)
            p_lb:    load_data = {{24{rsp_byte[7]}}, rsp_byte};
            p_lbu:   load_data = {24'h0, rsp_byte};
            p_lh:    load_data = {{16{rsp_half[15]}}, rsp_half};
            p_lhu:   load_data = {16'h0, rsp_half};
            default: load_data = mem_rdata_i;
        endcase
    end

    wire request_fire = mem_req_valid_o && mem_req_ready_i;
    wire response_fire = mem_rsp_valid_i && mem_rsp_ready_o;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 1'b0;
            p_load <= 1'b0;
            p_rd <= 5'd0;
            p_index <= 2'd0;
            {p_lb, p_lh, p_lbu, p_lhu} <= 4'b0;
        end else if (request_fire) begin
            pending <= 1'b1;
            p_load <= is_load;
            p_rd <= mem_rd_i;
            p_index <= mem_addr_index;
            {p_lb, p_lh, p_lbu, p_lhu} <= {mem_op_lb_i, mem_op_lh_i, mem_op_lbu_i, mem_op_lhu_i};
        end else if (response_fire) begin
            pending <= 1'b0;
            p_load <= 1'b0;
        end
    end
    assign mem_rsp_ready_o = rst_n && pending;
    // 上一笔的响应拍不能同时发新请求 (rib 在响应握手那拍不接收)
    assign mem_req_valid_o = rst_n && req_mem_i && !pending && !mem_access_misaligned_o;
    assign mem_stall_o = req_mem_i && !mem_access_misaligned_o && !request_fire;
    assign mem_addr_o = mem_addr_i;
    // Write intent belongs to the request, never to the response.
    assign mem_mem_we_o = mem_op_sb_i | mem_op_sh_i | mem_op_sw_i;

    assign load_we_o = p_load && response_fire;
    assign load_waddr_o = p_rd;
    assign load_wdata_o = load_data;
    assign load_ex_rd_o = (req_mem_i && is_load) ? mem_rd_i : 5'd0;
    assign load_wait_rd_o = (p_load && !mem_rsp_valid_i) ? p_rd : 5'd0;

    assign mem_access_misaligned_o = (mem_op_sw_i | mem_op_lw_i)? (mem_addr_i[0] | mem_addr_i[1]):
                                     (mem_op_sh_i | mem_op_lh_i | mem_op_lhu_i)? mem_addr_i[0]:
                                     0;

endmodule
