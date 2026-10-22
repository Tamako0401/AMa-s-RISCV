`timescale 1ns / 1ps
module boot_tb;
    parameter VIDEO_720P = 1;
    `include "boards/mes50hp/pins_top.vh"
    integer APP_LENGTH;
    reg [31:0] APP_CRC;
    string rom_path;
    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        $readmemh(rom_path, dut.soc.u_rom.mem);
    end
    localparam BIT_NS = 8680;
    localparam [31:0] ID = 32'h12345678;
    reg clk = 0;
    always #10 clk = ~clk;
    reg key1_n = 1, uart_rx = 1;
    wire [`IO_N-1:0] io;
    wire uart_tx = io[`PIN_UART_TX];
    assign io[`PIN_UART_RX] = uart_rx;
    mes50hp_top #(
        .VIDEO_720P(VIDEO_720P),        .MEM_FILE(""),
        .HW_ID(ID),
        .BREAK_CYCLES(6000)
    ) dut (
        .clk(clk),
        .key1_n(key1_n),
        .io(io)
    );

    reg [7:0] app[0:65535];
    reg [31:0] program_rom[0:16383];
    string program_path;
    integer length, bit_n;
    reg [7:0] received[0:4095];
    integer count = 0, cursor = 0;
    reg [7:0] byte_rx;
    integer b;
    initial
        forever begin
            @(negedge uart_tx);
            #(BIT_NS / 2);
            if (uart_tx !== 0) $fatal(1, "FAIL boot: start bit");
            for (b = 0; b < 8; b = b + 1) begin
                #BIT_NS;
                byte_rx[b] = uart_tx;
            end
            #BIT_NS;
            if (uart_tx !== 1) $fatal(1, "FAIL boot: stop bit");
            received[count] = byte_rx;
            count = count + 1;
        end

    task static send_byte(input logic [7:0] value);
        integer bit_n;
        begin
            uart_rx = 0;
            #BIT_NS;
            for (bit_n = 0; bit_n < 8; bit_n = bit_n + 1) begin
                uart_rx = value[bit_n];
                #BIT_NS;
            end
            uart_rx = 1;
            #BIT_NS;
        end
    endtask
    task static send_word(input logic [31:0] value);
        integer n;
        begin
            for (n = 0; n < 4; n = n + 1) send_byte(value[n*8+:8]);
        end
    endtask
    task static expect_byte(input logic [7:0] value);
        begin
            wait (count > cursor);
            if (received[cursor] !== value)
                $fatal(
                    1, "FAIL boot byte %0d: got %02x expected %02x", cursor, received[cursor], value
                );
            cursor = cursor + 1;
        end
    endtask
    task static expect_word(input logic [31:0] value);
        integer n;
        begin
            for (n = 0; n < 4; n = n + 1) expect_byte(value[n*8+:8]);
        end
    endtask
    task static expect_text(input string value);
        integer n;
        begin
            for (n = 0; n < value.len(); n = n + 1) expect_byte(value[n]);
        end
    endtask
    task static handshake;
        begin
            send_byte(8'h7f);
            expect_text("AMB");
            expect_byte(1);
            expect_word(ID);
            expect_word(32'hf800);
        end
    endtask
    task static enter_boot;
        begin
            uart_rx = 0;
            #160000;
            if (dut.reset_pipe !== 0) $fatal(1, "FAIL break did not hold reset");
            uart_rx = 1;
            #2000;
            handshake();
        end
    endtask
    task static download(input logic [31:0] crc);
        integer n;
        begin
            send_byte("W");
            send_word(APP_LENGTH);
            send_word(crc);
            for (n = 0; n < APP_LENGTH; n = n + 1) send_byte(app[n]);
        end
    endtask

    reg [31:0] first_word, boot_word;
    integer n;
    initial begin
        if (!$value$plusargs("program_rom=%s", program_path)) $fatal(1, "Missing program ROM");
        $readmemh(program_path, program_rom);
        length = 32'hf800;
        while (program_rom[(length-1)>>2][((length-1)&3)*8+:8] == 8'ha5) length = length - 1;
        for (n = 0; n < length; n = n + 1) app[n] = program_rom[n>>2][(n&3)*8+:8];
        // 下载尾部刻意不对齐, 覆盖协议的补零。
        while ((length & 3) != 0) begin
            app[length] = 0;
            length = length + 1;
        end
        app[length] = 8'h12;
        app[length+1] = 8'h34;
        app[length+2] = 8'h56;
        APP_LENGTH = length + 3;
        APP_CRC = 32'hffffffff;
        for (n = 0; n < APP_LENGTH; n = n + 1) begin
            APP_CRC = APP_CRC ^ app[n];
            for (bit_n = 0; bit_n < 8; bit_n = bit_n + 1)
            APP_CRC = (APP_CRC >> 1) ^ (APP_CRC[0] ? 32'hedb88320 : 0);
        end
        APP_CRC = ~APP_CRC;
        #1;
        first_word = dut.soc.u_rom.mem[0];
        boot_word  = dut.soc.u_rom.mem[15872];
        expect_text("AMA CPU PASS\r\n");
        if (dut.soc.u_rom.mem[0] !== first_word || dut.soc.u_rom.mem[15872] !== boot_word)
            $fatal(1, "FAIL default app ROM protection");
        $display("PASS boot: silent window, default app, ROM_WE=0 and boot protection");
        enter_boot();
        download(APP_CRC ^ 1);
        expect_byte("E");
        expect_word(APP_CRC);
        $display("PASS boot: bad CRC returns readback CRC");
        send_byte("W");
        send_word((32'hf800 + 1));
        send_word(0);
        expect_byte("E");
        expect_word(32'hffffffff);
        $display("PASS boot: oversized download rejected");
        download(APP_CRC);
        expect_byte("K");
        if (dut.soc.u_sysctl.rom_we !== 0) $fatal(1, "FAIL ROM_WE left enabled");
        for (n = 0; n < APP_LENGTH; n = n + 1)
        if (dut.soc.u_rom.mem[n>>2][(n&3)*8+:8] !== app[n])
            $fatal(1, "FAIL downloaded byte %0d", n);
        // 末字不足四字节也必须按协议补零。
        for (n = APP_LENGTH; (n & 3) != 0; n = n + 1)
        if (dut.soc.u_rom.mem[n>>2][(n&3)*8+:8] !== 0) $fatal(1, "FAIL download padding");
        first_word = dut.soc.u_rom.mem[0];
        send_byte("G");
        expect_text("NEW APP\n");
        if (dut.soc.u_rom.mem[0] !== first_word || dut.soc.u_rom.mem[15872] !== boot_word)
            $fatal(1, "FAIL new app ROM protection");
        $display("PASS boot: download, execute new instructions, protected writes discarded");
        enter_boot();
        $display("PASS boot: break reenters bootloader from downloaded app");
        // 未知命令和中途超时都要重新等同步字节。
        send_byte("?");
        handshake();
        send_byte("W");
        send_byte(1);
        #1500000;
        if (dut.soc.u_sysctl.rom_we !== 0) $fatal(1, "FAIL timeout write enable");
        handshake();
        send_byte("W");
        send_word(4);
        send_word(0);
        send_byte(1);
        #1500000;
        if (dut.soc.u_sysctl.rom_we !== 0) $fatal(1, "FAIL data timeout write enable");
        handshake();
        $display("PASS boot: command and byte timeout recovery");
        $display("PASS boot_tb");
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "FAIL boot_tb timeout (received=%0d cursor=%0d)", count, cursor);
    end
endmodule
