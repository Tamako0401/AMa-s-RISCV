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


module exu_mem(

    input wire clk,
    input wire rst_n,

    input req_mem_i,
    input wire[31:0] mem_addr_i,
    input wire[31:0] mem_rs2_data_i,
    input wire[31:0] mem_rdata_i,
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
    output wire[31:0] mem_addr_o,
    output wire[31:0] mem_wdata_o,
    output wire mem_reg_we_o,
    output wire mem_mem_we_o,
    output wire[3:0] mem_sel_o,
    output wire mem_req_valid_o,
    output wire mem_rsp_ready_o

    );


    reg [31:0] response_data;
    wire[1:0] mem_addr_index = mem_addr_i[1:0];
    wire mem_addr_index00 = (mem_addr_index == 2'b00);
    wire mem_addr_index01 = (mem_addr_index == 2'b01);
    wire mem_addr_index10 = (mem_addr_index == 2'b10);
    wire mem_addr_index11 = (mem_addr_index == 2'b11);

    assign mem_sel_o[0] = mem_addr_index00 | mem_op_sw_i;
    assign mem_sel_o[1] = mem_addr_index01 | (mem_op_sh_i & mem_addr_index00) | mem_op_sw_i;
    assign mem_sel_o[2] = mem_addr_index10 | mem_op_sw_i;
    assign mem_sel_o[3] = mem_addr_index11 | (mem_op_sh_i & mem_addr_index10) | mem_op_sw_i;

    reg[31:0] sb_res;

    always @ (*) begin
        sb_res = 32'h0;
        case (1'b1)
            mem_addr_index00: sb_res = {24'h0, mem_rs2_data_i[7:0]};
            mem_addr_index01: sb_res = {16'h0, mem_rs2_data_i[7:0], 8'h0};
            mem_addr_index10: sb_res = {8'h0, mem_rs2_data_i[7:0], 16'h0};
            mem_addr_index11: sb_res = {mem_rs2_data_i[7:0], 24'h0};
        endcase
    end

    reg[31:0] sh_res;

    always @ (*) begin
        sh_res = 32'h0;
        case (1'b1)
            mem_addr_index00: sh_res = {16'h0, mem_rs2_data_i[15:0]};
            mem_addr_index10: sh_res = {mem_rs2_data_i[15:0], 16'h0};
        endcase
    end

    wire[31:0] sw_res = mem_rs2_data_i;

    reg[31:0] lb_res;

    always @ (*) begin
        lb_res = 32'h0;
        case (1'b1)
            mem_addr_index00: lb_res = {{24{mem_op_lb_i & response_data[7]}}, response_data[7:0]};
            mem_addr_index01: lb_res = {{24{mem_op_lb_i & response_data[15]}}, response_data[15:8]};
            mem_addr_index10: lb_res = {{24{mem_op_lb_i & response_data[23]}}, response_data[23:16]};
            mem_addr_index11: lb_res = {{24{mem_op_lb_i & response_data[31]}}, response_data[31:24]};
        endcase
    end

    reg[31:0] lh_res;

    always @ (*) begin
        lh_res = 32'h0;
        case (1'b1)
            mem_addr_index00: lh_res = {{24{mem_op_lh_i & response_data[15]}}, response_data[15:0]};
            mem_addr_index10: lh_res = {{24{mem_op_lh_i & response_data[31]}}, response_data[31:16]};
        endcase
    end

    wire[31:0] lw_res = response_data;

    reg[31:0] mem_wdata;

    always @ (*) begin
        mem_wdata = 32'h0;
        case (1'b1)
            mem_op_sb_i:  mem_wdata = sb_res;
            mem_op_sh_i:  mem_wdata = sh_res;
            mem_op_sw_i:  mem_wdata = sw_res;
            mem_op_lb_i:  mem_wdata = lb_res;
            mem_op_lbu_i: mem_wdata = lb_res;
            mem_op_lh_i:  mem_wdata = lh_res;
            mem_op_lhu_i: mem_wdata = lh_res;
            mem_op_lw_i:  mem_wdata = lw_res;
        endcase
    end

    assign mem_wdata_o = mem_wdata;

    // Exactly one request per memory instruction. EX remains held until done.
    reg pending, done;
    wire request_fire = mem_req_valid_o && mem_req_ready_i;
    wire response_fire = mem_rsp_valid_i && mem_rsp_ready_o;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 1'b0;
            done <= 1'b0;
            response_data <= 32'b0;
        end else begin
            done <= 1'b0;
            if (request_fire) pending <= 1'b1;
            if (response_fire) begin
                pending <= 1'b0;
                done <= 1'b1;
                response_data <= mem_rdata_i;
            end
        end
    end
    assign mem_rsp_ready_o = rst_n && pending;
    assign mem_req_valid_o = rst_n && req_mem_i && !pending && !done
                             && !mem_access_misaligned_o;
    assign mem_stall_o = req_mem_i && !done && !mem_access_misaligned_o;
    assign mem_addr_o = mem_addr_i;
    assign mem_reg_we_o = (mem_op_lb_i | mem_op_lh_i | mem_op_lw_i |
                          mem_op_lbu_i | mem_op_lhu_i) && done;
    // Write intent belongs to the request, never to the response.
    assign mem_mem_we_o = mem_op_sb_i | mem_op_sh_i | mem_op_sw_i;

    assign mem_access_misaligned_o = (mem_op_sw_i | mem_op_lw_i)? (mem_addr_i[0] | mem_addr_i[1]):
                                     (mem_op_sh_i | mem_op_lh_i | mem_op_lhu_i)? mem_addr_i[0]:
                                     0;

endmodule
