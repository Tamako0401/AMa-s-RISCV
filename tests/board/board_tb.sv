`timescale 1ns / 1ps
module board_tb;
    parameter VIDEO_720P = 1;
`ifndef CLK_HALF_NS
`define CLK_HALF_NS 10 // mes50hp 的 50 MHz; 别的板的系统时钟频率不同时由 tests.toml 传入
`endif
    reg clk = 0;
    always #(`CLK_HALF_NS) clk = ~clk;  // 板子的物理系统时钟, 配合固件里真实的 UART 分频
    reg key1_n = 1, uart_rx = 1;
    wire uart_tx;
    wire [7:0] led;
    wire lcd_sck, lcd_mosi, lcd_cs, lcd_dc, lcd_rst_n, lcd_bl;
    // Parameter override at instantiation: Verilator rejects hierarchical
    // defparam (dut.soc.MEM_FILE), Icarus accepts both forms.
    // 板子由 -DBOARD=<名> 选择 (tests.toml), 默认 mes50hp。
`ifndef BOARD
`define BOARD mes50hp
`endif
`include `"boards/`BOARD/pins_top.vh`"
`define DUT_TOP `BOARD``_top
    wire [`IO_N-1:0] io;
    assign io[`PIN_UART_RX] = uart_rx;
    assign uart_tx = io[`PIN_UART_TX];
`ifdef PIN_LCD_SCK
    assign {lcd_sck, lcd_mosi, lcd_cs, lcd_dc, lcd_rst_n, lcd_bl} = {
        io[`PIN_LCD_SCK],
        io[`PIN_LCD_MOSI],
        io[`PIN_LCD_CS],
        io[`PIN_LCD_DC],
        io[`PIN_LCD_RST],
        io[`PIN_LCD_BL]
    };
`else
    assign {lcd_sck, lcd_mosi, lcd_cs, lcd_dc, lcd_rst_n, lcd_bl} = {
        io[`PIN_J8_27],
        io[`PIN_J8_28],
        io[`PIN_J8_23],
        io[`PIN_J8_26],
        io[`PIN_J8_25],
        io[`PIN_J8_24]
    };
`endif
    assign led = {
        io[`PIN_LED8],
        io[`PIN_LED7],
        io[`PIN_LED6],
        io[`PIN_LED5],
        io[`PIN_LED4],
        io[`PIN_LED3],
        io[`PIN_LED2],
        io[`PIN_LED1]
    };
    `DUT_TOP #(
        .VIDEO_720P(VIDEO_720P),
        .MEM_FILE("")
    ) dut (
        .clk(clk),
        .key1_n(key1_n),
        .io(io)
    );
    string rom_path;
    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        $readmemh(rom_path, dut.soc.u_rom.mem);
    end
    localparam BIT_NS = 8680;
    integer count = 0;
    integer boots = 0;
    reg [7:0] byte_rx;
    reg [7:0] expected[0:13];
    reg boot_done = 0;
    reg saw_led2 = 0;
    initial begin
        expected[0]  = "A";
        expected[1]  = "M";
        expected[2]  = "A";
        expected[3]  = " ";
        expected[4]  = "C";
        expected[5]  = "P";
        expected[6]  = "U";
        expected[7]  = " ";
        expected[8]  = "P";
        expected[9]  = "A";
        expected[10] = "S";
        expected[11] = "S";
        expected[12] = 13;
        expected[13] = 10;
    end
    // Decode serial output independently of the UART's internal registers.
    initial begin
        integer b;
        wait (dut.reset_pipe[15]);
        wait (uart_tx == 1);
        forever begin
            @(negedge uart_tx);
            #(BIT_NS / 2);
            if (uart_tx !== 0) $fatal(1, "Invalid start bit");
            for (b = 0; b < 8; b = b + 1) begin
                #BIT_NS;
                byte_rx[b] = uart_tx;
            end
            #BIT_NS;
            if (uart_tx !== 1) $fatal(1, "Invalid stop bit");
            if (count < 14) begin
                if (byte_rx !== expected[count])
                    $fatal(1, "UART byte %0d got %h expected %h", count, byte_rx, expected[count]);
            end else begin
                if (byte_rx !== 8'h5a) $fatal(1, "Echo mismatch %h", byte_rx);
                wait (saw_led2);
                $display("PASS board boot %0d: BSS/RAM/stack/byte masks, UART + Z echo, CPU GPIO",
                         boots);
                if (boots == 1) begin
                    $display("PASS board: power-on and KEY1 reset/reboot");
                    $finish;
                end
                boots = boots + 1;
                @(negedge clk);
                key1_n = 0;
                boot_done = 0;
                saw_led2 = 0;
                count = -1;
                repeat (8) @(negedge clk);
                key1_n = 1;
                wait (dut.reset_pipe[15]);
                wait (uart_tx == 1);
            end
            count = count + 1;
            if (count == 14) boot_done = 1;
        end
    end
    initial begin
        integer b;
        forever begin
            wait (boot_done);
            #(BIT_NS * 2);
            uart_rx = 0;
            #BIT_NS;
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx = (8'h5a >> b) & 1;
                #BIT_NS;
            end
            uart_rx = 1;
            wait (!boot_done);
        end
    end
    always @(posedge clk) begin
        if (led == 2) saw_led2 <= 1;
    end
    initial begin
        #2000000000;
        $fatal(1, "Board test timeout");
    end
endmodule
