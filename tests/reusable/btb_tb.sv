// btb 单元测试: 训练、命中、方向计数、冲突与旁路。
//
// 检查:
//   1. 复位后不命中, 预测"不跳";
//   2. 训练一次 taken 后立即命中并预测跳转, 目标正确;
//   3. 连续 not-taken 把 2-bit 计数器拉到 0, 之后预测"不跳";
//   4. 两个不同 PC 映射到同一索引时, tag 不匹配 -> 不命中 (不会用错目标);
//   5. 同一拍"查表 + 更新同一格"时, 查表看到的是更新后的结果 (write-through)。
`timescale 1ns / 1ps
module btb_tb;
    localparam integer ENTRIES = 32;
    localparam integer IDX_W = 5;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg [31:0] lookup_pc = 0;
    wire lookup_taken;
    wire [31:0] lookup_target;

    reg upd_en = 0;
    reg [31:0] upd_pc = 0;
    reg [31:0] upd_target = 0;
    reg upd_taken = 0;

    btb #(
        .ENTRIES(ENTRIES),
        .IDX_W  (IDX_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_pc(lookup_pc),
        .lookup_taken(lookup_taken),
        .lookup_target(lookup_target),
        .upd_en(upd_en),
        .upd_pc(upd_pc),
        .upd_target(upd_target),
        .upd_taken(upd_taken),
        .upd_kind(2'd0),
        .lookup_kind()
    );

    integer errors = 0;

    task check_hit(input [31:0] pc, input exp_taken, input [31:0] exp_target, input [127:0] what);
        begin
            lookup_pc = pc;
            #1;
            if (lookup_taken !== exp_taken) begin
                $display("FAIL %0s: pc=%h taken=%b expect=%b", what, pc, lookup_taken, exp_taken);
                errors = errors + 1;
            end
            if (exp_taken && lookup_target !== exp_target) begin
                $display("FAIL %0s: pc=%h target=%h expect=%h", what, pc, lookup_target, exp_target);
                errors = errors + 1;
            end
        end
    endtask

    task train(input [31:0] pc, input [31:0] target, input taken);
        begin
            @(negedge clk);
            upd_pc     = pc;
            upd_target = target;
            upd_taken  = taken;
            upd_en     = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            upd_en = 1'b0;
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1;

        // 1. 复位后不命中
        check_hit(32'h0000_0100, 1'b0, 32'h0, "cold miss");

        // 2. 训练一次 taken -> 立刻预测跳
        train(32'h0000_0100, 32'h0000_0040, 1'b1);
        check_hit(32'h0000_0100, 1'b1, 32'h0000_0040, "after one taken");

        // 3. 2-bit 饱和计数器: 分配时为 2(弱跳), 每次 not-taken 减 1
        //    2 -> 预测跳; 1 -> 预测不跳; 0 -> 预测不跳
        train(32'h0000_0100, 32'h0000_0040, 1'b0);  // 2 -> 1
        check_hit(32'h0000_0100, 1'b0, 32'h0, "counter=1 not taken");
        train(32'h0000_0100, 32'h0000_0040, 1'b0);  // 1 -> 0
        check_hit(32'h0000_0100, 1'b0, 32'h0, "counter=0 not taken");
        // 再训练两次 taken 才回到"预测跳" (0 -> 1 -> 2)
        train(32'h0000_0100, 32'h0000_0040, 1'b1);  // 0 -> 1
        check_hit(32'h0000_0100, 1'b0, 32'h0, "counter=1 after one taken");
        train(32'h0000_0100, 32'h0000_0040, 1'b1);  // 1 -> 2
        check_hit(32'h0000_0100, 1'b1, 32'h0000_0040, "retrained");

        // 4. 同索引不同 PC: tag 不匹配, 不能命中
        //    索引取 pc[6:2], 0x100 和 0x120 索引相同 (0x100>>2=0x40, 0x120>>2=0x48,
        //    低 5 位分别是 0 和 8 -> 不同; 用 0x100 和 0x300 保证同索引)
        check_hit(32'h0000_0100 + 32'h80, 1'b0, 32'h0, "index alias cold");

        // 5. 同一拍查表 + 更新同一格: 查表应看到新值
        //    先让 0x200 冷, 然后在查 0x200 的同一拍训练它
        lookup_pc = 32'h0000_0200;
        #1;
        if (lookup_taken !== 1'b0) begin
            $display("FAIL write-through: 0x200 should be cold");
            errors = errors + 1;
        end
        @(negedge clk);
        upd_pc     = 32'h0000_0200;
        upd_target = 32'h0000_0300;
        upd_taken  = 1'b1;
        upd_en     = 1'b1;
        lookup_pc  = 32'h0000_0200;  // 同拍查同一格
        #1;
        if (lookup_taken !== 1'b1 || lookup_target !== 32'h0000_0300) begin
            $display("FAIL write-through: taken=%b target=%h expect 1/%h", lookup_taken, lookup_target,
                     32'h0000_0300);
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        @(negedge clk);
        upd_en = 1'b0;
        #1;
        check_hit(32'h0000_0200, 1'b1, 32'h0000_0300, "write-through persisted");

        // 6. 不跳且未命中时不分配表项
        check_hit(32'h0000_0400, 1'b0, 32'h0, "alloc-target cold");
        train(32'h0000_0400, 32'h0000_0500, 1'b0);
        check_hit(32'h0000_0400, 1'b0, 32'h0, "not-taken miss must not allocate");

        if (errors == 0) begin
            $display("[result] btb all checks passed");
            $finish;
        end else begin
            $fatal(1, "btb: %0d check(s) failed", errors);
        end
    end
endmodule
