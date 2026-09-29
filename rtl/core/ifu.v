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
// RESET_PC 默认 = 哈佛式指令存储器(ROM)基址 0x0000_0000, 见 docs/cpu-baseline.md。
module ifu #(parameter [31:0] RESET_PC = 32'h00000000)(

    input wire clk,
    input wire rst_n,

    input wire flush_i,
    input wire[31:0] flush_addr_i,             // 跳转地址
    input wire[`STALL_WIDTH-1:0] stall_i,      // 流水线暂停标志
    input wire jtag_halt_i,

    output wire[31:0] inst_o,
    output wire[31:0] pc_o,
    output wire inst_valid_o,

    output wire[31:0] ibus_addr_o,
    input wire[31:0] ibus_data_i,
    output wire[31:0] ibus_data_o,
    output wire[3:0] ibus_sel_o,
    output wire ibus_we_o,
    output wire req_valid_o,
    input wire req_ready_i,
    input wire rsp_valid_i,
    output wire rsp_ready_o

    );

    // One outstanding fetch and one response buffer. No fixed-latency or
    // bus-arbitration assumptions. A redirected outstanding fetch is drained.
    localparam IDLE = 2'd0, SEND = 2'd1, WAIT = 2'd2, FULL = 2'd3;
    reg [1:0] state;
    reg [31:0] next_pc, request_pc, instruction;
    reg killed;
    wire blocked = stall_i[`STALL_PC] | jtag_halt_i;

    assign req_valid_o = rst_n && state == SEND;
    assign rsp_ready_o = rst_n && state == WAIT;
    assign ibus_addr_o = request_pc;
    assign ibus_data_o = 32'b0;
    assign ibus_sel_o = 4'b1111;
    assign ibus_we_o = 1'b0;
    assign inst_valid_o = state == FULL && !blocked && !flush_i;
    assign inst_o = inst_valid_o ? instruction : `INST_NOP;
    assign pc_o = request_pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            next_pc <= RESET_PC;
            request_pc <= RESET_PC;
            instruction <= `INST_NOP;
            killed <= 1'b0;
        end else begin
            case (state)
                IDLE: if (!blocked && !flush_i) begin
                    request_pc <= next_pc;
                    next_pc <= next_pc + 4;
                    killed <= 1'b0;
                    state <= SEND;
                end
                SEND: if (req_ready_i) state <= WAIT;
                WAIT: if (rsp_valid_i) begin
                    instruction <= ibus_data_i;
                    state <= (killed || flush_i) ? IDLE : FULL;
                end
                FULL: if (!blocked || flush_i) state <= IDLE;
            endcase
            if (flush_i) begin
                next_pc <= flush_addr_i;
                killed <= 1'b1;
            end
        end
    end
endmodule
