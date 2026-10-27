`timescale 1ns / 1ps
`include "defines.v"
// Board-independent CPU harness. Memory is a simulation model, not FPGA IP.
//
// 哈佛式存储器模型, 与 tests/cpu/link.ld 和 rtl/core/rib.v 的译码一致:
//   ROM 0x0000_0000, 64 KiB -- 指令(.text/.rodata)。数据总线只能"读"它。
//   RAM 0x1000_0000, 64 KiB -- 数据。窗口第 0 个字是"运行结束"信箱:
//           程序 sw a0, 0(0x1000_0000) 表示结束, 该值作为返回值被检查。
// 两个镜像分别由 +rom= 和 +ram= 给出(各 16384 个字, hex 文本)。
module cpu_tb;
    parameter I_DELAY = 0;
    parameter D_DELAY = 0;
    parameter SEED = 1;
    parameter [31:0] ROM_BASE = 32'h00000000;
    parameter [31:0] RAM_BASE = 32'h10000000;
    parameter [31:0] RESULT_ADDR = 32'h10000000;
    localparam [31:0] MEM_BYTES = 65536;
    localparam [31:0] MEM_WORDS = MEM_BYTES / 4;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    wire [31:0] ia, iw, da, dw;
    wire [3:0] isel, dsel;
    wire iwe, dwe, iv, ir, iq, dv, dr, dq;
    reg [31:0] idata, ddata;
    reg ivalid = 0, dvalid = 0;
    tinyriscv_core #(
        .RESET_PC(ROM_BASE)
    ) dut (
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
    reg [31:0] rom[0:MEM_WORDS-1];
    reg [31:0] ram[0:MEM_WORDS-1];
    reg [31:0] rng = SEED;
    reg ibusy = 0, dbusy = 0;
    integer icount, dcount, cycles = 0, stores = 0;
    integer expected_stores = -1;
    integer test_pass = 0;  // read by the ModelSim batch runner after $finish
    reg [31:0] ipayload, dpayload;
    reg completing = 0;
    reg [31:0] status;
    string rom_path, ram_path, wave_path, commit_log_path;
    integer commit_log_fd = 0;
    assign ir = rst_n && !ibusy && !ivalid && (I_DELAY == 0 || rng[0]);
    assign dr = rst_n && !dbusy && !dvalid && (D_DELAY == 0 || rng[4]);

    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        if (!$value$plusargs("ram=%s", ram_path)) $fatal(1, "Missing +ram=hex");
        if ($value$plusargs("commitlog=%s", commit_log_path))
            commit_log_fd = $fopen(commit_log_path, "w");
        // void' 丢弃返回值的原因见 soc_tb.sv: 旧 Verilator 会优化掉返回值没人用的调用
        void'($value$plusargs("stores=%d", expected_stores));
        $readmemh(rom_path, rom);
        $readmemh(ram_path, ram);
        if ($value$plusargs("vcd=%s", wave_path)) begin
            $dumpfile(wave_path);
            $dumpvars(0, cpu_tb);
        end
        repeat (5) @(negedge clk);
        rst_n = 1;
    end

    // Check request stability independently of the memory response generator.
    reg i_wait = 0, d_wait = 0;
    reg [31:0] held_ia;
    reg [68:0] held_d;
    always @(posedge clk)
        if (rst_n) begin
            if ((^{iv, dv, iq, dq}) === 1'bx)
                $fatal(1, "Unknown CPU bus control I=%b/%b D=%b/%b", iv, iq, dv, dq);
            if (dut.ex_reg_we_o && dut.ex_reg_waddr_o != 0 && ((^dut.ex_reg_wdata_o) === 1'bx))
                $fatal(1, "Unknown register writeback");
            if (dut.ex_load_we && dut.ex_load_waddr != 0 && ((^dut.ex_load_wdata) === 1'bx))
                $fatal(1, "Unknown load writeback");
            if (i_wait && (!iv || ia !== held_ia)) $fatal(1, "Unstable stalled fetch");
            if (d_wait && (!dv || {da, dw, dsel, dwe} !== held_d))
                $fatal(1, "Unstable stalled data request");
            i_wait  <= iv && !ir;
            d_wait  <= dv && !dr;
            held_ia <= ia;
            held_d  <= {da, dw, dsel, dwe};
        end

    always @(posedge clk)
        if (rst_n) begin
            cycles <= cycles + 1;
            rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            if (cycles > 1000000) $fatal(1, "Timeout pc=%h", ia);
            // ---- 取指: 只访问 ROM ----
            if (iv && ir) begin
                if ((^{ia, isel, iwe}) === 1'bx) $fatal(1, "Unknown fetch request");
                if (ia < ROM_BASE || ia >= ROM_BASE + MEM_BYTES || ia[1:0] != 0 || iwe)
                    $fatal(1, "Invalid fetch %h", ia);
                ibusy <= 1;
                icount <= I_DELAY == 0 ? 0 : rng[9:6] % (I_DELAY + 1);
                ipayload <= rom[(ia-ROM_BASE)>>2];
            end
            if (ibusy) begin
                if (icount == 0) begin
                    ibusy  <= 0;
                    ivalid <= 1;
                    idata  <= ipayload;
                end else icount <= icount - 1;
            end
            if (ivalid && iq) begin
                ivalid <= 0;
                idata  <= 32'hxxxxxxxx;  // catch consumers using a stale response
            end
            // ---- 访存: 结果信箱 / RAM / (只读)ROM ----
            if (dv && dr) begin
                if (((^{da, dsel, dwe}) === 1'bx) || (dwe && ((^dw) === 1'bx)))
                    $fatal(1, "Unknown data request");
                dbusy  <= 1;
                dcount <= D_DELAY == 0 ? 0 : rng[15:12] % (D_DELAY + 1);
                if (da == RESULT_ADDR && dwe && dsel == 4'b1111) begin
                    completing <= 1;
                    status <= dw;
                    dpayload <= 0;
                end else if (da >= RAM_BASE && da < RAM_BASE + MEM_BYTES) begin
                    dpayload <= ram[(da-RAM_BASE)>>2];
                    if (dwe) begin
                        stores <= stores + 1;
                        for (integer lane = 0; lane < 4; lane = lane + 1)
                        if (dsel[lane]) ram[(da-RAM_BASE)>>2][8*lane+:8] <= dw[8*lane+:8];
                    end
                end else if (da >= ROM_BASE && da < ROM_BASE + MEM_BYTES) begin
                    // 哈佛: 数据总线可以读 ROM 里的常量(.rodata), 但写被忽略,
                    // 与 perips/rom.v 把 we 丢掉的行为一致。
                    dpayload <= rom[(da-ROM_BASE)>>2];
                end else begin
                    $fatal(1, "Invalid data access %h", da);
                end
            end
            if (dbusy) begin
                if (dcount == 0) begin
                    dbusy  <= 0;
                    dvalid <= 1;
                    ddata  <= dpayload;
                end else dcount <= dcount - 1;
            end
            if (dvalid && dq) begin
                dvalid <= 0;
                ddata  <= 32'hxxxxxxxx;
                if (completing) begin
                    if (status !== 1) $fatal(1, "Program FAIL code=%h pc=%h", status, ia);
                    if (expected_stores >= 0 && stores != expected_stores)
                        $fatal(1, "Store count %0d expected %0d", stores, expected_stores);
                    $display("PASS CPU %s I=%0d D=%0d seed=%0d cycles=%0d stores=%0d", rom_path,
                             I_DELAY, D_DELAY, SEED, cycles, stores);
                    test_pass = 1;
                    $finish;
                end
            end
        end
    // load 在 EX 提交, 结果晚一拍以上才从寄存器堆第二个写口写回: 这一行等写回时再补上值和换行
    reg log_wait_load = 0;
    always @(posedge clk)
        if (rst_n) begin
            if (commit_log_fd != 0) begin
                if (log_wait_load && dut.ex_load_we) begin
                    if (dut.ex_load_waddr < 10)
                        $fwrite(commit_log_fd, " x%0d  0x%08h\n", dut.ex_load_waddr, dut.ex_load_wdata);
                    else $fwrite(commit_log_fd, " x%0d 0x%08h\n", dut.ex_load_waddr, dut.ex_load_wdata);
                    log_wait_load = 0;
                end
                if (dut.ie_inst_o != 32'h00000000 && dut.ie_inst_o != 32'h00000013 &&
                    dut.ctrl_stall_o[`STALL_EX] == 0) begin
                    // 没有真指令的时候不打印, 在等数据的时候不打印
                    // 会跳过真的nop, 需要时后续加一个valid?
                    $fwrite(commit_log_fd, "core   0: 3 0x%h (0x%h)", dut.ie_dec_pc_o,
                            dut.ie_inst_o);
                    if (dut.ex_reg_we_o == 1 && dut.ex_reg_waddr_o != 0)
                        if (dut.ex_reg_waddr_o < 10)
                            $fwrite(
                                commit_log_fd,
                                " x%0d  0x%08h",
                                dut.ex_reg_waddr_o,
                                dut.ex_reg_wdata_o
                            );
                        else
                            $fwrite(
                                commit_log_fd,
                                " x%0d 0x%08h",
                                dut.ex_reg_waddr_o,
                                dut.ex_reg_wdata_o
                            );
                    // 写非x0寄存器时
                    if (dut.ie_inst_o[6:0] == 7'b0000011 && dut.ie_inst_o[11:7] != 0) log_wait_load = 1;
                    else $fwrite(commit_log_fd, "\n");
                end
            end
        end
endmodule
