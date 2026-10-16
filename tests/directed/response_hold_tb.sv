`timescale 1ns/1ps
// gen_ram 本身无 valid/ready, 通过原有 ram 包装测完整响应契约。
module response_hold_tb;
    localparam [31:0] ROM_WORD = 32'h89abcdef, RAM_WORD = 32'hdecafbad;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, valid = 0, rsp_ready = 0;
    reg [31:0] addr = 0;
    wire rom_ready, rom_valid, ram_ready, ram_valid;
    wire [31:0] rom_data, ram_data;
    rom #(.DP(8)) u_rom(
        .clk(clk), .rst_n(rst_n), .addr_i(addr), .data_i(32'b0),
        .sel_i(4'hf), .we_i(1'b0), .data_o(rom_data),
        .req_valid_i(valid), .req_ready_o(rom_ready),
        .rsp_valid_o(rom_valid), .rsp_ready_i(rsp_ready)
    );
    ram #(.DP(8)) u_ram(
        .clk(clk), .rst_n(rst_n), .addr_i(addr), .data_i(32'b0),
        .sel_i(4'hf), .we_i(1'b0), .data_o(ram_data),
        .req_valid_i(valid), .req_ready_o(ram_ready),
        .rsp_valid_o(ram_valid), .rsp_ready_i(rsp_ready)
    );
    reg rom_bad = 0, ram_bad = 0;
    reg [31:0] rom_held, ram_held;
    integer n;
    initial begin
        u_rom.mem[0] = 32'h11223344; u_rom.mem[3] = ROM_WORD;
        u_ram.u_gen_ram.ram[0] = 32'h55667788;
        u_ram.u_gen_ram.ram[3] = RAM_WORD;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk); addr = 12; valid = 1; rsp_ready = 0;
        @(posedge clk);
        if (rom_ready !== 1'b1 || ram_ready !== 1'b1) begin
            $display("CHECK 1 FAIL: read request not accepted ROM=%b RAM=%b", rom_ready, ram_ready);
            $finish;
        end
        #1;
        rom_held = rom_data; ram_held = ram_data;
        $display("MEM accepted ROM=%h RAM=%h", rom_held, ram_held);
        if (rom_valid !== 1'b1 || rom_data !== ROM_WORD) rom_bad = 1;
        if (ram_valid !== 1'b1 || ram_data !== RAM_WORD) ram_bad = 1;
        // 握手已完成, 主设备可以撤销 valid 并改变地址。
        @(negedge clk); valid = 0; addr = 0;
        for (n = 1; n <= 4; n = n + 1) begin
            @(posedge clk); #1;
            $display("MEM hold=%0d ROM valid=%b data=%h RAM valid=%b data=%h",
                     n, rom_valid, rom_data, ram_valid, ram_data);
            if (rom_valid !== 1'b1 || rom_ready !== 1'b0 || rom_data !== rom_held)
                rom_bad = 1;
            if (ram_valid !== 1'b1 || ram_ready !== 1'b0 || ram_data !== ram_held)
                ram_bad = 1;
        end
        // 保存背压末尾实际数据, 并检查消费沿前数据及消费后无多余响应。
        rom_held = rom_data; ram_held = ram_data;
        @(negedge clk); rsp_ready = 1;
        @(posedge clk);
        if (rom_valid !== 1'b1 || rom_data !== ROM_WORD) rom_bad = 1;
        if (ram_valid !== 1'b1 || ram_data !== RAM_WORD) ram_bad = 1;
        #1;
        if (rom_valid !== 1'b0) rom_bad = 1;
        if (ram_valid !== 1'b0) ram_bad = 1;
        repeat (2) begin
            @(posedge clk); #1;
            if (rom_valid !== 1'b0) rom_bad = 1;
            if (ram_valid !== 1'b0) ram_bad = 1;
        end
        if (!rom_bad && !ram_bad) $display("CHECK 1 PASS");
        else $display("CHECK 1 FAIL: ROM bad=%b held=%h expected=%h; RAM/gen_ram bad=%b held=%h expected=%h",
                      rom_bad, rom_held, ROM_WORD, ram_bad, ram_held, RAM_WORD);
        $finish;
    end
    initial begin #10000; $display("CHECK 1 FAIL: timeout"); $finish; end
endmodule
