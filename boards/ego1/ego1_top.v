// EGO1 / xc7a35tcsg324-1, 复用 MES50HP 的哈佛 SoC 和 50 MHz 固件。
module ego1_top (
    input wire clk, input wire rst_n,
    input wire uart_rx, output wire uart_tx,
    output wire [7:0] led
);
    wire clk50_raw, clk50, feedback_raw, feedback, locked;
    // 100 MHz * 10 / 20 = 50 MHz; VCO = 1000 MHz。
    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(20.0)
    ) mmcm (
        .CLKIN1(clk), .CLKFBIN(feedback), .CLKFBOUT(feedback_raw),
        .CLKOUT0(clk50_raw), .LOCKED(locked),
        .PWRDWN(1'b0), .RST(~rst_n)
    );
    BUFG feedback_buf (.I(feedback_raw), .O(feedback));
    BUFG clock_buf (.I(clk50_raw), .O(clk50));
    // S6 按下为低; 未锁定时保持复位, 由 mes50hp_top 同步释放。
    mes50hp_top board (
        .clk(clk50), .key1_n(rst_n & locked),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .led(led),
        .lcd_sck(), .lcd_mosi(), .lcd_cs(),
        .lcd_dc(), .lcd_rst_n(), .lcd_bl()
    );
endmodule
