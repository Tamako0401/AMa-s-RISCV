`timescale 1ns/1ps
module board_reset_tb;
    reg clk = 0;
    always #10 clk = ~clk;
    reg key1_n = 1, uart_rx = 1;
    wire uart_tx;
    wire [7:0] led;
    wire lcd_sck, lcd_mosi, lcd_cs, lcd_dc, lcd_rst_n, lcd_bl;
    mes50hp_top #(.MEM_FILE("board_reset.hex")) dut(.*);

    integer boot = 0, reports = 0, mutations = 0, fetches = 0;
    reg done = 0;
    reg [31:0] reported, first_value, data_addr;
    task fail(input string why);
        $display("CHECK 3 FAIL: %s", why);
        $finish;
    endtask
    // 仅观察已握手的 CPU 访问。RAM 只由 minimal_soc 的 initial 加载一次。
    always @(posedge clk) if (dut.reset_pipe[15]) begin
        if (dut.fault !== 1'b0) fail("SoC bus fault");
        if (dut.soc.ifire && dut.soc.ia == 32'h80000000) fetches = fetches + 1;
        if (dut.soc.dfire && dut.soc.dwe) begin
            if (dut.soc.dsel !== 4'hf) fail("unexpected partial program store");
            if (dut.soc.da[31:16] == 16'h8000 && dut.soc.dw === 32'd1) begin
                data_addr = dut.soc.da;
                mutations = mutations + 1;
            end
            if (dut.soc.da == 32'h40000004) begin
                if (reports == 0) begin
                    reported = dut.soc.dw;
                    reports = 1;
                end else if (reports == 1 && dut.soc.dw === 32'hc001cafe) begin
                    reports = 2;
                    done <= 1;
                end else fail("unexpected program report sequence");
            end
        end
    end
    initial begin
        wait(done);
        @(negedge clk);
        if (reported !== 3 || mutations != 1 || fetches != 1)
            fail($sformatf("power-on setup value=%h mutations=%0d fetches=%0d", reported, mutations, fetches));
        first_value = reported;
        if (dut.soc.ram[data_addr[15:2]] !== 1) fail("global was not changed to 1");
        $display("RESET boot=0 global_read=%0d global_addr=%h RAM_before_KEY1=%0d",
                 reported, data_addr, dut.soc.ram[data_addr[15:2]]);
        key1_n = 0;
        #1;
        if (dut.reset_pipe !== 0 || dut.soc.core_reset_n !== 0) fail("KEY1 did not assert CPU reset");
        boot = 1; done = 0; reports = 0; mutations = 0; fetches = 0;
        repeat (8) @(negedge clk);
        if (dut.soc.ram[data_addr[15:2]] !== 1) fail("RAM changed during KEY1 reset");
        $display("RESET KEY1 held low: RAM=%0d (no reload)", dut.soc.ram[data_addr[15:2]]);
        key1_n = 1;
        wait(dut.reset_pipe[15]);
        wait(done);
        @(negedge clk);
        if (mutations != 1 || fetches != 1) fail("second boot/mutation not observed");
        $display("RESET boot=%0d global_read=%0d expected=3", boot, reported);
        if (reported === 3) $display("CHECK 3 PASS");
        else $display("CHECK 3 FAIL: power_on=%0d after_KEY1=%0d expected=3 (RAM retained 1)",
                      first_value, reported);
        $finish;
    end
    initial begin #2000000; fail($sformatf("timeout boot=%0d reports=%0d", boot, reports)); end
endmodule
