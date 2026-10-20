`timescale 1ns / 1ps
module storage_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg we = 0;
    reg [4:0] wa = 0, ra = 0, rb = 0;
    reg [31:0] wd = 0;
    wire [31:0] qa, qb;
    gpr_reg rf (
        clk,
        rst_n,
        we,
        wa,
        wd,
        ra,
        qa,
        rb,
        qb
    );

    reg [3:0] addr = 0;
    reg [31:0] data = 0;
    reg [3:0] mask = 0;
    reg wr = 0;
    wire [31:0] dout;
    gen_ram #(
        .DP(16),
        .AW(4)
    ) ram (
        clk,
        addr,
        data,
        mask,
        wr,
        dout
    );

    reg vi = 0, ready = 0;
    wire ri0, vo0, ri1, vo1;
    vld_rdy #(
        .CUT_READY(0)
    ) flow0 (
        clk,
        rst_n,
        vi,
        ri0,
        ready,
        vo0
    );
    vld_rdy #(
        .CUT_READY(1)
    ) flow1 (
        clk,
        rst_n,
        vi,
        ri1,
        ready,
        vo1
    );
    reg  [7:0] sync_in = 0;
    wire [7:0] sync_out;
    gen_ticks_sync #(
        .DP(2),
        .DW(8)
    ) sync2 (
        rst_n,
        clk,
        sync_in,
        sync_out
    );
    reg flush = 0;
    wire [7:0] pipe_q;
    gen_pipe_dff #(8) pipe_ff (
        clk,
        rst_n,
        flush,
        8'h13,
        sync_in,
        pipe_q
    );
    wire [7:0] one_q, def_q;
    gen_rst_1_dff #(8) one_ff (
        clk,
        rst_n,
        sync_in,
        one_q
    );
    gen_rst_def_dff #(8) def_ff (
        clk,
        rst_n,
        8'h42,
        sync_in,
        def_q
    );

    task tick;
        @(posedge clk);
        #1;
    endtask
    integer i;
    initial begin
        tick();
        if (qa !== 0 || qb !== 0 || vo0 !== 0 || vo1 !== 0 ||
            sync_out !== 0 || pipe_q !== 8'h13 || one_q !== 8'hff || def_q !== 8'h42)
            $fatal(1, "reset/x0 failure");
        @(negedge clk);
        rst_n = 1;
        // All architectural registers, including attempted x0 writes.
        for (i = 0; i < 32; i = i + 1) begin
            wa = i;
            ra = i;
            rb = i;
            we = 1;
            wd = 32'h12340000 + i;
            #1;
            if (qa !== (i == 0 ? 0 : wd) || qb !== qa) $fatal(1, "register bypass failure x%0d", i);
            tick();
            @(negedge clk);
            we = 0;
            #1;
            if (qa !== (i == 0 ? 0 : wd)) $fatal(1, "register storage failure");
        end
        // No-reset register file must retain written values across reset.
        rst_n = 0;
        tick();
        @(negedge clk);
        rst_n = 1;
        ra = 31;
        #1;
        if (qa !== 32'h1234001f) $fatal(1, "upstream RF reset contract changed");
        // Word addressing, synchronous read address, byte-lane preservation.
        for (i = 0; i < 16; i = i + 1) begin
            addr = i;
            data = 32'h10203000 + i;
            mask = 15;
            wr   = 1;
            tick();
            @(negedge clk);
        end
        for (i = 0; i < 16; i = i + 1) begin
            addr = i;
            wr   = 0;
            tick();
            if (dout !== 32'h10203000 + i) $fatal(1, "RAM read mismatch");
            @(negedge clk);
        end
        addr = 3;
        wr   = 1;
        mask = 4'b0101;
        data = 32'haabbccdd;
        tick();
        @(negedge clk);
        wr = 0;
        tick();
        if (dout !== 32'h10bb30dd) $fatal(1, "RAM byte mask mismatch");
        @(negedge clk);
        addr = 4;
        #1;
        if (dout !== 32'h10bb30dd) $fatal(1, "RAM read was asynchronous");
        tick();
        if (dout !== 32'h10203004) $fatal(1, "RAM delayed address mismatch");

        @(negedge clk);
        vi = 1;
        ready = 0;
        tick();
        if (!vo0 || !vo1 || ri0 || ri1) $fatal(1, "flow fill failure");
        repeat (3) begin
            tick();
            if (!vo0 || !vo1 || ri0 || ri1) $fatal(1, "flow hold failure");
        end
        @(negedge clk);
        ready = 1;
        #1;
        if (!ri0 || ri1) $fatal(1, "CUT_READY semantics mismatch");
        tick();
        if (!vo0 || vo1) $fatal(1, "flow pop/refill mismatch");
        @(negedge clk);
        vi = 0;
        tick();
        if (vo0 || vo1) $fatal(1, "flow drain failure");
        @(negedge clk);
        sync_in = 8'ha5;
        tick();
        if (sync_out !== 0 || pipe_q !== 8'ha5) $fatal(1, "pipeline delay mismatch");
        @(negedge clk);
        flush = 1;
        tick();
        if (sync_out !== 8'ha5 || pipe_q !== 8'h13) $fatal(1, "flush is default, not hold");
        $display("PASS storage: GPR, RAM, handshake, DFF and synchronizer");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
