// 复位测试: soc_top 跑 sw/app/reset_check, 程序改掉自己的变量后复位 CPU,
// 只在仿真开始时装一次 ROM 镜像 (和 FPGA 配置一样), RAM 不预装, 复位也不重装。
// 两次运行都写 tohost = 1 才算通过: 说明 startup.S 每次复位都把 .data 初值从 ROM 拷回 RAM。
// 运行: python3 scripts/test-lcd.py reset_check --tb reset_tb
`timescale 1ns/1ps
module reset_tb;
    parameter [31:0] TOHOST_ADDR = 32'h10000000;

    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;

    soc_top u_soc(
        .clk(clk), .rst_n(rst_n),
        .uart_rx(1'b1), .uart_tx(), .led(),
        .spi_mosi(), .spi_miso(1'b0), .spi_ss(), .spi_clk(),
        .lcd_dc(), .lcd_rst_n()
    );

    // 观察数据总线上对 tohost 的写
    wire [31:0] da = u_soc.u_core.dbus_addr_o;
    wire [31:0] dw = u_soc.u_core.dbus_data_o;
    wire dwe = u_soc.u_core.dbus_we_o;
    wire dv = u_soc.u_core.dbus_req_valid_o;
    wire dr = u_soc.u_core.dbus_req_ready_i;
    reg [31:0] result;
    reg done = 0;
    always @(posedge clk) if (rst_n && dv && dr && dwe && da == TOHOST_ADDR) begin
        result <= dw;
        done <= 1;
    end

    reg [1023:0] rom_path, ram_path;
    integer boot;
    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        $readmemh(rom_path, u_soc.u_rom.mem);
        if ($value$plusargs("ram=%s", ram_path))
            $readmemh(ram_path, u_soc.u_ram.u_gen_ram.ram);
        for (boot = 0; boot < 2; boot = boot + 1) begin
            repeat (5) @(posedge clk);
            rst_n = 1;
            fork
                wait (done);
                begin repeat (200000) @(posedge clk); $fatal(1, "boot %0d: timeout", boot); end
            join_any
            disable fork;
            if (result != 1)
                $fatal(1, "boot %0d: tohost=%0d (2 = 初值没恢复, 3 = .bss 不是 0)", boot, result);
            $display("PASS reset boot %0d: lives 初值为 3, score 为 0", boot);
            @(negedge clk); rst_n = 0; done = 0;
        end
        $display("PASS reset: 复位后 .data 从 ROM 恢复, 与上电一致");
        $finish;
    end
endmodule
