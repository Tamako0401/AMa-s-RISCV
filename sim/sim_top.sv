`timescale 1ns / 1ps
module sim_top;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    string rom_path;

    `include "boards/mes50hp/pins_top.vh"
    wire [127:0] io_o, io_oe;
    wire [127:0] io_i = {69'b0, 1'b1, 58'b0};
    soc_top #(
        .IO_N(`IO_N),
        .UART_TX_PIN(`UART_TX_PIN),
        .UART_RX_PIN(`UART_RX_PIN)
    ) u_soc (
        .clk(clk),
        .rst_n(rst_n),
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
    st7789_model u_panel (
        .rst_n(io_o[22]),
        .cs_n(io_o[20]),
        .dc(io_o[23]),
        .sck(io_o[24]),
        .mosi(io_o[25])
    );
    uart_rx u_uart_rx (
        .clk(clk),
        .tx (io_o[`UART_TX_PIN])
    );

    initial begin
        $value$plusargs("rom=%s", rom_path);
        $readmemh(rom_path, u_soc.u_rom.mem);
        repeat (5) @(negedge clk);
        rst_n = 1;
    end
endmodule
