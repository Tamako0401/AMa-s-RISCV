`timescale 1ns / 1ps
// 与 cpu_tb 相同的独立存储模型: 握手后锁住数据, 隔离存储响应保持问题。
module trap_stack_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    wire [31:0] ia, iw, da, dw;
    wire [3:0] isel, dsel;
    wire iwe, dwe, iv, ir, iq, dv, dr, dq;
    reg ivalid = 0, dvalid = 0;
    reg [31:0] idata = 0, ddata = 0;
    assign ir = rst_n && !ivalid;
    assign dr = rst_n && !dvalid;
    tinyriscv_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .jtag_halt_i(1'b0),
        .int_i(8'b0),
        .ibus_addr_o(ia),
        .ibus_data_o(iw),
        .ibus_data_i(idata),
        .ibus_sel_o(isel),
        .ibus_we_o(iwe),
        .ibus_req_valid_o(iv),
        .ibus_req_ready_i(ir),
        .ibus_rsp_valid_i(ivalid),
        .ibus_rsp_ready_o(iq),
        .dbus_addr_o(da),
        .dbus_data_o(dw),
        .dbus_data_i(ddata),
        .dbus_sel_o(dsel),
        .dbus_we_o(dwe),
        .dbus_req_valid_o(dv),
        .dbus_req_ready_i(dr),
        .dbus_rsp_valid_i(dvalid),
        .dbus_rsp_ready_o(dq)
    );
    reg [31:0] rom[0:16383];
    reg [31:0] ram[0:16383];
    reg completing = 0;
    reg [31:0] result;
    integer snapshots = 0;
    string rom_path;
    task static fail(input string why);
        $fatal(1, "CHECK 2 FAIL: %s", why);
    endtask
    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) fail("missing +rom=hex");
        $readmemh(rom_path, rom);
        for (integer n = 0; n < 16384; n = n + 1) ram[n] = 32'ha5a5a5a5;
        repeat (5) @(negedge clk);
        rst_n = 1;
    end
    always @(posedge clk)
        if (rst_n) begin
            if (ivalid && iq) ivalid <= 0;
            if (iv && ir) begin
                if ((^ia) === 1'bx || ia >= 65536 || ia[1:0] != 0 || iwe !== 1'b0)
                    fail($sformatf("invalid fetch %h", ia));
                idata  <= rom[ia[15:2]];
                ivalid <= 1;
            end
            if (dv && dr) begin
                if ((^{da, dsel, dwe}) === 1'bx || da < 32'h10000000 || da >= 32'h10010000)
                    fail($sformatf("invalid data request %h", da));
                ddata  <= ram[da[15:2]];
                dvalid <= 1;
                if (dwe) begin
                    if ((^dw) === 1'bx || dsel !== 4'hf) fail("unknown/partial snapshot write");
                    ram[da[15:2]] <= dw;
                    if (da == 32'h10000000) begin
                        completing <= 1;
                        result <= dw;
                    end else snapshots <= snapshots + 1;
                end
            end
            if (dvalid && dq) begin
                dvalid <= 0;
                if (completing) begin
                    $display(
                        "TRAP before=%h entry=%h return=%h mcause=%h mepc=%h ecall_pc=%h errors=%h",
                        ram[1], ram[2], ram[3], ram[4], ram[5], ram[6], result);
                    if (snapshots != 6 || ram[1] !== 8 || ram[4] !== 11 || ram[5] !== ram[6])
                        fail($sformatf("setup/cause/PC mismatch snapshots=%0d", snapshots));
                    if (result === 0 && (ram[2] & 32'h88) === 32'h80 &&
                    (ram[3] & 32'h88) === 32'h88)
                        $display("CHECK 2 PASS");
                    else
                        $fatal(
                            1,
                            "CHECK 2 FAIL: entry MIE=%b MPIE=%b; return MIE=%b MPIE=%b (expected 0/1;1/1)",
                            ram[2][3],
                            ram[2][7],
                            ram[3][3],
                            ram[3][7]
                        );
                    $finish;
                end
            end
        end
    initial begin
        #1000000;
        fail($sformatf("timeout pc=%h", ia));
    end
endmodule
