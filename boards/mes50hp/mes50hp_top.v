`include "boards/mes50hp/pins_top.vh"
`include "boards/mes50hp/video_clock.vh"
module mes50hp_top #(
    parameter [31:0] HW_ID = 0,
    parameter BREAK_CYCLES = 500000,
    parameter VIDEO_720P = 0,  // 1 要先在 video_clock.vh 补上 74.25 MHz PLL
    parameter OV7670_MONITOR = 0,
    parameter OV7670_VSYNC_ACTIVE_LEVEL = 1'b1,
    parameter IO_N = `IO_N,
    parameter MEM_FILE = "firmware.hex"
) (
    input wire clk,
    input wire key1_n,
    inout wire [IO_N-1:0] io,
    // HDMI 发送芯片 MS7210 的视频口 (配置口在 io 里, 见 sw/bsp/board_hdmi.h)
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
    // 不用系统复位清计数器, 否则 break 会被自身复位打断。
    reg [1:0] rx_sync = 2'b11;
    reg [$clog2(BREAK_CYCLES+1)-1:0] break_count = 0;
    reg in_break = 0;       // 寄存器输出再去拉复位: 计数比较的组合输出会有毛刺, 不能直接接异步复位
    always @(posedge clk) begin
        rx_sync <= {rx_sync[0], io[`UART_RX_PIN]};
        if (rx_sync[1]) break_count <= 0;
        else if (break_count < BREAK_CYCLES) break_count <= break_count + 1'b1;
        in_break <= !rx_sync[1] && break_count == BREAK_CYCLES;
    end
    wire reset_n = (key1_n) && !in_break;
    reg [15:0] reset_pipe = 16'b0;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) reset_pipe <= 16'b0;
        else reset_pipe <= {reset_pipe[14:0], 1'b1};
    end
    localparam [127:0] INOUT_MASK = `IO_INOUT_MASK;
    localparam [127:0] OUT_MASK   = `IO_OUT_MASK;
    localparam [127:0] IN_N_MASK  = `IO_IN_N_MASK;
    wire [127:0] io_o, io_oe, io_i;
    wire camera_xclk;
    wire camera_hdmi_pclk, camera_hdmi_hs, camera_hdmi_vs, camera_hdmi_de;
    wire [23:0] camera_hdmi_rgb;
    wire camera_scl_low, camera_sda_low, camera_config_done, camera_config_error;
    wire camera_vsync = io[`PIN_J8_23];
    wire camera_href = io[`PIN_J8_24];
    wire camera_pclk = io[`PIN_J8_25];
    wire [7:0] camera_data = {
        io[`PIN_J8_27], io[`PIN_J8_28], io[`PIN_J8_29], io[`PIN_J8_30],
        io[`PIN_J8_31], io[`PIN_J8_32], io[`PIN_J8_33], io[`PIN_J8_34]
    };

    generate if (OV7670_MONITOR) begin : g_ov7670
        ov7670_sccb_init u_sccb_init (
            .clk(clk),
            .rst_n(reset_pipe[15]),
            .sda_in(io[`PIN_J8_22]),
            .scl_low(camera_scl_low),
            .sda_low(camera_sda_low),
            .done(camera_config_done),
            .error(camera_config_error)
        );
        ov7670_vga #(
            .VSYNC_ACTIVE_LEVEL(OV7670_VSYNC_ACTIVE_LEVEL)
        ) u_monitor (
            .sys_clk(clk),
            .rst_n(reset_pipe[15]),
            .cam_pclk(camera_pclk),
            .cam_vsync(camera_vsync),
            .cam_href(camera_href),
            .cam_data(camera_data),
            .cam_xclk(camera_xclk),
            .hdmi_pclk(camera_hdmi_pclk),
            .hdmi_hs(camera_hdmi_hs),
            .hdmi_vs(camera_hdmi_vs),
            .hdmi_de(camera_hdmi_de),
            .hdmi_rgb(camera_hdmi_rgb)
        );
    end else begin : g_no_ov7670
        assign camera_scl_low = 1'b0;
        assign camera_sda_low = 1'b0;
        assign camera_config_done = 1'b0;
        assign camera_config_error = 1'b0;
        assign camera_xclk = 1'b0;
        assign camera_hdmi_pclk = 1'b0;
        assign camera_hdmi_hs = 1'b1;
        assign camera_hdmi_vs = 1'b1;
        assign camera_hdmi_de = 1'b0;
        assign camera_hdmi_rgb = 24'b0;
    end endgenerate

    genvar n;
    generate
        for (n = 0; n < IO_N; n = n + 1) begin : g_pins
            if (OV7670_MONITOR && n == `PIN_J8_21) begin : g_camera_scl
                assign io[n] = camera_scl_low ? 1'b0 : 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_22) begin : g_camera_sda
                assign io[n] = camera_sda_low ? 1'b0 : 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_23) begin : g_camera_vsync
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_24) begin : g_camera_href
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_25) begin : g_camera_pclk
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_26) begin : g_camera_xclk
                assign io[n] = camera_xclk;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_27) begin : g_camera_d7
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_28) begin : g_camera_d6
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_29) begin : g_camera_d5
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_30) begin : g_camera_d4
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_31) begin : g_camera_d3
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_32) begin : g_camera_d2
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_33) begin : g_camera_d1
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_34) begin : g_camera_d0
                assign io[n] = 1'bz;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_35) begin : g_camera_reset
                assign io[n] = 1'b1;
                assign io_i[n] = io[n];
            end else if (OV7670_MONITOR && n == `PIN_J8_36) begin : g_camera_pwdn
                assign io[n] = 1'b0;
                assign io_i[n] = 1'b0;
            end else if (INOUT_MASK[n]) begin : g_inout
                assign io[n] = io_oe[n] ? io_o[n] : 1'bz;
                assign io_i[n] = IN_N_MASK[n] ? ~io[n] : io[n];
            end else if (OUT_MASK[n]) begin : g_output
                assign io[n] = io_o[n];
                assign io_i[n] = IN_N_MASK[n] ? ~io[n] : io[n];
            end else begin : g_input
                assign io_i[n] = IN_N_MASK[n] ? ~io[n] : io[n];
            end
        end
    endgenerate
    assign io_i[127:IO_N] = 0;
    wire video_clk, video_locked;
    generate if (VIDEO_720P) begin : g_video_clock
        mes50hp_video_clock u_clock (.clk(clk), .rst_n(reset_pipe[15]),
            .pix_clk(video_clk), .locked(video_locked));
    end else begin : g_vga_clock
        assign video_clk = 1'b0;
        assign video_locked = 1'b1;
    end endgenerate
    wire video_reset_n = reset_pipe[15] && video_locked;
    reg [1:0] video_reset_pipe;
    always @(posedge clk or negedge video_reset_n)
        if (!video_reset_n) video_reset_pipe <= 0;
        else video_reset_pipe <= {video_reset_pipe[0], 1'b1};
    wire soc_hdmi_pclk, soc_hdmi_hs, soc_hdmi_vs, soc_hdmi_de;
    wire [23:0] soc_hdmi_rgb;
    soc_top #(
        .VIDEO_720P(VIDEO_720P),
        .RESET_PC(32'hf800),
        .ROM_WRITABLE(1),
        .HW_ID(HW_ID),
        .ROM_INIT_FILE(MEM_FILE),
        .IO_N(IO_N),
        .UART_TX_PIN(`UART_TX_PIN),
        .UART_RX_PIN(`UART_RX_PIN)
    ) soc (
        .clk(clk),
        .rst_n(video_reset_pipe[1]),
        .video_clk(video_clk),
        .io_o(io_o),
        .io_oe(io_oe),
        .io_i(io_i),
        .video_pclk(soc_hdmi_pclk),
        .video_hsync_n(soc_hdmi_hs),
        .video_vsync_n(soc_hdmi_vs),
        .video_de(soc_hdmi_de),
        .video_rgb(soc_hdmi_rgb),
        .vin_pclk(hdmi_rx_pclk),
        .vin_de(hdmi_rx_de),
        .vin_rgb(hdmi_rx_d)
    );
    assign hdmi_pclk = OV7670_MONITOR ? camera_hdmi_pclk : soc_hdmi_pclk;
    assign hdmi_hs = OV7670_MONITOR ? camera_hdmi_hs : soc_hdmi_hs;
    assign hdmi_vs = OV7670_MONITOR ? camera_hdmi_vs : soc_hdmi_vs;
    assign hdmi_de = OV7670_MONITOR ? camera_hdmi_de : soc_hdmi_de;
    assign hdmi_d = OV7670_MONITOR ? camera_hdmi_rgb : soc_hdmi_rgb;
endmodule
