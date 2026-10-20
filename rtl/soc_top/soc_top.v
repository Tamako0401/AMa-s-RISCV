// SoC 顶层: 处理器核 + RIB 总线 + 存储器
//
// 地址映射(由 rib 的 addr[31:28] 译码决定, 与 tests/cpu/link.ld、sw/link.ld 一致):
//   s0 = ROM   0x0000_0000, 64 KiB, 可选 app 区写入 -- 后 2 KiB 为引导区
//   s1 = RAM   0x1000_0000, 64 KiB, 读写 -- 数据
//   s2 = 保留(未接入)
//   s3 = 保留(未接入)
//   s4 = 外设子总线 0x4000_0000, 按 addr[15:12] 再分, 每个外设 4 KiB (rtl/core/periph_bus.v):
//          0x4000_0000: 空, 读返回 0, 写被丢弃
//          0x4000_1000  UART  -- 偏移 0/4/8/C/10: 控制/状态/分频/TX/RX
//          0x4000_2000  SPI   -- CR1 / CR2 / SR / DR, 见 docs/spi.md
//          0x4000_3000  GPIO 矩阵, 见 docs/gpio-matrix.md
//          0x4000_4000  SYSCTL -- HW_ID / ROM_WE
//          0x4000_5000 以后: 空, 读返回 0, 写被丢弃
//
// 未命中任何 rib 从设备的地址不会握手(RIB 没有错误响应通道), 访问会一直等待。
module soc_top #(
    parameter [31:0] HW_ID = 0,
    parameter ROM_WRITABLE = 0,
    parameter [31:0] RESET_PC = 32'h00000000,
    parameter ROM_INIT_FILE = "",  // ROM 初值 hex 文件, 相对仿真工作目录
    parameter RAM_INIT_FILE = "",  // RAM 初值 hex 文件, 相对仿真工作目录
    parameter CPU_CLOCK_HZ = 50000000,  // 供 UART 计算默认波特率分频
    parameter IO_N = 0,
    parameter UART_TX_PIN = 255,
    parameter UART_RX_PIN = 255
) (

    input wire clk,
    input wire rst_n,

    output wire [127:0] io_o,
    output wire [127:0] io_oe,
    input  wire [127:0] io_i

);

    // 核 <-> rib: 主设备 0 = ibus(取指), 主设备 1 = dbus(访存)
    wire [31:0] ibus_addr, ibus_data_i, ibus_data_o;
    wire [3:0] ibus_sel;
    wire ibus_we, ibus_req_valid, ibus_req_ready, ibus_rsp_valid, ibus_rsp_ready;

    wire [31:0] dbus_addr, dbus_data_i, dbus_data_o;
    wire [3:0] dbus_sel;
    wire dbus_we, dbus_req_valid, dbus_req_ready, dbus_rsp_valid, dbus_rsp_ready;

    // rib 从设备 0: ROM
    wire [31:0] s0_addr, s0_wdata, s0_rdata;
    wire [3:0] s0_sel;
    wire s0_we, s0_req_valid, s0_req_ready, s0_rsp_valid, s0_rsp_ready;

    // rib 从设备 1: RAM
    wire [31:0] s1_addr, s1_wdata, s1_rdata;
    wire [3:0] s1_sel;
    wire s1_we, s1_req_valid, s1_req_ready, s1_rsp_valid, s1_rsp_ready;

    // rib 从设备 2、3: 保留
    wire [31:0] s2_addr, s2_wdata, s3_addr, s3_wdata;
    wire [3:0] s2_sel, s3_sel;
    wire s2_we, s2_req_valid, s3_we, s3_req_valid;

    // rib 从设备 4: 外设子总线 (0x4000_0000)
    wire [31:0] s4_addr, s4_wdata, s4_rdata;
    wire [3:0] s4_sel;
    wire s4_we, s4_req_valid, s4_req_ready, s4_rsp_valid, s4_rsp_ready;

    // 子总线各口从 UART 开始; 第 k 口占 [k*32 +: 32] / [k*4 +: 4] / [k]
    localparam PERIPH_N = 4;
    localparam P_UART   = 0, P_SPI = 1, P_MATRIX = 2, P_SYSCTL = 3;
    wire [PERIPH_N*32-1:0] p_addr, p_wdata, p_rdata;
    wire [PERIPH_N*4-1:0] p_sel;
    wire [PERIPH_N-1:0] p_we, p_req_valid, p_req_ready, p_rsp_valid, p_rsp_ready;

    wire uart_tx, spi_mosi, spi_clk;
    wire matrix_uart_rx, matrix_spi_miso;
    wire rom_we;


    tinyriscv_core #(
        .RESET_PC(RESET_PC)
    ) u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .jtag_halt_i(1'b0),   // 本版本没有 JTAG
        .int_i      (8'h0),   // 本版本没有中断源

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


    rib u_rib (
        .clk  (clk),
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

        // 从设备 2 = 保留: 不握手
        .s2_addr_o(s2_addr),
        .s2_data_o(s2_wdata),
        .s2_sel_o(s2_sel),
        .s2_we_o(s2_we),
        .s2_req_valid_o(s2_req_valid),
        .s2_req_ready_i(1'b0),
        .s2_rsp_valid_i(1'b0),
        .s2_rsp_ready_o(),
        .s2_data_i(32'h0),

        // 从设备 3 = 保留: 不握手
        .s3_addr_o(s3_addr),
        .s3_data_o(s3_wdata),
        .s3_sel_o(s3_sel),
        .s3_we_o(s3_we),
        .s3_req_valid_o(s3_req_valid),
        .s3_req_ready_i(1'b0),
        .s3_rsp_valid_i(1'b0),
        .s3_rsp_ready_o(),
        .s3_data_i(32'h0),

        // 从设备 4 = 外设子总线 (0x4000_0000)
        .s4_addr_o(s4_addr),
        .s4_data_o(s4_wdata),
        .s4_sel_o(s4_sel),
        .s4_we_o(s4_we),
        .s4_req_valid_o(s4_req_valid),
        .s4_req_ready_i(s4_req_ready),
        .s4_rsp_valid_i(s4_rsp_valid),
        .s4_rsp_ready_o(s4_rsp_ready),
        .s4_data_i(s4_rdata)
    );


    // 指令存储器: 64 KiB, 深度与 tests/cpu/link.ld 的 ROM 区一致
    rom #(
        .WRITABLE(ROM_WRITABLE),
        .DP(16384),
        .ROM_INIT_FILE(ROM_INIT_FILE)
    ) u_rom (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(s0_addr),
        .data_i(s0_wdata),
        .sel_i(s0_sel),
        .we_i(s0_we),
        .we_en_i(rom_we),
        .data_o(s0_rdata),
        .req_valid_i(s0_req_valid),
        .req_ready_o(s0_req_ready),
        .rsp_valid_o(s0_rsp_valid),
        .rsp_ready_i(s0_rsp_ready)
    );


    // 数据存储器: 64 KiB, 深度与 tests/cpu/link.ld 的 RAM 区一致
    ram #(
        .DP(16384),
        .RAM_INIT_FILE(RAM_INIT_FILE)
    ) u_ram (
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


    // 外设子总线 (rib 从设备 4)
    // 保持外设 MMIO 地址不变, 同时让旧 GPIO 页落入子总线的空地址范围。
    periph_bus #(
        .N(PERIPH_N)
    ) u_periph_bus (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(s4_addr - 32'h1000),
        .data_i(s4_wdata),
        .sel_i(s4_sel),
        .we_i(s4_we),
        .data_o(s4_rdata),
        .req_valid_i(s4_req_valid),
        .req_ready_o(s4_req_ready),
        .rsp_valid_o(s4_rsp_valid),
        .rsp_ready_i(s4_rsp_ready),
        .p_addr_o(p_addr),
        .p_data_o(p_wdata),
        .p_sel_o(p_sel),
        .p_we_o(p_we),
        .p_req_valid_o(p_req_valid),
        .p_req_ready_i(p_req_ready),
        .p_rsp_valid_i(p_rsp_valid),
        .p_rsp_ready_o(p_rsp_ready),
        .p_data_i(p_rdata)
    );

    // SPI master (0x4000_2000)
    spi u_spi (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(p_addr[P_SPI*32+:32]),
        .data_i(p_wdata[P_SPI*32+:32]),
        .sel_i(p_sel[P_SPI*4+:4]),
        .we_i(p_we[P_SPI]),
        .data_o(p_rdata[P_SPI*32+:32]),
        .req_valid_i(p_req_valid[P_SPI]),
        .req_ready_o(p_req_ready[P_SPI]),
        .rsp_valid_o(p_rsp_valid[P_SPI]),
        .rsp_ready_i(p_rsp_ready[P_SPI]),
        .spi_mosi(spi_mosi),
        .spi_miso(matrix_spi_miso),
        .spi_clk(spi_clk)
    );

    // UART (0x4000_1000)
    uart #(
        .CPU_CLOCK_HZ(CPU_CLOCK_HZ)
    ) u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(p_addr[P_UART*32+:32]),
        .data_i(p_wdata[P_UART*32+:32]),
        .sel_i(p_sel[P_UART*4+:4]),
        .we_i(p_we[P_UART]),
        .data_o(p_rdata[P_UART*32+:32]),
        .req_valid_i(p_req_valid[P_UART]),
        .req_ready_o(p_req_ready[P_UART]),
        .rsp_valid_o(p_rsp_valid[P_UART]),
        .rsp_ready_i(p_rsp_ready[P_UART]),
        .tx_pin(uart_tx),
        .rx_pin(matrix_uart_rx)
    );

    gpio_matrix #(
        .IO_N(IO_N),
        .UART_TX_PIN(UART_TX_PIN),
        .UART_RX_PIN(UART_RX_PIN)
    ) u_gpio_matrix (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(p_addr[P_MATRIX*32+:32]),
        .data_i(p_wdata[P_MATRIX*32+:32]),
        .sel_i(p_sel[P_MATRIX*4+:4]),
        .we_i(p_we[P_MATRIX]),
        .data_o(p_rdata[P_MATRIX*32+:32]),
        .req_valid_i(p_req_valid[P_MATRIX]),
        .req_ready_o(p_req_ready[P_MATRIX]),
        .rsp_valid_o(p_rsp_valid[P_MATRIX]),
        .rsp_ready_i(p_rsp_ready[P_MATRIX]),
        .io_o(io_o),
        .io_oe(io_oe),
        .io_i(io_i),
        .uart_tx_i(uart_tx),
        .uart_rx_o(matrix_uart_rx),
        .spi_sck_i(spi_clk),
        .spi_mosi_i(spi_mosi),
        .spi_miso_o(matrix_spi_miso)
    );

    sysctl #(
        .HW_ID(HW_ID)
    ) u_sysctl (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(p_addr[P_SYSCTL*32+:32]),
        .data_i(p_wdata[P_SYSCTL*32+:32]),
        .sel_i(p_sel[P_SYSCTL*4+:4]),
        .we_i(p_we[P_SYSCTL]),
        .data_o(p_rdata[P_SYSCTL*32+:32]),
        .req_valid_i(p_req_valid[P_SYSCTL]),
        .req_ready_o(p_req_ready[P_SYSCTL]),
        .rsp_valid_o(p_rsp_valid[P_SYSCTL]),
        .rsp_ready_i(p_rsp_ready[P_SYSCTL]),
        .rom_we(rom_we)
    );

endmodule
