// SoC 顶层: 处理器核 + RIB 总线 + 存储器
//
// 地址映射(由 rib 的 addr[31:28] 译码决定, 与 tests/cpu/link.ld、sw/link.ld 一致):
//   s0 = ROM 0x0000_0000, 64 KiB, 只读  -- 指令和常量; 也是复位向量
//   s1 = RAM 0x1000_0000, 64 KiB, 读写  -- 数据
//   s2 / s3 / s4 = 保留(未接入)
//
// 为什么 s2~s4 还空着:
//   - perips/uart.v、perips/gpio.v 的 valid/ready 接口本可直接挂上去, 但引脚
//     (UART tx/rx、GPIO 输入输出) 和时钟参数要按具体板卡定;
//   - perips/spi.v 还是旧式接口(没有 req_valid/req_ready/rsp_valid/rsp_ready),
//     必须先写一层总线包装才能挂到 RIB 上;
//   - 本仓库没有 timer。
// 因此本版本只做 "核 + 总线 + 存储器" 的闭环, 外设留到下一步。
//
// 保留槽位的访问行为: req_ready 恒为 0, 即不握手。这与 "地址未命中任何从设备"
// 的行为一致(RIB 没有错误响应通道), 访问会一直等待。
module soc_top #(
    parameter [31:0] RESET_PC = 32'h00000000,
    parameter ROM_INIT_FILE = ""            // ROM 初值 hex 文件, 相对仿真工作目录
)(

    input wire clk,
    input wire rst_n

    );

    // 核 <-> rib: 主设备 0 = ibus(取指), 主设备 1 = dbus(访存)
    wire[31:0] ibus_addr, ibus_data_i, ibus_data_o;
    wire[3:0] ibus_sel;
    wire ibus_we, ibus_req_valid, ibus_req_ready, ibus_rsp_valid, ibus_rsp_ready;

    wire[31:0] dbus_addr, dbus_data_i, dbus_data_o;
    wire[3:0] dbus_sel;
    wire dbus_we, dbus_req_valid, dbus_req_ready, dbus_rsp_valid, dbus_rsp_ready;

    // rib 从设备 0: ROM
    wire[31:0] s0_addr, s0_wdata, s0_rdata;
    wire[3:0] s0_sel;
    wire s0_we, s0_req_valid, s0_req_ready, s0_rsp_valid, s0_rsp_ready;

    // rib 从设备 1: RAM
    wire[31:0] s1_addr, s1_wdata, s1_rdata;
    wire[3:0] s1_sel;
    wire s1_we, s1_req_valid, s1_req_ready, s1_rsp_valid, s1_rsp_ready;

    // rib 从设备 2~4: 保留, 未接入任何设备
    wire[31:0] s2_addr, s2_wdata, s3_addr, s3_wdata, s4_addr, s4_wdata;
    wire[3:0] s2_sel, s3_sel, s4_sel;
    wire s2_we, s3_we, s4_we, s2_req_valid, s3_req_valid, s4_req_valid;


    tinyriscv_core #(
        .RESET_PC(RESET_PC)
    ) u_core(
        .clk(clk),
        .rst_n(rst_n),
        .jtag_halt_i(1'b0),                 // 本版本没有 JTAG
        .int_i(8'h0),                       // 本版本没有中断源

        .ibus_addr_o(ibus_addr),
        .ibus_data_i(ibus_data_i),
        .ibus_data_o(ibus_data_o),
        .ibus_sel_o(ibus_sel),
        .ibus_we_o(ibus_we),
        .ibus_req_valid_o(ibus_req_valid),
        .ibus_req_ready_i(ibus_req_ready),
        .ibus_rsp_valid_i(ibus_rsp_valid),
        .ibus_rsp_ready_o(ibus_rsp_ready),

        .dbus_addr_o(dbus_addr),
        .dbus_data_i(dbus_data_i),
        .dbus_data_o(dbus_data_o),
        .dbus_sel_o(dbus_sel),
        .dbus_we_o(dbus_we),
        .dbus_req_valid_o(dbus_req_valid),
        .dbus_req_ready_i(dbus_req_ready),
        .dbus_rsp_valid_i(dbus_rsp_valid),
        .dbus_rsp_ready_o(dbus_rsp_ready)
    );


    rib u_rib(
        .clk(clk),
        .rst_n(rst_n),

        // 主设备 0 = ibus
        .m0_addr_i(ibus_addr),
        .m0_data_i(ibus_data_o),
        .m0_sel_i(ibus_sel),
        .m0_we_i(ibus_we),
        .m0_req_valid_i(ibus_req_valid),
        .m0_req_ready_o(ibus_req_ready),
        .m0_rsp_ready_i(ibus_rsp_ready),
        .m0_rsp_valid_o(ibus_rsp_valid),
        .m0_data_o(ibus_data_i),

        // 主设备 1 = dbus
        .m1_addr_i(dbus_addr),
        .m1_data_i(dbus_data_o),
        .m1_sel_i(dbus_sel),
        .m1_we_i(dbus_we),
        .m1_req_valid_i(dbus_req_valid),
        .m1_req_ready_o(dbus_req_ready),
        .m1_rsp_ready_i(dbus_rsp_ready),
        .m1_rsp_valid_o(dbus_rsp_valid),
        .m1_data_o(dbus_data_i),

        // 从设备 0 = ROM (0x0000_0000)
        .s0_addr_o(s0_addr),
        .s0_data_o(s0_wdata),
        .s0_sel_o(s0_sel),
        .s0_we_o(s0_we),
        .s0_req_valid_o(s0_req_valid),
        .s0_req_ready_i(s0_req_ready),
        .s0_rsp_valid_i(s0_rsp_valid),
        .s0_rsp_ready_o(s0_rsp_ready),
        .s0_data_i(s0_rdata),

        // 从设备 1 = RAM (0x1000_0000)
        .s1_addr_o(s1_addr),
        .s1_data_o(s1_wdata),
        .s1_sel_o(s1_sel),
        .s1_we_o(s1_we),
        .s1_req_valid_o(s1_req_valid),
        .s1_req_ready_i(s1_req_ready),
        .s1_rsp_valid_i(s1_rsp_valid),
        .s1_rsp_ready_o(s1_rsp_ready),
        .s1_data_i(s1_rdata),

        // 从设备 2~4 = 保留: 不握手, 将来在这里挂 timer / uart / gpio
        .s2_addr_o(s2_addr),
        .s2_data_o(s2_wdata),
        .s2_sel_o(s2_sel),
        .s2_we_o(s2_we),
        .s2_req_valid_o(s2_req_valid),
        .s2_req_ready_i(1'b0),
        .s2_rsp_valid_i(1'b0),
        .s2_rsp_ready_o(),
        .s2_data_i(32'h0),

        .s3_addr_o(s3_addr),
        .s3_data_o(s3_wdata),
        .s3_sel_o(s3_sel),
        .s3_we_o(s3_we),
        .s3_req_valid_o(s3_req_valid),
        .s3_req_ready_i(1'b0),
        .s3_rsp_valid_i(1'b0),
        .s3_rsp_ready_o(),
        .s3_data_i(32'h0),

        .s4_addr_o(s4_addr),
        .s4_data_o(s4_wdata),
        .s4_sel_o(s4_sel),
        .s4_we_o(s4_we),
        .s4_req_valid_o(s4_req_valid),
        .s4_req_ready_i(1'b0),
        .s4_rsp_valid_i(1'b0),
        .s4_rsp_ready_o(),
        .s4_data_i(32'h0)
    );


    // 指令存储器: 64 KiB, 深度与 tests/cpu/link.ld 的 ROM 区一致
    rom #(
        .DP(16384),
        .ROM_INIT_FILE(ROM_INIT_FILE)
    ) u_rom(
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(s0_addr),
        .data_i(s0_wdata),
        .sel_i(s0_sel),
        .we_i(s0_we),
        .data_o(s0_rdata),
        .req_valid_i(s0_req_valid),
        .req_ready_o(s0_req_ready),
        .rsp_valid_o(s0_rsp_valid),
        .rsp_ready_i(s0_rsp_ready)
    );


    // 数据存储器: 64 KiB, 深度与 tests/cpu/link.ld 的 RAM 区一致
    ram #(
        .DP(16384)
    ) u_ram(
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(s1_addr),
        .data_i(s1_wdata),
        .sel_i(s1_sel),
        .we_i(s1_we),
        .data_o(s1_rdata),
        .req_valid_i(s1_req_valid),
        .req_ready_o(s1_req_ready),
        .rsp_valid_o(s1_rsp_valid),
        .rsp_ready_i(s1_rsp_ready)
    );

endmodule
