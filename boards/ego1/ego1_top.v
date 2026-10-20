`include "boards/ego1/pins_top.vh"
module ego1_top #(
    parameter [31:0] HW_ID = 0,
    parameter BREAK_CYCLES = 500000,
    parameter IO_N = `IO_N,
    parameter MEM_FILE = "firmware.hex"
) (
    input wire clk,
    input wire rst_n,
    inout wire [IO_N-1:0] io
);
    wire clk50_raw, clk50, feedback_raw, feedback, locked;
    // 100 MHz * 10 / 20 = 50 MHz; VCO = 1000 MHz。
    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0),
        .CLKOUT0_DIVIDE_F(20.0)
    ) mmcm (
        .CLKIN1(clk),
        .CLKFBIN(feedback),
        .CLKFBOUT(feedback_raw),
        .CLKOUT0(clk50_raw),
        .LOCKED(locked),
        .PWRDWN(1'b0),
        .RST(~rst_n)
    );
    BUFG feedback_buf (
        .I(feedback_raw),
        .O(feedback)
    );
    BUFG clock_buf (
        .I(clk50_raw),
        .O(clk50)
    );

    // S6 按下为低; 未锁定时保持复位。异步拉低、同步释放, 与 mes50hp_top 相同
    // 不用系统复位清计数器, 否则 break 会被自身复位打断。
    reg [1:0] rx_sync = 2'b11;
    reg [$clog2(BREAK_CYCLES+1)-1:0] break_count = 0;
    reg in_break = 0;       // 寄存器输出再去拉复位: 计数比较的组合输出会有毛刺, 不能直接接异步复位
    always @(posedge clk50) begin
        rx_sync <= {rx_sync[0], io[`UART_RX_PIN]};
        if (rx_sync[1]) break_count <= 0;
        else if (break_count < BREAK_CYCLES) break_count <= break_count + 1'b1;
        in_break <= !rx_sync[1] && break_count == BREAK_CYCLES;
    end
    wire reset_n = (rst_n & locked) && !in_break;
    reg [15:0] reset_pipe = 16'b0;
    always @(posedge clk50 or negedge reset_n) begin
        if (!reset_n) reset_pipe <= 16'b0;
        else reset_pipe <= {reset_pipe[14:0], 1'b1};
    end
    localparam [127:0] INOUT_MASK = `IO_INOUT_MASK;
    localparam [127:0] OUT_MASK   = `IO_OUT_MASK;
    localparam [127:0] IN_N_MASK  = `IO_IN_N_MASK;
    wire [127:0] io_o, io_oe, io_i;
    genvar n;
    generate
        for (n = 0; n < IO_N; n = n + 1) begin : pins
            if (INOUT_MASK[n]) begin
                assign io[n] = io_oe[n] ? io_o[n] : 1'bz;
            end else if (OUT_MASK[n]) begin
                assign io[n] = io_o[n];
            end
            assign io_i[n] = IN_N_MASK[n] ? ~io[n] : io[n];
        end
    endgenerate
    assign io_i[127:IO_N] = 0;
    soc_top #(
        .RESET_PC(32'hf800),
        .ROM_WRITABLE(1),
        .HW_ID(HW_ID),
        .ROM_INIT_FILE(MEM_FILE),
        .IO_N(IO_N),
        .UART_TX_PIN(`UART_TX_PIN),
        .UART_RX_PIN(`UART_RX_PIN)
    ) soc (
        .clk(clk50),
        .rst_n(reset_pipe[15]),
        .io_o(io_o),
        .io_oe(io_oe),
        .io_i(io_i),
        .uart_rx(1'b1),
        .uart_tx(),
        .led(),
        .spi_mosi(),
        .spi_miso(1'b0),
        .spi_ss(),
        .spi_clk(),
        .lcd_dc(),
        .lcd_rst_n()
    );
endmodule
