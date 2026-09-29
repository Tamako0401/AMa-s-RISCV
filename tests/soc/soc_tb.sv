`timescale 1ns/1ps
// SoC 级测试台: 直接例化 rtl/soc_top/soc_top.v, 程序真正跑在 RTL 的
// rib + rom + ram 上。
//
// 与 tests/cpu 的分工: cpu_tb 用的是测试台自己的行为级存储模型(验证核),
// 这里补的是"总线互连 + 存储器 RTL 接起来对不对"这一层。
//
// 程序镜像由 +rom= 给出, RAM 初值由可选的 +ram= 给出, 测试台用 $readmemh
// 预载进 soc_top 内部的 rom/ram (相当于实机的引导加载或综合时的存储初值),
// 因此 rom.v/ram.v 自己的 ROM_INIT_FILE/RAM_INIT_FILE 参数在这里用不到。
//
// 结束判定: 向 RAM 窗口第 0 个字 0x1000_0000 的整字写 = 程序结束, 写入值为返回值。
module soc_tb;
    parameter [31:0] RESULT_ADDR = 32'h10000000;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    string rom_path, ram_path;
    integer unused;
    integer cycles = 0, stores = 0, expected_stores = -1;
    reg seen = 0;
    reg [31:0] result;

    // 层次化引用核的数据总线端口(接 rib 的主设备 1), 只用于观察
    wire [31:0] da, dw;
    wire [3:0]  dsel;
    wire        dwe, dv, dr;
    assign da   = u_soc.u_core.dbus_addr_o;
    assign dw   = u_soc.u_core.dbus_data_o;
    assign dsel = u_soc.u_core.dbus_sel_o;
    assign dwe  = u_soc.u_core.dbus_we_o;
    assign dv   = u_soc.u_core.dbus_req_valid_o;
    assign dr   = u_soc.u_core.dbus_req_ready_i;

    soc_top u_soc(
        .clk(clk),
        .rst_n(rst_n)
    );

    // rib 的互斥性: 任一时刻最多一个从设备被选中, 最多一个主设备收到响应
    wire [2:0] sel_cnt = u_soc.u_rib.s0_req_valid_o + u_soc.u_rib.s1_req_valid_o
                       + u_soc.u_rib.s2_req_valid_o + u_soc.u_rib.s3_req_valid_o
                       + u_soc.u_rib.s4_req_valid_o;
    wire [1:0] rsp_cnt = u_soc.u_rib.m0_rsp_valid_o + u_soc.u_rib.m1_rsp_valid_o;

    always @(posedge clk) if (rst_n) begin
        if (sel_cnt > 3'd1) $fatal(1, "rib selected %0d slaves at once", sel_cnt);
        if (rsp_cnt > 2'd1) $fatal(1, "rib routed a response to both masters");
    end

    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        unused = $value$plusargs("stores=%d", expected_stores);
        $readmemh(rom_path, u_soc.u_rom.mem);
        // RAM 初值是可选的: 用到已初始化 .data 的程序必须给 +ram=。
        // 这里直接写进存储数组, 相当于实机由 ram.v 的 RAM_INIT_FILE 完成。
        if ($value$plusargs("ram=%s", ram_path)) begin
            $readmemh(ram_path, u_soc.u_ram.u_gen_ram.ram);
        end
        repeat (5) @(negedge clk);
        rst_n = 1;
    end

    always @(posedge clk) if (rst_n && !seen) begin
        cycles <= cycles + 1;
        if (cycles > 200000) $fatal(1, "Timeout");
        if (dv && dr && dwe) begin
            if (da == RESULT_ADDR) begin
                if (dsel !== 4'b1111) $fatal(1, "Result write must be a full word");
                result <= dw;
                seen <= 1;
            end else begin
                stores <= stores + 1;
            end
        end
    end

    always @(posedge clk) if (seen) begin
        if (result !== 32'h1) $fatal(1, "Program FAIL code=%h", result);
        if (expected_stores >= 0 && stores != expected_stores)
            $fatal(1, "Store count %0d expected %0d", stores, expected_stores);
        $display("PASS SoC %s cycles=%0d stores=%0d", rom_path, cycles, stores);
        $finish;
    end

    initial begin #2000000; $fatal(1, "timeout"); end
endmodule
