// SoC 顶层: 处理器核 + RIB 总线 + 存储器
//
// 取指: CPU 的 ibus 直接接 ROM 的取指口, 不经过 rib, 取指和数据访问同拍进行、
//       互不阻塞。因此指令必须位于 ROM 窗口(0x0000_0000 起 64 KiB); 这是严格
//       哈佛式划分, soc_top 不支持从 RAM 取指。
//
// 数据: CPU 的 dbus 是 rib 的主设备 1。rib 主设备 0 保留未用。从设备由 addr[31:28]
//       译码, 与 tests/cpu/link.ld、sw/link.ld 一致:
//   s0 = ROM   0x0000_0000, 64 KiB, 可选 app 区写入 -- 后 2 KiB 为引导区
//   s1 = RAM   0x1000_0000, 64 KiB, 读写 -- 数据
//   s2 = 视频  0x2000_0000, 寄存器和显存, 见 docs/video.md; 小窗读视觉输入 (u_vision, docs/vision.md)
//   s3 = 新显示 0x3000_0000, 见 docs/display.md; DISPLAY_NEW=1 才接 (0 时保留, 访问会挂起)
//   s4 = 外设子总线 0x4000_0000, 按 addr[15:12] 再分, 每个外设 4 KiB (rtl/core/periph_bus.v):
//          0x4000_0000: 空, 读返回 0, 写被丢弃
//          0x4000_1000  UART  -- 偏移 0/4/8/C/10: 控制/状态/分频/TX/RX
//          0x4000_2000  SPI   -- CR1 / CR2 / SR / DR, 见 docs/spi.md
//          0x4000_3000  GPIO 矩阵, 见 docs/gpio-matrix.md
//          0x4000_4000  SYSCTL -- HW_ID / ROM_WE
//          0x4000_5000  视觉输入 -- 颜色跟踪, 见 docs/vision.md (u_vision)
//          0x4000_6000  handnet 加速器, 见 docs/nn.md (u_nn)
//          0x4000_7000  UART2 -- 同 UART, 收发脚由 GPIO 矩阵选 (上电不接)
//          0x4000_8000  声音 -- 方波 + 噪声声道, I2S 输出经 GPIO 矩阵, 见 docs/audio.md
//          0x4000_9000 以后: 空, 读返回 0, 写被丢弃
//
// 未命中任何 rib 从设备的地址不会握手(RIB 没有错误响应通道), 访问会一直等待。
module soc_top #(
    parameter [31:0] HW_ID = 0,
    parameter ROM_WRITABLE = 0,
    parameter [31:0] RESET_PC = 32'h00000000,
    parameter ROM_INIT_FILE = "",  // ROM 初值 hex 文件, 相对仿真工作目录
    parameter RAM_INIT_FILE = "",  // RAM 初值 hex 文件, 相对仿真工作目录
    parameter CPU_CLOCK_HZ = 50000000,  // 供 UART 计算默认波特率分频
    parameter VIDEO_720P = 0,
    parameter DISPLAY_NEW = 0,  // 1 = s3 接新显示, 视频输出口和小窗读改由它驱动 (旧 video 留在 s2, 改回 0 退回); 要 video_clk (74.25 MHz)
    parameter NN = 1,  // 0 = 不综合 handnet 加速器 (它占约 108/134 块 DRM18K); 用 PGL50H 这类小片子时关掉, 0x4000_6000 变成不握手
    parameter IO_N = 0,
    parameter UART_TX_PIN = 255,
    parameter UART_RX_PIN = 255
) (

    input wire clk,
    input wire rst_n,

    output wire [127:0] io_o,
    output wire [127:0] io_oe,
    input  wire [127:0] io_i,

    input wire video_clk,  // 720p 像素时钟; VGA 模式不用; DISPLAY_NEW 时兼作新显示的 pclk

    // 视频输出 (VGA / 720p), 板子不接就留空
    output wire video_pclk,
    output wire video_hsync_n,
    output wire video_vsync_n,
    output wire video_de,
    output wire [23:0] video_rgb,

    // 视觉输入 (HDMI 接收芯片的并行口), 板子不接就接 0
    input wire vin_pclk,
    input wire vin_de,
    input wire [23:0] vin_rgb

);

    // 取指: ibus 直连 ROM 的取指口, 不经过 rib
    wire [31:0] ibus_addr, ibus_data_i;
    wire ibus_req_valid, ibus_req_ready, ibus_rsp_valid, ibus_rsp_ready;

    // ROM 取指口
    wire [31:0] rom_i_data;
    wire rom_i_req_ready, rom_i_rsp_valid;

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

    // rib 从设备 2: 视频
    wire [31:0] s2_addr, s2_wdata, s2_rdata;
    wire [3:0] s2_sel;
    wire s2_we, s2_req_valid, s2_req_ready, s2_rsp_valid, s2_rsp_ready;

    // rib 从设备 3: 新显示 (DISPLAY_NEW=1 才接, 例化在下面 generate 里; 0 时保留不握手)
    wire [31:0] s3_addr, s3_wdata, s3_rdata;
    wire [3:0] s3_sel;
    wire s3_we, s3_req_valid, s3_req_ready, s3_rsp_valid, s3_rsp_ready;

    // rib 从设备 4: 外设子总线 (0x4000_0000)
    wire [31:0] s4_addr, s4_wdata, s4_rdata;
    wire [3:0] s4_sel;
    wire s4_we, s4_req_valid, s4_req_ready, s4_rsp_valid, s4_rsp_ready;

    // 子总线各口从 UART 开始; 第 k 口占 [k*32 +: 32] / [k*4 +: 4] / [k]
    localparam PERIPH_N = 8;
    localparam P_UART   = 0, P_SPI = 1, P_MATRIX = 2, P_SYSCTL = 3, P_VISION = 4, P_NN = 5, P_UART2 = 6, P_AUDIO = 7;
    wire [PERIPH_N*32-1:0] p_addr, p_wdata, p_rdata;
    wire [PERIPH_N*4-1:0] p_sel;
    wire [PERIPH_N-1:0] p_we, p_req_valid, p_req_ready, p_rsp_valid, p_rsp_ready;

    wire uart_tx, spi_mosi, spi_clk, uart2_tx;
    wire matrix_uart_rx, matrix_spi_miso, matrix_uart2_rx;
    wire i2s_bclk, i2s_lrck, i2s_dout;
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
        .ibus_data_o(),
        .ibus_sel_o(),
        .ibus_we_o(),
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

        // 主设备 0 保留未用: 取指已直连 ROM 的取指口
        .m0_addr_i(32'h0),
        .m0_data_i(32'h0),
        .m0_sel_i(4'h0),
        .m0_we_i(1'b0),
        .m0_req_valid_i(1'b0),
        .m0_req_ready_o(),
        .m0_rsp_ready_i(1'b0),
        .m0_rsp_valid_o(),
        .m0_data_o(),

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

        // 从设备 2 = 视频 (0x2000_0000)
        .s2_addr_o(s2_addr),
        .s2_data_o(s2_wdata),
        .s2_sel_o(s2_sel),
        .s2_we_o(s2_we),
        .s2_req_valid_o(s2_req_valid),
        .s2_req_ready_i(s2_req_ready),
        .s2_rsp_valid_i(s2_rsp_valid),
        .s2_rsp_ready_o(s2_rsp_ready),
        .s2_data_i(s2_rdata),

        // 从设备 3 = 新显示 (0x3000_0000); DISPLAY_NEW=0 时 req_ready/rsp_valid 在下面 generate 里接地
        .s3_addr_o(s3_addr),
        .s3_data_o(s3_wdata),
        .s3_sel_o(s3_sel),
        .s3_we_o(s3_we),
        .s3_req_valid_o(s3_req_valid),
        .s3_req_ready_i(s3_req_ready),
        .s3_rsp_valid_i(s3_rsp_valid),
        .s3_rsp_ready_o(s3_rsp_ready),
        .s3_data_i(s3_rdata),

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


    // 取指口直连 ibus: 取指不再和 dbus 抢 rib
    assign ibus_req_ready = rom_i_req_ready;
    assign ibus_rsp_valid = rom_i_rsp_valid;
    assign ibus_data_i = rom_i_data;

    // 指令存储器: 64 KiB, 深度与 tests/cpu/link.ld 的 ROM 区一致
    // 数据口接 rib 从设备 0(读 rodata、bootloader 写), 取指口接 ibus
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
        .rsp_ready_i(s0_rsp_ready),
        .i_addr_i(ibus_addr),
        .i_data_o(rom_i_data),
        .i_req_valid_i(ibus_req_valid),
        .i_req_ready_o(rom_i_req_ready),
        .i_rsp_valid_o(rom_i_rsp_valid),
        .i_rsp_ready_i(ibus_rsp_ready)
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


    // 旧显示 (s2)。输出口和小窗读地址先落在 vid_*, 由 DISPLAY_NEW 在下面 generate 里决定谁上引脚
    wire vid_pclk, vid_hsync_n, vid_vsync_n, vid_de;
    wire [23:0] vid_rgb;
    wire [14:0] vid_win_raddr;
    wire [14:0] win_raddr;
    wire [ 7:0] win_rdata;
    reg vga_clk;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) vga_clk <= 0;
        else vga_clk <= ~vga_clk;
    wire scan_clk = VIDEO_720P ? video_clk : vga_clk;
    video #(.MODE_720P(VIDEO_720P)) u_video (
        .pix_clk(scan_clk),
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(s2_addr),
        .data_i(s2_wdata),
        .sel_i(s2_sel),
        .we_i(s2_we),
        .data_o(s2_rdata),
        .req_valid_i(s2_req_valid),
        .req_ready_o(s2_req_ready),
        .rsp_valid_o(s2_rsp_valid),
        .rsp_ready_i(s2_rsp_ready),
        .pclk(vid_pclk),
        .hsync_n(vid_hsync_n),
        .vsync_n(vid_vsync_n),
        .de(vid_de),
        .rgb(vid_rgb),
        .win_raddr(vid_win_raddr),
        .win_rdata(win_rdata)
    );

    // 新显示 (rtl/display, docs/display.md): DISPLAY_NEW=1 时挂 rib s3 (0x3000_0000), 视频输出口和小窗改由它驱动。
    // 两个引擎不能同时上: vision 的小窗读口 (win_raddr/win_rclk) 和对外引脚只有一套, 参数固定选一路, 综合只留选中的。
    // 新显示在 clk 域读小窗 (display.v), 所以 DISPLAY_NEW 时 vision 的读时钟也切到 clk (旧 video 在扫描时钟读)。
    generate
        if (DISPLAY_NEW) begin : gen_display
            wire dsp_pclk, dsp_hsync_n, dsp_vsync_n, dsp_de;
            wire [23:0] dsp_rgb;
            wire [14:0] dsp_win_raddr;

            display u_display (
                .clk        (clk),
                .rst_n      (rst_n),
                .addr_i     (s3_addr),
                .data_i     (s3_wdata),
                .sel_i      (s3_sel),
                .we_i       (s3_we),
                .data_o     (s3_rdata),
                .req_valid_i(s3_req_valid),
                .req_ready_o(s3_req_ready),
                .rsp_valid_o(s3_rsp_valid),
                .rsp_ready_i(s3_rsp_ready),
                .pclk       (video_clk),
                .pclk_o     (dsp_pclk),
                .hsync_n    (dsp_hsync_n),
                .vsync_n    (dsp_vsync_n),
                .de         (dsp_de),
                .rgb        (dsp_rgb),
                .win_raddr  (dsp_win_raddr),
                .win_rdata  (win_rdata)
            );

            assign video_pclk = dsp_pclk;
            assign video_hsync_n = dsp_hsync_n;
            assign video_vsync_n = dsp_vsync_n;
            assign video_de = dsp_de;
            assign video_rgb = dsp_rgb;
            assign win_raddr = dsp_win_raddr;
        end else begin : gen_no_display
            // s3 保留: 不握手 (和没接新显示之前一样)
            assign s3_req_ready = 1'b0;
            assign s3_rsp_valid = 1'b0;
            assign s3_rdata = 32'h0;

            assign video_pclk = vid_pclk;
            assign video_hsync_n = vid_hsync_n;
            assign video_vsync_n = vid_vsync_n;
            assign video_de = vid_de;
            assign video_rgb = vid_rgb;
            assign win_raddr = vid_win_raddr;
        end
    endgenerate
    wire win_rclk = DISPLAY_NEW ? clk : scan_clk;  // vision 的小窗读口跟着被选中的引擎走

    wire nn_valid, nn_sof, nn_eol, nn_boundary, nn_commit;
    wire [23:0] nn_data;
    vision u_vision (
        .nn_valid(nn_valid), .nn_sof(nn_sof), .nn_eol(nn_eol), .nn_data(nn_data),
        .nn_boundary(nn_boundary), .nn_commit(nn_commit),
        .win_rclk(win_rclk),
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(p_addr[P_VISION*32+:32]),
        .data_i(p_wdata[P_VISION*32+:32]),
        .sel_i(p_sel[P_VISION*4+:4]),
        .we_i(p_we[P_VISION]),
        .data_o(p_rdata[P_VISION*32+:32]),
        .req_valid_i(p_req_valid[P_VISION]),
        .req_ready_o(p_req_ready[P_VISION]),
        .rsp_valid_o(p_rsp_valid[P_VISION]),
        .rsp_ready_i(p_rsp_ready[P_VISION]),
        .vin_pclk(vin_pclk),
        .vin_de(vin_de),
        .vin_rgb(vin_rgb),
        .win_raddr(win_raddr),
        .win_rdata(win_rdata)
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

    // UART2 (0x4000_7000): 第二个串口, 和控制台串口同一个模块; 以后接 WS63 星闪
    uart #(
        .CPU_CLOCK_HZ(CPU_CLOCK_HZ)
    ) u_uart2 (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(p_addr[P_UART2*32+:32]),
        .data_i(p_wdata[P_UART2*32+:32]),
        .sel_i(p_sel[P_UART2*4+:4]),
        .we_i(p_we[P_UART2]),
        .data_o(p_rdata[P_UART2*32+:32]),
        .req_valid_i(p_req_valid[P_UART2]),
        .req_ready_o(p_req_ready[P_UART2]),
        .rsp_valid_o(p_rsp_valid[P_UART2]),
        .rsp_ready_i(p_rsp_ready[P_UART2]),
        .tx_pin(uart2_tx),
        .rx_pin(matrix_uart2_rx)
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
        .spi_miso_o(matrix_spi_miso),
        .uart2_tx_i(uart2_tx),
        .uart2_rx_o(matrix_uart2_rx),
        .i2s_bclk_i(i2s_bclk),
        .i2s_lrck_i(i2s_lrck),
        .i2s_dout_i(i2s_dout)
    );

    // 声音 (0x4000_8000): I2S 三根线经 GPIO 矩阵接到功放
    audio u_audio (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(p_addr[P_AUDIO*32+:32]),
        .data_i(p_wdata[P_AUDIO*32+:32]),
        .sel_i(p_sel[P_AUDIO*4+:4]),
        .we_i(p_we[P_AUDIO]),
        .data_o(p_rdata[P_AUDIO*32+:32]),
        .req_valid_i(p_req_valid[P_AUDIO]),
        .req_ready_o(p_req_ready[P_AUDIO]),
        .rsp_valid_o(p_rsp_valid[P_AUDIO]),
        .rsp_ready_i(p_rsp_ready[P_AUDIO]),
        .bclk(i2s_bclk),
        .lrck(i2s_lrck),
        .dout(i2s_dout)
    );

    // handnet 加速器 (0x4000_6000); NN=0 时整个加速器不综合, 这一口保留不握手 (同 DISPLAY_NEW=0 时 s3 的做法)
    generate
        if (NN) begin : g_nn
            nn u_nn (
                .vin_pclk(vin_pclk), .vin_valid(nn_valid), .vin_sof(nn_sof), .vin_eol(nn_eol),
                .vin_data(nn_data), .vin_boundary(nn_boundary), .vin_commit(nn_commit),
                .clk(clk),
                .rst_n(rst_n),
                .addr_i(p_addr[P_NN*32+:32]),
                .data_i(p_wdata[P_NN*32+:32]),
                .sel_i(p_sel[P_NN*4+:4]),
                .we_i(p_we[P_NN]),
                .data_o(p_rdata[P_NN*32+:32]),
                .req_valid_i(p_req_valid[P_NN]),
                .req_ready_o(p_req_ready[P_NN]),
                .rsp_valid_o(p_rsp_valid[P_NN]),
                .rsp_ready_i(p_rsp_ready[P_NN]),
                .busy_o(),
                .done_o()
            );
        end else begin : g_no_nn
            assign p_rdata[P_NN*32+:32] = 32'h0;
            assign p_req_ready[P_NN] = 1'b0;
            assign p_rsp_valid[P_NN] = 1'b0;
        end
    endgenerate

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
