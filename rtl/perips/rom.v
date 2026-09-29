// Adapted from JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G
// Source commit: 00a3334d7c98f57a6d429a5e18910a7e2e88390b (source/perips/rom.v)
// Local changes:
//   - Remove the vendor IP instance (ram1) and the dependency on core/defines.v.
//   - Store instructions in an internal reg array loaded by $readmemh instead of
//     a PANGO IP core, so the file elaborates and simulates with plain Icarus.
//   - DP now really controls the depth (upstream DP was a dead parameter that
//     only fed the commented-out gen_ram instance).
//   - Explicitly read-only: we_i/data_i/sel_i are ignored.
// See docs/third-party.md and docs/cpu-baseline.md.
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

// 指令存储器(ROM)从设备
//
// 总线接口与 perips/gpio.v、perips/uart.v 以及 rib 的从设备端口逐位对应:
//     addr_i / data_i / sel_i / we_i / data_o
//     req_valid_i / req_ready_o / rsp_valid_o / rsp_ready_i
//
// 特性:
// - 只读: 写请求会被正常握手但被丢弃(we_i/data_i/sel_i 不参与任何逻辑);
// - addr_i 是字节地址, 内部右移 2 位取字地址, 高位超出 DP 的部分被截断
//   (调用方需保证地址落在合法区间, 与上游 gen_ram 的约定一致);
// - 读数据在请求握手后的下一拍与 rsp_valid_o 同时有效;
// - 程序初值由 $readmemh 从 ROM_INIT_FILE 载入; 文件名为空则不初始化(读到 X)。
//   该初始化方式在仿真中已验证; 能否被综合工具推断成 ROM 初值尚未验证。
module rom #(
    parameter DP = 16384,                 // 深度, 单位 word(4字节)
    parameter ROM_INIT_FILE = ""          // 初始化 hex 文件名, 相对仿真工作目录
)(

    input wire clk,
    input wire rst_n,
    input wire[31:0] addr_i,
    input wire[31:0] data_i,
    input wire[3:0] sel_i,
    input wire we_i,
    output wire[31:0] data_o,

    input wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input wire rsp_ready_i

    );

    localparam AW = $clog2(DP);

    reg[31:0] mem [0:DP-1];
    reg[AW-1:0] addr_r;

    // 字节地址 -> 字地址
    wire[31:0] word_addr = addr_i[31:2];

    // 程序初值
    initial begin
        if (ROM_INIT_FILE != "") begin
            $readmemh(ROM_INIT_FILE, mem);
        end
    end

    // 采样地址: 读数据在下一拍输出, 正好与 rsp_valid_o 对齐
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_r <= {AW{1'b0}};
        end else begin
            addr_r <= word_addr[AW-1:0];
        end
    end

    assign data_o = mem[addr_r];

    // req/rsp 握手时序: 请求被接受后的下一拍拉高 rsp_valid_o
    vld_rdy #(
        .CUT_READY(0)
    ) u_vld_rdy(
        .clk(clk),
        .rst_n(rst_n),
        .vld_i(req_valid_i),
        .rdy_o(req_ready_o),
        .rdy_i(rsp_ready_i),
        .vld_o(rsp_valid_o)
    );

endmodule
