// Adapted from JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G
// Source commit: 00a3334d7c98f57a6d429a5e18910a7e2e88390b (source/perips/ram.v)
// Local changes:
//   - Restore the generic gen_ram body that upstream had commented out, and drop
//     the vendor IP instance (ram2) plus the core/defines.v dependency.
//   - DP now drives gen_ram's depth instead of being a dead parameter.
//   - The write enable is gated by the request handshake, so a master that keeps
//     we_i asserted while waiting for the response cannot write more than once.
//   - Add an optional RAM_INIT_FILE parameter, forwarded to gen_ram's INIT_FILE,
//     so the data memory can be preloaded with a program's .data image.
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

// 数据存储器(RAM)从设备
//
// 总线接口与 perips/gpio_matrix.v、perips/uart.v 以及 rib 的从设备端口逐位对应:
//     addr_i / data_i / sel_i / we_i / data_o
//     req_valid_i / req_ready_o / rsp_valid_o / rsp_ready_i
//
// 特性:
// - 存储体复用 rtl/utils/gen_ram.v(字地址、按字节写、同步读);
// - addr_i 是字节地址, 右移 2 位后取低位作为 gen_ram 的字地址, 超出 DP 的
//   高位被截断(调用方需保证地址落在合法区间);
// - 写使能只在请求真正握手(valid & ready)的那一拍有效, 避免重复写入;
// - 初值由 $readmemh 从 RAM_INIT_FILE 载入(文件名为空则不初始化); 该方式在仿真中
//   已验证, 能否被综合工具推断成存储初值尚未验证。内容不随复位清零。
module ram #(
    parameter DP            = 8192,  // 深度, 单位 word(4字节)
    parameter RAM_INIT_FILE = ""     // 初始化 hex 文件名, 相对仿真工作目录
) (

    input wire clk,
    input wire rst_n,
    input wire [31:0] addr_i,
    input wire [31:0] data_i,
    input wire [3:0] sel_i,
    input wire we_i,
    output wire [31:0] data_o,

    input  wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input  wire rsp_ready_i

);

    localparam AW = $clog2(DP);

    // 字节地址 -> 字地址
    wire [31:0] word_addr = addr_i[31:2];

    // 请求被接受的那一拍才写: 主设备保持 we_i 等待响应时不会重复写入
    wire wr_en = we_i & req_valid_i & req_ready_o;

    gen_ram #(
        .DP(DP),
        .DW(32),
        .MW(4),
        .AW(AW),
        .INIT_FILE(RAM_INIT_FILE)
    ) u_gen_ram (
        .clk(clk),
        .addr_i(word_addr[AW-1:0]),
        .data_i(data_i),
        .sel_i(sel_i),
        .we_i(wr_en),
        .data_o(data_o)
    );

    // req/rsp 握手时序: 请求被接受后的下一拍拉高 rsp_valid_o
    vld_rdy #(
        .CUT_READY(0)
    ) u_vld_rdy (
        .clk  (clk),
        .rst_n(rst_n),
        .vld_i(req_valid_i),
        .rdy_o(req_ready_o),
        .rdy_i(rsp_ready_i),
        .vld_o(rsp_valid_o)
    );

endmodule
