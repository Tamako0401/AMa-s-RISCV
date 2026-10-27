// Imported and adapted for AMa-s-RISCV, 2026-09-25.
// Changes: Normalize line endings to LF and remove trailing whitespace. Remove dependency on upstream core/defines.v.
// Provenance: docs/third-party.md and third_party/tinyriscv-manifest.json.
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


// 通用寄存器模块
module gpr_reg (

    input wire clk,
    input wire rst_n,

    input wire        we_i,     // 写寄存器使能
    input wire [ 4:0] waddr_i,  // 写寄存器地址
    input wire [31:0] wdata_i,  // 写寄存器数据

    // 第二个写口: load 结果 (指令已离开 EX)。译码级保证它和第一个写口不会同拍写同一个寄存器
    input wire        load_we_i,
    input wire [ 4:0] load_waddr_i,
    input wire [31:0] load_wdata_i,

    input  wire [ 4:0] raddr1_i,  // 读寄存器1地址
    output wire [31:0] rdata1_o,  // 读寄存器1数据

    input  wire [ 4:0] raddr2_i,  // 读寄存器2地址
    output wire [31:0] rdata2_o   // 读寄存器2数据

);

    // 存储用 LUT RAM (每块一个写口、一个组合读口), 不用 32x32 个触发器 (约 900 LUT + 990 FF)。
    // 两个写口各写一组, 每组复制两份给两个读口; lvt 记下每个寄存器最后是哪个写口写的,
    // 读的时候按它选组 (Live Value Table)。两个写口不会同拍写同一个寄存器 (见上), lvt 没有冲突。
    (* syn_ramstyle = "select_ram" *) reg [31:0] bank_a1[0:31];
    (* syn_ramstyle = "select_ram" *) reg [31:0] bank_a2[0:31];
    (* syn_ramstyle = "select_ram" *) reg [31:0] bank_b1[0:31];
    (* syn_ramstyle = "select_ram" *) reg [31:0] bank_b2[0:31];
    reg [31:0] lvt;  // 1: 最后由 load 写口写

    // 写 x0 无害: 读 x0 恒为 0
    always @(posedge clk) begin
        if (we_i) begin
            bank_a1[waddr_i] <= wdata_i;
            bank_a2[waddr_i] <= wdata_i;
        end
        if (load_we_i) begin
            bank_b1[load_waddr_i] <= load_wdata_i;
            bank_b2[load_waddr_i] <= load_wdata_i;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lvt <= 32'h0;
        else begin
            if (we_i) lvt[waddr_i] <= 1'b0;
            if (load_we_i) lvt[load_waddr_i] <= 1'b1;
        end
    end

    wire [31:0] rf1 = lvt[raddr1_i] ? bank_b1[raddr1_i] : bank_a1[raddr1_i];
    wire [31:0] rf2 = lvt[raddr2_i] ? bank_b2[raddr2_i] : bank_a2[raddr2_i];

    // 同拍写的值直接旁路给读口
    assign rdata1_o = (|raddr1_i)? ((we_i & (waddr_i == raddr1_i))? wdata_i:
                                    (load_we_i & (load_waddr_i == raddr1_i))? load_wdata_i: rf1): 32'h0;
    assign rdata2_o = (|raddr2_i)? ((we_i & (waddr_i == raddr2_i))? wdata_i:
                                    (load_we_i & (load_waddr_i == raddr2_i))? load_wdata_i: rf2): 32'h0;

endmodule
