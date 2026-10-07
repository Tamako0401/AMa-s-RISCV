// MES50HP / PGL50H-6IFBG484. KEY1 is active-low user reset, not PROGRAM_N.
// LCD: GMT024-8p10p-SPI (ST7789V, 240x320, write-only). Backlight is tied on.
module mes50hp_top (
    input wire clk, input wire key1_n,
    input wire uart_rx, output wire uart_tx,
    output wire [7:0] led,
    output wire lcd_sck, output wire lcd_mosi, output wire lcd_cs,
    output wire lcd_dc, output wire lcd_rst_n, output wire lcd_bl
);
    // Configuration-time initialization supplies power-on reset even if KEY1
    // is never pressed. Assertion is asynchronous; release is synchronized.
    reg [15:0] reset_pipe = 16'b0;
    always @(posedge clk or negedge key1_n) begin
        if (!key1_n) reset_pipe <= 16'b0;
        else reset_pipe <= {reset_pipe[14:0], 1'b1};
    end
    wire fault;
    reg [1:0] rx_sync = 2'b11;
    always @(posedge clk) rx_sync <= {rx_sync[0], uart_rx};
    minimal_soc soc (
        .clk(clk), .rst_n(reset_pipe[15]), .uart_rx(rx_sync[1]), .uart_tx(uart_tx),
        .led(led), .fault(fault),
        .spi_clk(lcd_sck), .spi_mosi(lcd_mosi),
        .lcd_cs(lcd_cs), .lcd_dc(lcd_dc), .lcd_rst_n(lcd_rst_n)
    );
    assign lcd_bl = 1'b1; // backlight always on; add a GPIO bit later if needed
endmodule
