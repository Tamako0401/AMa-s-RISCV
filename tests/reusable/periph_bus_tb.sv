`timescale 1ns/1ps
// periph_bus: 路由、地址裁剪、响应送回、上游/下游背压、空口返回 0、同时最多选中一个口.
// 下游是 3 个行为级外设: 读回 {口号, 收到的偏移}, 并记录最后一次写.
module periph_bus_tb;
    localparam N = 3;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg [31:0] addr = 0, data = 0;
    reg [3:0] sel = 0;
    reg we = 0, req_valid = 0, rsp_ready = 1;
    wire [31:0] rdata;
    wire req_ready, rsp_valid;

    wire [N*32-1:0] p_addr, p_wdata, p_rdata;
    wire [N*4-1:0] p_sel;
    wire [N-1:0] p_we, p_req_valid, p_req_ready, p_rsp_valid, p_rsp_ready;

    periph_bus #(.N(N)) dut(
        .clk(clk), .rst_n(rst_n),
        .addr_i(addr), .data_i(data), .sel_i(sel), .we_i(we), .data_o(rdata),
        .req_valid_i(req_valid), .req_ready_o(req_ready),
        .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready),
        .p_addr_o(p_addr), .p_data_o(p_wdata), .p_sel_o(p_sel), .p_we_o(p_we),
        .p_req_valid_o(p_req_valid), .p_req_ready_i(p_req_ready),
        .p_rsp_valid_i(p_rsp_valid), .p_rsp_ready_o(p_rsp_ready), .p_data_i(p_rdata)
    );

    // 行为级外设: 请求握手后等 delay[k] 拍给响应, 响应保持到 rsp_ready
    integer delay [0:N-1];
    reg [31:0] last_wdata [0:N-1];
    reg [3:0]  last_sel [0:N-1];
    integer    writes [0:N-1];
    genvar k;
    generate for (k = 0; k < N; k = k + 1) begin: g_slave
        reg busy = 0, valid = 0;
        reg [31:0] resp = 0;
        integer wait_cnt = 0;
        assign p_req_ready[k] = !busy;
        assign p_rsp_valid[k] = valid;
        assign p_rdata[k*32 +: 32] = valid ? resp : 32'hx;
        always @(posedge clk) begin
            if (valid && p_rsp_ready[k]) begin valid <= 0; busy <= 0; end
            if (busy && !valid) begin
                if (wait_cnt == 0) valid <= 1; else wait_cnt <= wait_cnt - 1;
            end
            if (p_req_valid[k] && p_req_ready[k]) begin
                if (p_addr[k*32+12 +: 20] !== 0) $fatal(1, "port %0d got untruncated address %h", k, p_addr[k*32 +: 32]);
                busy <= 1;
                wait_cnt <= delay[k];
                resp <= {8'h0, k[7:0], 4'h0, p_addr[k*32 +: 12]};
                if (p_we[k]) begin
                    last_wdata[k] <= p_wdata[k*32 +: 32];
                    last_sel[k] <= p_sel[k*4 +: 4];
                    writes[k] <= writes[k] + 1;
                end
            end
        end
    end endgenerate

    // 任意时刻最多一个口被请求、最多一个口被告知响应已取走
    always @(posedge clk) if (rst_n) begin
        if ($countones(p_req_valid) > 1) $fatal(1, "more than one port requested");
        if ($countones(p_rsp_ready) > 1) $fatal(1, "more than one port acknowledged");
    end

    // 一次完整访问: 请求保持到握手, 响应在 hold 拍后才取走
    task access(input [31:0] a, input w, input [31:0] d, input [3:0] s,
                input integer hold, output [31:0] result);
        integer guard;
        @(negedge clk);
        addr = a; we = w; data = d; sel = s; req_valid = 1; rsp_ready = (hold == 0);
        guard = 0;
        while (!req_ready) begin
            @(negedge clk); guard = guard + 1;
            if (guard > 50) $fatal(1, "request never accepted: %h", a);
        end
        @(posedge clk); #1;
        // 握手后上游地址会变(rib 会清零): 换到另一个口, 响应仍须来自原来的口
        req_valid = 0; we = 0; addr = a ^ 32'h0000_1000;
        guard = 0;
        while (!rsp_valid) begin
            @(posedge clk); #1; guard = guard + 1;
            if (guard > 50) $fatal(1, "no response: %h", a);
        end
        result = rdata;
        // 响应被拖住时: 数据保持不变, 也不接受新请求
        repeat (hold) begin
            @(posedge clk); #1;
            if (!rsp_valid || rdata !== result) $fatal(1, "response not held: %h", a);
            if (req_ready) $fatal(1, "accepted new request while response pending");
        end
        rsp_ready = 1;
        @(posedge clk); #1;
        if (rsp_valid) $fatal(1, "duplicate response: %h", a);
    endtask

    reg [31:0] r;
    integer i;
    integer test_pass = 0;
    initial begin
        for (i = 0; i < N; i = i + 1) begin delay[i] = 0; writes[i] = 0; end
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // 1) 每个口都能读到, 且地址只保留口内偏移
        for (i = 0; i < N; i = i + 1) begin
            access(32'h4000_0000 + i * 32'h1000 + 32'h10, 0, 0, 4'hf, 0, r);
            if (r !== {8'h0, i[7:0], 16'h0010}) $fatal(1, "port %0d read got %h", i, r);
        end
        access(32'h4000_2ffc, 0, 0, 4'hf, 0, r);
        if (r !== 32'h0002_0ffc) $fatal(1, "offset truncation got %h", r);

        // 2) 写只到达目标口, 数据和字节使能原样传递
        access(32'h4000_1004, 1, 32'hcafe_f00d, 4'b0110, 0, r);
        if (writes[0] != 0 || writes[1] != 1 || writes[2] != 0) $fatal(1, "write routing");
        if (last_wdata[1] !== 32'hcafe_f00d || last_sel[1] !== 4'b0110) $fatal(1, "write payload");

        // 3) 上游背压: 响应拖住 5 拍
        access(32'h4000_2008, 0, 0, 4'hf, 5, r);
        if (r !== 32'h0002_0008) $fatal(1, "held response got %h", r);

        // 4) 下游慢: 外设 4 拍后才给响应, 结果必须来自正确的口
        delay[1] = 4;
        access(32'h4000_1020, 0, 0, 4'hf, 2, r);
        if (r !== 32'h0001_0020) $fatal(1, "slow port got %h", r);
        delay[1] = 0;

        // 5) 空口: 读返回 0, 写不到达任何外设, 都不卡住
        access(32'h4000_5000, 0, 0, 4'hf, 0, r);
        if (r !== 0) $fatal(1, "unmapped read got %h", r);
        access(32'h4000_f004, 1, 32'h1234_5678, 4'hf, 3, r);
        if (r !== 0 || writes[0] + writes[1] + writes[2] != 1) $fatal(1, "unmapped write");

        // 6) 空口之后正常口照常工作
        access(32'h4000_0000, 0, 0, 4'hf, 0, r);
        if (r !== 32'h0000_0000) $fatal(1, "port 0 after unmapped got %h", r);

        $display("PASS periph_bus: routing, offset, write payload, backpressure, slow port, unmapped");
        test_pass = 1;
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
