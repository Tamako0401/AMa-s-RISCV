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

// RIB总线模块(valid/ready 握手)
//
// 结构: 2 个主设备 x 5 个从设备，同一时刻只允许一个未完成事务。
//
// 主设备端口与 tinyriscv_core.v 的一一对应关系(推荐的顶层连线):
//   m0 = 取指总线 ibus:
//     .m0_addr_i      (ibus_addr_o)
//     .m0_data_i      (ibus_data_o)
//     .m0_sel_i       (ibus_sel_o)
//     .m0_we_i        (ibus_we_o)
//     .m0_req_valid_i (ibus_req_valid_o)
//     .m0_req_ready_o (ibus_req_ready_i)
//     .m0_rsp_valid_o (ibus_rsp_valid_i)
//     .m0_rsp_ready_i (ibus_rsp_ready_o)
//     .m0_data_o      (ibus_data_i)
//   m1 = 访存总线 dbus:
//     .m1_addr_i      (dbus_addr_o)
//     .m1_data_i      (dbus_data_o)
//     .m1_sel_i       (dbus_sel_o)
//     .m1_we_i        (dbus_we_o)
//     .m1_req_valid_i (dbus_req_valid_o)
//     .m1_req_ready_o (dbus_req_ready_i)
//     .m1_rsp_valid_o (dbus_rsp_valid_i)
//     .m1_rsp_ready_i (dbus_rsp_ready_o)
//     .m1_data_o      (dbus_data_i)
//   m0/m1 只是编号: 在顶层把两组连线对调即可交换取指/访存。rib 内部对两者的
//   数据处理完全相同，只有仲裁优先级固定为 m0 高于 m1。
//
// 从设备端口(每个从设备一组，与 perips/gpio.v、perips/uart.v、perips/spi.v
// 以及存储器模型逐位对应):
//     .sN_addr_o      (slave.addr_i)        // 只保留低 28 位偏移
//     .sN_data_o      (slave.data_i)
//     .sN_sel_o       (slave.sel_i)
//     .sN_we_o        (slave.we_i)
//     .sN_req_valid_o (slave.req_valid_i)
//     .sN_req_ready_i (slave.req_ready_o)
//     .sN_rsp_valid_i (slave.rsp_valid_o)
//     .sN_rsp_ready_o (slave.rsp_ready_i)
//     .sN_data_i      (slave.data_o)
//
// 事务行为:
//   1. 空闲时按固定优先级仲裁 m0 > m1，把被授权主设备的请求送到 addr[31:28]
//      译码选中的从设备;
//   2. 请求握手(valid & ready)时锁存 owner 和目标从设备编号，进入等待响应;
//   3. 响应只回给 owner，响应数据来自锁存的目标从设备，与之后的地址无关;
//   4. 响应握手后回到空闲。
//   本模块不会在同一个时钟既接受请求又给出响应(响应至少晚一个时钟)，因此与
//   core 的 rsp_ready 时序兼容。
//
// 未命中任何从设备的地址: 不对请求握手，主设备会一直等待(本总线没有错误响应
// 通道，顶层必须保证地址落在合法区间)。
module rib(

    input wire clk,
    input wire rst_n,

    // master 0 interface (推荐接 ibus)
    input wire[31:0] m0_addr_i,          // 主设备0读、写地址
    input wire[31:0] m0_data_i,          // 主设备0写数据
    input wire[3:0] m0_sel_i,            // 主设备0字节选择
    input wire m0_we_i,                  // 主设备0写标志
    input wire m0_req_valid_i,           // 主设备0请求有效
    output wire m0_req_ready_o,          // 主设备0请求就绪
    input wire m0_rsp_ready_i,           // 主设备0响应就绪
    output wire m0_rsp_valid_o,          // 主设备0响应有效
    output wire[31:0] m0_data_o,         // 主设备0读取到的数据

    // master 1 interface (推荐接 dbus)
    input wire[31:0] m1_addr_i,          // 主设备1读、写地址
    input wire[31:0] m1_data_i,          // 主设备1写数据
    input wire[3:0] m1_sel_i,            // 主设备1字节选择
    input wire m1_we_i,                  // 主设备1写标志
    input wire m1_req_valid_i,           // 主设备1请求有效
    output wire m1_req_ready_o,          // 主设备1请求就绪
    input wire m1_rsp_ready_i,           // 主设备1响应就绪
    output wire m1_rsp_valid_o,          // 主设备1响应有效
    output wire[31:0] m1_data_o,         // 主设备1读取到的数据

    // slave 0 interface (ROM)
    output wire[31:0] s0_addr_o,
    output wire[31:0] s0_data_o,
    output wire[3:0] s0_sel_o,
    output wire s0_we_o,
    output wire s0_req_valid_o,
    input wire s0_req_ready_i,
    input wire s0_rsp_valid_i,
    output wire s0_rsp_ready_o,
    input wire[31:0] s0_data_i,

    // slave 1 interface (RAM)
    output wire[31:0] s1_addr_o,
    output wire[31:0] s1_data_o,
    output wire[3:0] s1_sel_o,
    output wire s1_we_o,
    output wire s1_req_valid_o,
    input wire s1_req_ready_i,
    input wire s1_rsp_valid_i,
    output wire s1_rsp_ready_o,
    input wire[31:0] s1_data_i,

    // slave 2 interface (Timer)
    output wire[31:0] s2_addr_o,
    output wire[31:0] s2_data_o,
    output wire[3:0] s2_sel_o,
    output wire s2_we_o,
    output wire s2_req_valid_o,
    input wire s2_req_ready_i,
    input wire s2_rsp_valid_i,
    output wire s2_rsp_ready_o,
    input wire[31:0] s2_data_i,

    // slave 3 interface (UART)
    output wire[31:0] s3_addr_o,
    output wire[31:0] s3_data_o,
    output wire[3:0] s3_sel_o,
    output wire s3_we_o,
    output wire s3_req_valid_o,
    input wire s3_req_ready_i,
    input wire s3_rsp_valid_i,
    output wire s3_rsp_ready_o,
    input wire[31:0] s3_data_i,

    // slave 4 interface (GPIO)
    output wire[31:0] s4_addr_o,
    output wire[31:0] s4_data_o,
    output wire[3:0] s4_sel_o,
    output wire s4_we_o,
    output wire s4_req_valid_o,
    input wire s4_req_ready_i,
    input wire s4_rsp_valid_i,
    output wire s4_rsp_ready_o,
    input wire[31:0] s4_data_i

    );


    // 从设备由地址最高 4 位 addr[31:28] 选择，因此基地址必须按 0xN000_0000 对齐。
    // 下面这些参数就是地址映射的唯一改动点，默认沿用上游 SoC 顶层的分配:
    //   s0 = ROM   0x0000_0000      s1 = RAM    0x1000_0000
    //   s2 = Timer 0x2000_0000      s3 = UART   0x3000_0000
    //   s4 = GPIO  0x4000_0000
    // 如需迁就本仓库 CPU 仿真基线(RAM=0x8000_0000)，把 RAM 那一档改成 4'h8 即可。
    parameter [3:0] SLAVE_0_BASE = 4'h0;
    parameter [3:0] SLAVE_1_BASE = 4'h1;
    parameter [3:0] SLAVE_2_BASE = 4'h2;
    parameter [3:0] SLAVE_3_BASE = 4'h3;
    parameter [3:0] SLAVE_4_BASE = 4'h4;

    localparam M0 = 1'b0;
    localparam M1 = 1'b1;
    localparam [2:0] S_NONE = 3'd7;

    // 未完成事务的状态
    reg busy;                    // 1: 已接受请求，正在等待响应
    reg owner;                   // 未完成事务的发起主设备
    reg[2:0] rsp_slave;          // 未完成事务的目标从设备


    // *************************** 主设备仲裁 ****************************

    // 固定优先级仲裁: m0 高于 m1。只在空闲时决定由谁发起。
    wire m0_grant = m0_req_valid_i;
    wire m1_grant = m1_req_valid_i & (~m0_grant);

    // 被授权主设备的请求信号
    wire[31:0] req_addr  = m0_grant ? m0_addr_i  : m1_addr_i;
    wire[31:0] req_wdata = m0_grant ? m0_data_i  : m1_data_i;
    wire[3:0]  req_sel   = m0_grant ? m0_sel_i   : m1_sel_i;
    wire       req_we    = m0_grant ? m0_we_i    : m1_we_i;


    // *************************** 地址译码 ******************************

    reg[2:0] dec_slave;
    always @ (*) begin
        case (req_addr[31:28])
            SLAVE_0_BASE: dec_slave = 3'd0;
            SLAVE_1_BASE: dec_slave = 3'd1;
            SLAVE_2_BASE: dec_slave = 3'd2;
            SLAVE_3_BASE: dec_slave = 3'd3;
            SLAVE_4_BASE: dec_slave = 3'd4;
            default:      dec_slave = S_NONE;
        endcase
    end

    // 空闲、有请求、且地址命中从设备时才发起一次事务
    wire launch = rst_n & (~busy) & (m0_req_valid_i | m1_req_valid_i)
                  & (dec_slave != S_NONE);

    // 从设备只看到地址低 28 位偏移，基地址在 rib 里被剥离
    wire[31:0] req_offset = {4'h0, req_addr[27:0]};


    // *********************** 从设备请求通道 ****************************

    wire s0_hit = launch & (dec_slave == 3'd0);
    wire s1_hit = launch & (dec_slave == 3'd1);
    wire s2_hit = launch & (dec_slave == 3'd2);
    wire s3_hit = launch & (dec_slave == 3'd3);
    wire s4_hit = launch & (dec_slave == 3'd4);

    assign s0_addr_o      = s0_hit ? req_offset : 32'h0;
    assign s0_data_o      = s0_hit ? req_wdata  : 32'h0;
    assign s0_sel_o       = s0_hit ? req_sel    : 4'h0;
    assign s0_we_o        = s0_hit & req_we;
    assign s0_req_valid_o = s0_hit;

    assign s1_addr_o      = s1_hit ? req_offset : 32'h0;
    assign s1_data_o      = s1_hit ? req_wdata  : 32'h0;
    assign s1_sel_o       = s1_hit ? req_sel    : 4'h0;
    assign s1_we_o        = s1_hit & req_we;
    assign s1_req_valid_o = s1_hit;

    assign s2_addr_o      = s2_hit ? req_offset : 32'h0;
    assign s2_data_o      = s2_hit ? req_wdata  : 32'h0;
    assign s2_sel_o       = s2_hit ? req_sel    : 4'h0;
    assign s2_we_o        = s2_hit & req_we;
    assign s2_req_valid_o = s2_hit;

    assign s3_addr_o      = s3_hit ? req_offset : 32'h0;
    assign s3_data_o      = s3_hit ? req_wdata  : 32'h0;
    assign s3_sel_o       = s3_hit ? req_sel    : 4'h0;
    assign s3_we_o        = s3_hit & req_we;
    assign s3_req_valid_o = s3_hit;

    assign s4_addr_o      = s4_hit ? req_offset : 32'h0;
    assign s4_data_o      = s4_hit ? req_wdata  : 32'h0;
    assign s4_sel_o       = s4_hit ? req_sel    : 4'h0;
    assign s4_we_o        = s4_hit & req_we;
    assign s4_req_valid_o = s4_hit;

    // 把被选中从设备的 req_ready 送回被授权的主设备
    reg req_ready_sel;
    always @ (*) begin
        case (dec_slave)
            3'd0:    req_ready_sel = s0_req_ready_i;
            3'd1:    req_ready_sel = s1_req_ready_i;
            3'd2:    req_ready_sel = s2_req_ready_i;
            3'd3:    req_ready_sel = s3_req_ready_i;
            3'd4:    req_ready_sel = s4_req_ready_i;
            default: req_ready_sel = 1'b0;
        endcase
    end

    assign m0_req_ready_o = m0_grant & launch & req_ready_sel;
    assign m1_req_ready_o = m1_grant & launch & req_ready_sel;

    // 请求握手(同一时刻只会有一个主设备被授权)
    wire req_fire = (m0_req_valid_i & m0_req_ready_o)
                    | (m1_req_valid_i & m1_req_ready_o);


    // *********************** 从设备响应通道 ****************************

    // 响应 valid/data 来自被锁存的 rsp_slave，而不是当前地址
    reg rsp_valid_sel;
    reg[31:0] rsp_data_sel;
    always @ (*) begin
        case (rsp_slave)
            3'd0:    begin rsp_valid_sel = s0_rsp_valid_i; rsp_data_sel = s0_data_i; end
            3'd1:    begin rsp_valid_sel = s1_rsp_valid_i; rsp_data_sel = s1_data_i; end
            3'd2:    begin rsp_valid_sel = s2_rsp_valid_i; rsp_data_sel = s2_data_i; end
            3'd3:    begin rsp_valid_sel = s3_rsp_valid_i; rsp_data_sel = s3_data_i; end
            3'd4:    begin rsp_valid_sel = s4_rsp_valid_i; rsp_data_sel = s4_data_i; end
            default: begin rsp_valid_sel = 1'b0;           rsp_data_sel = 32'h0;     end
        endcase
    end

    // 只有 owner 的 rsp_ready 会送到从设备
    wire owner_rsp_ready = (owner == M1) ? m1_rsp_ready_i : m0_rsp_ready_i;

    assign m0_rsp_valid_o = busy & (owner == M0) & rsp_valid_sel;
    assign m1_rsp_valid_o = busy & (owner == M1) & rsp_valid_sel;
    assign m0_data_o      = (busy & (owner == M0)) ? rsp_data_sel : 32'h0;
    assign m1_data_o      = (busy & (owner == M1)) ? rsp_data_sel : 32'h0;

    assign s0_rsp_ready_o = busy & (rsp_slave == 3'd0) & owner_rsp_ready;
    assign s1_rsp_ready_o = busy & (rsp_slave == 3'd1) & owner_rsp_ready;
    assign s2_rsp_ready_o = busy & (rsp_slave == 3'd2) & owner_rsp_ready;
    assign s3_rsp_ready_o = busy & (rsp_slave == 3'd3) & owner_rsp_ready;
    assign s4_rsp_ready_o = busy & (rsp_slave == 3'd4) & owner_rsp_ready;

    wire rsp_fire = busy & rsp_valid_sel & owner_rsp_ready;


    // *********************** 事务状态寄存器 ****************************

    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            owner <= M0;
            rsp_slave <= S_NONE;
        end else if (req_fire) begin
            // 请求握手时锁存事务归属，之后地址/仲裁变化都不影响响应路由
            busy <= 1'b1;
            owner <= m0_grant ? M0 : M1;
            rsp_slave <= dec_slave;
        end else if (rsp_fire) begin
            busy <= 1'b0;
        end
    end

endmodule
