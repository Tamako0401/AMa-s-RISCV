`timescale 1ns / 1ps
// 虚拟盘古板: 真实的 mes50hp_top, 屏幕模型和串口接在板子的 io 脚上 (接线同 sw/bsp/shield_lcd.h)
module sim_top;
    reg clk = 0;
    always #10 clk = ~clk;
    string rom_path;

    `include "boards/mes50hp/pins_top.vh"
    wire [`IO_N-1:0] io;
    assign io[`PIN_UART_RX] = 1'b1;
    // 按键是低有效输入, 没人按时板上是高电平
    localparam [127:0] IN_N = `IO_IN_N_MASK;
    for (genvar i = 0; i < `IO_N; i++) begin : g_key
        if (IN_N[i]) assign io[i] = 1'b1;
    end
    mes50hp_top #(
        .MEM_FILE("")
    ) board (
        .clk(clk),
        .key1_n(1'b1),
        .io(io)
    );
    st7789_model u_panel (
        .rst_n(io[`PIN_J8_25]),
        .cs_n(io[`PIN_J8_23]),
        .dc(io[`PIN_J8_26]),
        .sck(io[`PIN_J8_27]),
        .mosi(io[`PIN_J8_28])
    );
    uart_rx u_uart_rx (
        .clk(clk),
        .tx (io[`PIN_UART_TX])
    );

    initial begin
        $value$plusargs("rom=%s", rom_path);
        $readmemh(rom_path, board.soc.u_rom.mem);
    end
endmodule
