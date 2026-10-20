// ifu 单元测试: 随机 flush / 停顿 / 总线延迟下检查取指队列的正确性。
//
// 检查的不变量:
//   1. 交付的 (pc, inst) 永远配对: inst 必须等于 mem[pc];
//   2. 没有 flush 时 PC 顺序 +4, flush 之后从目标地址重新开始 (不重不漏);
//   3. req_valid 拉高后到握手前地址保持, 不撤回首;
//   4. STALL_PC 不再阻塞取指 (只有 STALL_ID 会停下来等消费)。
//
// 参数: DEPTH / STALL_WINDOW / RDELAY / BACK2BACK / SEED, 由 tests.toml 的 -G 传入。
`timescale 1ns / 1ps
`include "defines.v"
module ifu_tb;
    parameter [31:0] RESET_PC = 32'h0000_0100;  // 非零, 顺带检查复位地址
    parameter integer DEPTH = 4;
    parameter integer STALL_WINDOW = 2;
    parameter integer RDELAY = 1;      // 1 = 与真实 ROM 相同, 次拍返回
    parameter integer BACK2BACK = 0;   // 1 = 每拍都能接受请求的假想专用端口
    parameter integer SEED = 1;
    parameter integer TARGET = 5000;   // 交付多少条指令后结束
    parameter integer CYCLES = 200000;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg flush_i = 0;
    reg [31:0] flush_addr = 32'h0;
    reg [`STALL_WIDTH-1:0] stall = {`STALL_WIDTH{1'b0}};
    reg jtag_halt = 0;

    wire [31:0] inst, pc;
    wire inst_valid;
    wire [31:0] addr;
    wire req_valid, req_ready, rsp_valid, rsp_ready;
    wire [31:0] ibus_data_o;
    wire [3:0] ibus_sel;
    wire ibus_we;

    ifu #(
        .RESET_PC(RESET_PC),
        .FETCH_DEPTH(DEPTH),
        .STALL_WINDOW(STALL_WINDOW)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .flush_i(flush_i),
        .flush_addr_i(flush_addr),
        .stall_i(stall),
        .jtag_halt_i(jtag_halt),
        .inst_o(inst),
        .pc_o(pc),
        .inst_valid_o(inst_valid),
        .ibus_addr_o(addr),
        .ibus_data_i(rsp_data),
        .ibus_data_o(ibus_data_o),
        .ibus_sel_o(ibus_sel),
        .ibus_we_o(ibus_we),
        .req_valid_o(req_valid),
        .req_ready_i(req_ready),
        .rsp_valid_i(rsp_valid),
        .rsp_ready_o(rsp_ready)
    );

    // 指令存储: 内容由地址唯一决定, 便于发现 PC 和指令错配
    localparam integer MEMW = 1024;
    reg [31:0] mem[0:MEMW-1];
    integer k;
    initial for (k = 0; k < MEMW; k = k + 1) mem[k] = 32'hC0DE_0000 ^ (k << 2);

    // 从设备模型: BACK2BACK=0 时与真实 ROM 一致 (次拍返回), 否则每拍都能接受
    reg [31:0] rsp_data;
    reg busy = 0, rsp_valid_r = 0;
    integer cnt = 0;
    reg [31:0] saved_addr;
    integer gate;

    wire [31:0] waddr = addr[31:2];
    assign req_ready = rst_n && !busy && !rsp_valid_r && (BACK2BACK != 0 || gate == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0;
            rsp_valid_r <= 0;
            cnt <= 0;
            rsp_data <= 32'h0;
        end else if (BACK2BACK != 0) begin
            rsp_valid_r <= req_valid && req_ready;
            rsp_data <= mem[waddr % MEMW];
        end else begin
            if (rsp_valid_r && rsp_ready) rsp_valid_r <= 0;
            if (req_valid && req_ready) begin
                if (RDELAY <= 1) begin
                    rsp_valid_r <= 1;
                    rsp_data <= mem[waddr % MEMW];
                end else begin
                    busy <= 1;
                    cnt <= RDELAY - 1;
                    saved_addr <= addr;
                end
            end else if (busy) begin
                if (cnt <= 1) begin
                    busy <= 0;
                    rsp_valid_r <= 1;
                    rsp_data <= mem[saved_addr[31:2] % MEMW];
                end else begin
                    cnt <= cnt - 1;
                end
            end
        end
    end
    assign rsp_valid = rsp_valid_r;

    // 检查器
    reg [31:0] expect_pc;
    reg [31:0] held_addr;
    reg held_valid = 0;
    integer accepted = 0, flushes = 0, cycles = 0;
    integer pcstall_cycles = 0, pcstall_issues = 0;

    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (cycles > CYCLES) $fatal(1, "timeout: accepted=%0d pc=%h", accepted, pc);

        if (!rst_n) begin
            expect_pc <= RESET_PC;
            held_valid <= 0;
        end else begin
            // 3) 总线协议: 拉高未握手时 valid 和地址都不能变
            if (held_valid && (!req_valid || addr !== held_addr))
                $fatal(1, "unstable stalled fetch: valid=%b addr=%h held=%h", req_valid, addr, held_addr);
            held_valid <= req_valid && !req_ready;
            held_addr <= addr;

            if (rsp_valid && !rsp_ready) $fatal(1, "rsp_ready deasserted while rsp_valid");

            // 1)+2) 交付的指令必须与 pc 配对, 且 pc 顺序正确
            if (flush_i) begin
                expect_pc <= flush_addr;
                flushes <= flushes + 1;
            end else if (stall[`STALL_ID]) begin
                // 流水线冻结, 不消费
            end else if (inst_valid) begin
                if ((^inst) === 1'bx || (^pc) === 1'bx) $fatal(1, "unknown delivery");
                if (inst !== mem[pc[31:2] % MEMW])
                    $fatal(1, "inst mismatch pc=%h got=%h want=%h", pc, inst, mem[pc[31:2] % MEMW]);
                if (pc !== expect_pc)
                    $fatal(1, "pc order pc=%h want=%h accepted=%0d", pc, expect_pc, accepted);
                expect_pc <= pc + 32'd4;
                accepted <= accepted + 1;
            end

            if (req_valid && (addr[1:0] != 0 || addr >= (MEMW << 2)))
                $fatal(1, "bad fetch address %h", addr);
            if (req_valid && ibus_we) $fatal(1, "fetch asserted write enable");

            // 4) 只有 STALL_PC 时取指必须继续
            if (stall == `STALL_WIDTH'b0001 && !flush_i) begin
                pcstall_cycles <= pcstall_cycles + 1;
                if (req_valid && req_ready) pcstall_issues <= pcstall_issues + 1;
            end
        end
    end

    // 随机激励
    reg [31:0] rng = SEED;
    integer seed_arg;
    initial if ($value$plusargs("seed=%d", seed_arg)) rng = seed_arg;

    always @(posedge clk) if (rst_n) begin
        rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
        gate <= rng[3:2];
        // 0: 不暂停; 1: 只有 STALL_PC; 2+: 含 STALL_ID 的整条流水线暂停
        case (rng[5:4])
            2'd0: stall <= {`STALL_WIDTH{1'b0}};
            2'd1: stall <= `STALL_WIDTH'b0001;
            default: stall <= {`STALL_WIDTH{1'b1}};
        endcase
        flush_i <= 1'b0;
        if (rng[9:4] == 6'h0 && accepted > 4) begin
            flush_i <= 1'b1;
            flush_addr <= ((rng >> 10) % (MEMW / 4)) << 2;
        end
    end

    reg done = 0;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
    end

    always @(posedge clk) begin
        if (rst_n && accepted >= TARGET && !done) begin
            done = 1;
            if (pcstall_cycles > 100 && pcstall_issues < pcstall_cycles / 10)
                $fatal(1, "STALL_PC 仍在阻塞取指: cycles=%0d issues=%0d", pcstall_cycles, pcstall_issues);
            $display("[result] ifu DEPTH=%0d RDELAY=%0d BACK2BACK=%0d accepted=%0d flushes=%0d cycles=%0d",
                     DEPTH, RDELAY, BACK2BACK, accepted, flushes, cycles);
            $finish;
        end
    end
endmodule
