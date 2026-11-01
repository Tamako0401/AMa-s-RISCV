`include "boards/mes2l100hp/pins_top.vh"
module mes2l100hp_top #(
    parameter [31:0] HW_ID = 0,
    parameter BREAK_CYCLES = 500000,
    parameter VIDEO_720P = 1,
    // 1 = 画面由新显示 (rtl/display, rib s3) 出; 0 = 旧 video (s2, 现有 demo 用它)。
    // 置 1 能综合、时序满足 (PDS 2022.2-SP6.4 的段错误已在 disp_blend 绕过, 资源和时序见 docs/display.md);
    // 默认还是 0: 新显示的 C 后端还没写, 现有 demo 都画在旧 video 上。
    parameter DISPLAY_NEW = 0,
    parameter NN = 1,  // 传给 soc_top: 0 = 不综合 handnet 加速器
    parameter IO_N = `IO_N,
    parameter MEM_FILE = "firmware.hex"
) (
    input wire clk,  // 板载 27 MHz 晶振 (D18)
    input wire key1_n,
    inout wire [IO_N-1:0] io,
    // HDMI 发送芯片 MS7210 的视频口 (配置口在 io 里, 见 sw/bsp/board_hdmi.h;
    // 本板 MS7210 和 MS7200 共用一条 I2C 和一个复位脚)
    output wire hdmi_pclk,
    output wire hdmi_hs,
    output wire hdmi_vs,
    output wire hdmi_de,
    output wire [23:0] hdmi_d,  // {R, G, B}
    // HDMI 接收芯片 MS7200 的视频口 (配置口同上)
    input wire hdmi_rx_pclk,
    input wire hdmi_rx_de,
    input wire [23:0] hdmi_rx_d  // {R, G, B}
);
    // 27 MHz 晶振经 GPLL 倍频出 50 MHz 系统时钟 (同 ego1 的 MMCM 做法, 原语直接内联)。
    // 参数语义 (厂商例程 2_5_pll_test 反推, 输出 54/81 MHz 验证过):
    //   VCO = clk_in × RATIOM × RATIOF / RATIOI = 27 × 1 × 25 / 1 = 675 MHz (datasheet 边界 600~1200)
    //   clkout0 = VCO / RATIO0 = 675 / 13.5 = 50 MHz (RATIO0 支持 0.5 步进, 例程用了 19.5)
    wire sys_clk, pll_lock;
`ifdef VERILATOR
    // 仿真不模拟 PLL 的模拟行为, 直接旁路: 测试台给 50 MHz, 恒认为已锁定。
    // (Icarus 用户可加 +define+VERILATOR 走这条路)
    assign sys_clk = clk;
    assign pll_lock = 1'b1;
`else
    GTP_GPLL #(
        .CLKIN_FREQ(27.0),
        .LOCK_MODE(0),
        .STATIC_RATIOI(1),
        .STATIC_RATIOM(1),
        .STATIC_RATIO0(13.5),
        .STATIC_RATIO1(13),
        .STATIC_RATIO2(13),
        .STATIC_RATIO3(21),
        .STATIC_RATIO4(21),
        .STATIC_RATIO5(21),
        .STATIC_RATIO6(21),
        .STATIC_RATIOF(25.0),
        .STATIC_DUTY0(13),
        .STATIC_DUTY1(13),
        .STATIC_DUTY2(13),
        .STATIC_DUTY3(21),
        .STATIC_DUTY4(21),
        .STATIC_DUTY5(21),
        .STATIC_DUTY6(21),
        .STATIC_DUTYF(25),
        .STATIC_PHASE(0),
        .STATIC_PHASE0(0),
        .STATIC_PHASE1(0),
        .STATIC_PHASE2(0),
        .STATIC_PHASE3(0),
        .STATIC_PHASE4(0),
        .STATIC_PHASE5(0),
        .STATIC_PHASE6(0),
        .STATIC_PHASEF(0),
        .STATIC_CPHASE0(0),
        .STATIC_CPHASE1(0),
        .STATIC_CPHASE2(0),
        .STATIC_CPHASE3(0),
        .STATIC_CPHASE4(0),
        .STATIC_CPHASE5(0),
        .STATIC_CPHASE6(0),
        .STATIC_CPHASEF(0),
        .CLK_DPS0_EN("FALSE"),
        .CLK_DPS1_EN("FALSE"),
        .CLK_DPS2_EN("FALSE"),
        .CLK_DPS3_EN("FALSE"),
        .CLK_DPS4_EN("FALSE"),
        .CLK_DPS5_EN("FALSE"),
        .CLK_DPS6_EN("FALSE"),
        .CLK_DPSF_EN("FALSE"),
        .CLK_CAS5_EN("FALSE"),
        .CLKOUT0_SYN_EN("FALSE"),
        .CLKOUT1_SYN_EN("FALSE"),
        .CLKOUT2_SYN_EN("FALSE"),
        .CLKOUT3_SYN_EN("FALSE"),
        .CLKOUT4_SYN_EN("FALSE"),
        .CLKOUT5_SYN_EN("FALSE"),
        .CLKOUT6_SYN_EN("FALSE"),
        .CLKOUTF_SYN_EN("FALSE"),
        .SSC_MODE("DISABLE"),
        .SSC_FREQ(25),
        .INTERNAL_FB("CLKOUTF"),
        .EXTERNAL_FB("DISABLE"),
        .BANDWIDTH("OPTIMIZED")
    ) u_gpll (
        .CLKOUT0(sys_clk),
        .CLKOUT0N(),
        .CLKOUT1(),
        .CLKOUT1N(),
        .CLKOUT2(),
        .CLKOUT2N(),
        .CLKOUT3(),
        .CLKOUT3N(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKOUTF(),
        .CLKOUTFN(),
        .LOCK(pll_lock),
        .DPS_DONE(),
        .DPS_CLK(1'b0),
        .DPS_EN(1'b0),
        .DPS_DIR(1'b0),
        .CLKIN1(clk),
        .CLKIN2(1'b0),
        .CLKFB(1'b0),
        .CLKIN_SEL(1'b0),
        .CLKOUT0_SYN(1'b0),
        .CLKOUT1_SYN(1'b0),
        .CLKOUT2_SYN(1'b0),
        .CLKOUT3_SYN(1'b0),
        .CLKOUT4_SYN(1'b0),
        .CLKOUT5_SYN(1'b0),
        .CLKOUT6_SYN(1'b0),
        .CLKOUTF_SYN(1'b0),
        .PLL_PWD(1'b0),
        .RST(1'b0),
        .APB_RDATA(),
        .APB_READY(),
        .APB_CLK(1'b0),
        .APB_RST_N(1'b0),
        .APB_ADDR(5'b0),
        .APB_SEL(1'b0),
        .APB_EN(1'b0),
        .APB_WRITE(1'b0),
        .APB_WDATA(16'b0)
    );
`endif
    // 不用系统复位清计数器, 否则 break 会被自身复位打断。
    reg [1:0] rx_sync = 2'b11;
    reg [$clog2(BREAK_CYCLES+1)-1:0] break_count = 0;
    reg in_break = 0;       // 寄存器输出再去拉复位: 计数比较的组合输出会有毛刺, 不能直接接异步复位
    always @(posedge sys_clk) begin
        rx_sync <= {rx_sync[0], io[`UART_RX_PIN]};
        if (rx_sync[1]) break_count <= 0;
        else if (break_count < BREAK_CYCLES) break_count <= break_count + 1'b1;
        in_break <= !rx_sync[1] && break_count == BREAK_CYCLES;
    end
    wire reset_n = (key1_n && pll_lock) && !in_break;
    reg [15:0] reset_pipe = 16'b0;
    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n) reset_pipe <= 16'b0;
        else reset_pipe <= {reset_pipe[14:0], 1'b1};
    end
    localparam [127:0] INOUT_MASK = `IO_INOUT_MASK;
    localparam [127:0] OUT_MASK   = `IO_OUT_MASK;
    localparam [127:0] IN_N_MASK  = `IO_IN_N_MASK;
    wire [127:0] io_o, io_oe, io_i;
    genvar n;
    generate
        for (n = 0; n < IO_N; n = n + 1) begin : g_pins
            if (INOUT_MASK[n]) begin : g_inout
                assign io[n] = io_oe[n] ? io_o[n] : 1'bz;
            end else if (OUT_MASK[n]) begin : g_output
                assign io[n] = io_o[n];
            end
            assign io_i[n] = IN_N_MASK[n] ? ~io[n] : io[n];
        end
    endgenerate
    assign io_i[127:IO_N] = 0;
    // 720p 像素时钟 74.25 MHz 和 50 MHz 要不同的 VCO (891 vs 675), 用第二个 GPLL:
    //   VCO = 27 × 1 × 33 / 1 = 891 MHz, clkout0 = 891 / 12 = 74.25 MHz
    // 不放进 generate: fdc 按 u_video_gpll/CLKOUT0 定义派生时钟, 实例路径要固定。VGA 时输出没人用, 综合会删掉它。
    wire video_pll_clk, video_pll_locked;
`ifdef VERILATOR
    reg pixel = 0;
    always #6.734006734 pixel = ~pixel;
    assign video_pll_clk = pixel;
    assign video_pll_locked = 1'b1;
`else
    GTP_GPLL #(
        .CLKIN_FREQ(27.0),
        .LOCK_MODE(0),
        .STATIC_RATIOI(1),
        .STATIC_RATIOM(1),
        .STATIC_RATIO0(12),
        .STATIC_RATIO1(13),
        .STATIC_RATIO2(13),
        .STATIC_RATIO3(21),
        .STATIC_RATIO4(21),
        .STATIC_RATIO5(21),
        .STATIC_RATIO6(21),
        .STATIC_RATIOF(33.0),
        .STATIC_DUTY0(12),
        .STATIC_DUTY1(13),
        .STATIC_DUTY2(13),
        .STATIC_DUTY3(21),
        .STATIC_DUTY4(21),
        .STATIC_DUTY5(21),
        .STATIC_DUTY6(21),
        .STATIC_DUTYF(33),
        .STATIC_PHASE(0),
        .STATIC_PHASE0(0),
        .STATIC_PHASE1(0),
        .STATIC_PHASE2(0),
        .STATIC_PHASE3(0),
        .STATIC_PHASE4(0),
        .STATIC_PHASE5(0),
        .STATIC_PHASE6(0),
        .STATIC_PHASEF(0),
        .STATIC_CPHASE0(0),
        .STATIC_CPHASE1(0),
        .STATIC_CPHASE2(0),
        .STATIC_CPHASE3(0),
        .STATIC_CPHASE4(0),
        .STATIC_CPHASE5(0),
        .STATIC_CPHASE6(0),
        .STATIC_CPHASEF(0),
        .CLK_DPS0_EN("FALSE"),
        .CLK_DPS1_EN("FALSE"),
        .CLK_DPS2_EN("FALSE"),
        .CLK_DPS3_EN("FALSE"),
        .CLK_DPS4_EN("FALSE"),
        .CLK_DPS5_EN("FALSE"),
        .CLK_DPS6_EN("FALSE"),
        .CLK_DPSF_EN("FALSE"),
        .CLK_CAS5_EN("FALSE"),
        .CLKOUT0_SYN_EN("FALSE"),
        .CLKOUT1_SYN_EN("FALSE"),
        .CLKOUT2_SYN_EN("FALSE"),
        .CLKOUT3_SYN_EN("FALSE"),
        .CLKOUT4_SYN_EN("FALSE"),
        .CLKOUT5_SYN_EN("FALSE"),
        .CLKOUT6_SYN_EN("FALSE"),
        .CLKOUTF_SYN_EN("FALSE"),
        .SSC_MODE("DISABLE"),
        .SSC_FREQ(25),
        .INTERNAL_FB("CLKOUTF"),
        .EXTERNAL_FB("DISABLE"),
        .BANDWIDTH("OPTIMIZED")
    ) u_video_gpll (
        .CLKOUT0(video_pll_clk),
        .CLKOUT0N(),
        .CLKOUT1(),
        .CLKOUT1N(),
        .CLKOUT2(),
        .CLKOUT2N(),
        .CLKOUT3(),
        .CLKOUT3N(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKOUTF(),
        .CLKOUTFN(),
        .LOCK(video_pll_locked),
        .DPS_DONE(),
        .DPS_CLK(1'b0),
        .DPS_EN(1'b0),
        .DPS_DIR(1'b0),
        .CLKIN1(clk),
        .CLKIN2(1'b0),
        .CLKFB(1'b0),
        .CLKIN_SEL(1'b0),
        .CLKOUT0_SYN(1'b0),
        .CLKOUT1_SYN(1'b0),
        .CLKOUT2_SYN(1'b0),
        .CLKOUT3_SYN(1'b0),
        .CLKOUT4_SYN(1'b0),
        .CLKOUT5_SYN(1'b0),
        .CLKOUT6_SYN(1'b0),
        .CLKOUTF_SYN(1'b0),
        .PLL_PWD(1'b0),
        .RST(1'b0),
        .APB_RDATA(),
        .APB_READY(),
        .APB_CLK(1'b0),
        .APB_RST_N(1'b0),
        .APB_ADDR(5'b0),
        .APB_SEL(1'b0),
        .APB_EN(1'b0),
        .APB_WRITE(1'b0),
        .APB_WDATA(16'b0)
    );
`endif
    wire video_clk = VIDEO_720P ? video_pll_clk : 1'b0;
    wire video_locked = VIDEO_720P ? video_pll_locked : 1'b1;
    wire video_reset_n = reset_pipe[15] && video_locked;
    reg [1:0] video_reset_pipe;
    always @(posedge sys_clk or negedge video_reset_n)
        if (!video_reset_n) video_reset_pipe <= 0;
        else video_reset_pipe <= {video_reset_pipe[0], 1'b1};
    soc_top #(
        .VIDEO_720P(VIDEO_720P),
        .DISPLAY_NEW(DISPLAY_NEW),
        .NN(NN),
        .RESET_PC(32'hf800),
        .ROM_WRITABLE(1),
        .HW_ID(HW_ID),
        .ROM_INIT_FILE(MEM_FILE),
        .IO_N(IO_N),
        .UART_TX_PIN(`UART_TX_PIN),
        .UART_RX_PIN(`UART_RX_PIN)
    ) soc (
        .clk(sys_clk),
        .rst_n(video_reset_pipe[1]),
        .video_clk(video_clk),
        .io_o(io_o),
        .io_oe(io_oe),
        .io_i(io_i),
        .video_pclk(hdmi_pclk),
        .video_hsync_n(hdmi_hs),
        .video_vsync_n(hdmi_vs),
        .video_de(hdmi_de),
        .video_rgb(hdmi_d),
        .vin_pclk(hdmi_rx_pclk),
        .vin_de(hdmi_rx_de),
        .vin_rgb(hdmi_rx_d)
    );
endmodule
