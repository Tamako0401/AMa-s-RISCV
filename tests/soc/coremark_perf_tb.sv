// CoreMark 流水线效率监视器 (仿真里的 "ILA"): 在 start_time..stop_time 之间, 逐拍看 EX 级在干什么并归因。
//
// 和 coremark_tb 一样跑 sw/app/coremark, 存储全在片内, 周期数与实机相同。
// 计时区间: EX 级退休的第一条 `csrr rd, cycle` 开始, 第二条结束 (start_time / stop_time 各读一次)。
//
// 每拍归入一类 (加起来等于区间总拍数):
//   退休        EX 里是有效指令且没被 hold
//   load / store 等待、乘除等待   EX 被 hold (exu_mem / exu_muldiv)
//   冲刷气泡    跳转预测错 (或没预测) 后 EX 里的空拍, 按引起冲刷的指令分 分支 / jal / jalr / 其他
//   load-use    ID 等 load 写回而送进 EX 的气泡
//   取指气泡    取指队列这一拍没给出指令
// 气泡的来源用影子标签记录, 跟着 ifu_idu、idu_exu 两级寄存器一起走 (使能条件与 RTL 相同)。
//
// +trace=<文件>: 把区间内 +trace_from (默认 0) 起 +trace_len (默认 20000) 拍的流水线状态写成 CSV, 画波形用。
`timescale 1ns / 1ps
module coremark_perf_tb;
    parameter VIDEO_720P = 0;
    reg pixel_clk = 0;
    always #6.734006734 pixel_clk = ~pixel_clk;
    parameter [31:0] TOHOST_ADDR = 32'h10000000;
    parameter integer MAX_CYCLES = 400000000;

    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    `include "boards/mes50hp/pins_top.vh"

    soc_top #(
        .VIDEO_720P(VIDEO_720P),
        .IO_N(`IO_N),
        .UART_TX_PIN(`UART_TX_PIN),
        .UART_RX_PIN(`UART_RX_PIN)
    ) u_soc (
        .video_clk(pixel_clk),
        .clk(clk),
        .rst_n(rst_n),
        .io_o(),
        .io_oe(),
        .io_i(128'd1 << `UART_RX_PIN)
    );

    // ---- 探针 ----
    wire flush = u_soc.u_core.ctrl_flush_o;
    wire [3:0] stall = u_soc.u_core.ctrl_stall_o;
    wire if_valid = u_soc.u_core.ifetch_inst_valid_o;
    wire [31:0] if_pc = u_soc.u_core.ifetch_pc_o;
    wire if_pred = u_soc.u_core.ifetch_pred_taken_o;
    wire [31:0] id_pc = u_soc.u_core.if_inst_addr_o;
    wire [31:0] ex_pc = u_soc.u_core.ie_dec_pc_o;
    wire [31:0] ex_inst = u_soc.u_core.ie_inst_o;
    wire ex_pred = u_soc.u_core.ie_pred_taken_o;
    wire hold = u_soc.u_core.ex_hold_flag_o;
    wire md_st = u_soc.u_core.u_exu.muldiv_stall_o;
    wire mem_st = u_soc.u_core.u_exu.mem_stall_o;
    wire lu = u_soc.u_core.load_use_stall;
    wire id_st = u_soc.u_core.id_stall_o;
    wire dv = u_soc.u_core.dbus_req_valid_o, dr = u_soc.u_core.dbus_req_ready_i;
    wire drsp = u_soc.u_core.dbus_rsp_valid_i;
    wire dwe = u_soc.u_core.dbus_we_o;
    wire [31:0] da = u_soc.u_core.dbus_addr_o;

    // ---- 影子标签 ----
    localparam T_VALID = 0, T_BR = 1, T_JAL = 2, T_JALR = 3, T_OTHER = 4, T_LU = 5, T_IDST = 6, T_FETCH = 7;
    wire [6:0] ex_opc = ex_inst[6:0];
    wire [2:0] flush_cause = ex_opc == 7'b1100011 ? T_BR : ex_opc == 7'b1101111 ? T_JAL :
                             ex_opc == 7'b1100111 ? T_JALR : T_OTHER;
    reg [2:0] id_tag = T_OTHER, ex_tag = T_OTHER, refetch = T_FETCH;  // refetch: 冲刷后到第一条有效指令前的气泡算谁的
    always @(posedge clk) begin
        if (flush) refetch <= flush_cause;
        else if (if_valid && (!stall[2])) refetch <= T_FETCH;
        if (!stall[2] || flush) id_tag <= flush ? flush_cause : if_valid ? T_VALID : refetch;
        if (!stall[3] || flush) ex_tag <= flush ? flush_cause : stall[2] ? (lu ? T_LU : T_IDST) : id_tag;
    end

    // ---- 计时区间 ----
    wire retire = rst_n && !hold && ex_tag == T_VALID;
    wire is_rdcycle = ex_inst[6:0] == 7'b1110011 && ex_inst[14:12] == 3'b010 && ex_inst[31:20] == 12'hc00;
    reg on = 0, done = 0;
    integer marks = 0;
    longint total = 0, n_ret = 0, c_ld = 0, c_st = 0, c_md = 0, c_hold = 0;
    longint c_tag[8];
    longint n_br = 0, n_jal = 0, n_jalr = 0, n_ld = 0, n_st = 0, n_mul = 0, n_div = 0;
    longint f_cnt[8];  // 冲刷次数, 按原因
    initial for (int i = 0; i < 8; i++) begin c_tag[i] = 0; f_cnt[i] = 0; end

    integer tf = 0;
    longint t_from = 0, t_len = 20000;
    string trace_path;

    always @(posedge clk) if (rst_n) begin
        if (dv && dr && dwe && da == TOHOST_ADDR) begin
            if (u_soc.u_core.dbus_data_o != 1) $fatal(1, "coremark: CRC or score failed");
            done <= 1;
        end
        if (retire && is_rdcycle) begin
            marks = marks + 1;
            on <= marks == 1;
        end
        if (on) begin
            if (tf != 0 && total >= t_from && total < t_from + t_len)
                $fwrite(tf, "%0d,%h,%0d,%0d,%h,%0d,%h,%h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                        total, if_pc, if_valid, if_pred, id_pc, id_tag, ex_pc, ex_inst, ex_tag, ex_pred,
                        flush, lu, hold, mem_st, md_st, dv, dr, drsp, dwe);
            total++;
            if (flush) f_cnt[flush_cause]++;
            if (hold) begin
                if (md_st) c_md++;
                else if (mem_st) begin if (dwe) c_st++; else c_ld++; end
                else c_hold++;
            end else c_tag[ex_tag]++;
            if (retire) begin
                n_ret++;
                case (ex_opc)
                    7'b1100011: n_br++;
                    7'b1101111: n_jal++;
                    7'b1100111: n_jalr++;
                    7'b0000011: n_ld++;
                    7'b0100011: n_st++;
                    7'b0110011: if (ex_inst[25]) begin if (ex_inst[14]) n_div++; else n_mul++; end
                    default: ;
                endcase
            end
        end
        if (total == MAX_CYCLES) $fatal(1, "coremark: timeout");
    end

    function automatic void line(string name, longint v);
        $display("  %-24s %10d  %6.2f%%", name, v, 100.0 * v / total);
    endfunction

    reg [1023:0] rom_path;
    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) $fatal(1, "Missing +rom=hex");
        if ($value$plusargs("trace=%s", trace_path)) begin
            tf = $fopen(trace_path, "w");
            $fwrite(tf, "cyc,if_pc,if_valid,if_pred,id_pc,id_tag,ex_pc,ex_inst,ex_tag,ex_pred,flush,lu,hold,mem_st,md_st,dv,dr,drsp,dwe\n");
        end
        void'($value$plusargs("trace_from=%d", t_from));
        void'($value$plusargs("trace_len=%d", t_len));
        $readmemh(rom_path, u_soc.u_rom.mem);
        repeat (5) @(posedge clk);
        rst_n = 1;
        wait (done);
        if (tf != 0) $fclose(tf);
        if (marks < 2) $fatal(1, "coremark_perf: 没找到两条 csrr cycle (%0d)", marks);
        $display("计时区间 %0d 拍, 退休 %0d 条, CPI %.4f", total, n_ret, 1.0 * total / n_ret);
        line("退休", c_tag[T_VALID]);
        line("load 等待", c_ld);
        line("store 等待", c_st);
        line("乘除等待", c_md);
        line("其他 hold", c_hold);
        line("冲刷气泡: 条件分支", c_tag[T_BR]);
        line("冲刷气泡: jal", c_tag[T_JAL]);
        line("冲刷气泡: jalr", c_tag[T_JALR]);
        line("冲刷气泡: 其他", c_tag[T_OTHER]);
        line("load-use 气泡", c_tag[T_LU]);
        line("ID 其他停顿", c_tag[T_IDST]);
        line("取指气泡", c_tag[T_FETCH]);
        $display("冲刷次数: 分支 %0d, jal %0d, jalr %0d, 其他 %0d", f_cnt[T_BR], f_cnt[T_JAL], f_cnt[T_JALR], f_cnt[T_OTHER]);
        $display("指令: 分支 %0d, jal %0d, jalr %0d, load %0d, store %0d, mul %0d, div %0d",
                 n_br, n_jal, n_jalr, n_ld, n_st, n_mul, n_div);
        $display("[result] CPI %.4f, 分支预测错 %.2f%%, load-use %.2f%%", 1.0 * total / n_ret,
                 100.0 * f_cnt[T_BR] / n_br, 100.0 * c_tag[T_LU] / total);
        $finish;
    end
endmodule
