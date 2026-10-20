// axi_bridge 组件测试: RIB 从设备侧 <-> AXI 主设备侧 的协议转换。
//
// 覆盖:
//   - 字 / 半字 / 单字节读写, 四种字节通道各来一遍
//   - 读延迟与写延迟(由模型参数给出), 桥必须等待而不是抢拍
//   - RIB 响应背压: 响应必须保持, 不能被改写或重复
//   - 单次执行: 每一笔 RIB 事务只能产生一笔 AXI 事务(计数器核对)
//   - AXI 数据宽度 32 与 64 两种取值的字节通道定位
//   - 非 OKAY 响应上报到 error_o
`timescale 1ns / 1ps
module axi_bridge_tb;

    reg clk = 0;
    always #5 clk = ~clk;  // 100 MHz
    reg rst_n = 0;

    integer waited;

    // ================= 32 位 AXI 实例 =================

    reg [31:0] r32_addr = 0, r32_wdata = 0;
    reg [3:0] r32_sel = 0;
    reg r32_we = 0, r32_valid = 0, r32_rsp_ready = 0;
    wire [31:0] r32_rdata;
    wire r32_ready, r32_rsp_valid, r32_error;

    wire [3:0] a32_arid, a32_rid, a32_awid, a32_bid;
    wire [31:0] a32_araddr, a32_awaddr, a32_rdata, a32_wdata;
    wire [7:0] a32_arlen, a32_awlen;
    wire [2:0] a32_arsize, a32_awsize;
    wire [1:0] a32_arburst, a32_awburst, a32_rresp, a32_bresp;
    wire a32_arvalid, a32_arready, a32_rvalid, a32_rready, a32_rlast;
    wire a32_awvalid, a32_awready, a32_wvalid, a32_wready, a32_wlast;
    wire a32_bvalid, a32_bready;
    wire [3:0] a32_wstrb;
    reg        inject32 = 0;

    integer a32_ar_count = 0, a32_aw_count = 0, a32_w_count = 0;
    always @(posedge clk) begin
        if (a32_arvalid && a32_arready) a32_ar_count <= a32_ar_count + 1;
        if (a32_awvalid && a32_awready) a32_aw_count <= a32_aw_count + 1;
        if (a32_wvalid && a32_wready) a32_w_count <= a32_w_count + 1;
    end

    axi_bridge #(
        .AXI_ID_WIDTH  (4),
        .AXI_ADDR_WIDTH(32),
        .AXI_DATA_WIDTH(32)
    ) dut32 (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(r32_addr),
        .data_i(r32_wdata),
        .sel_i(r32_sel),
        .we_i(r32_we),
        .data_o(r32_rdata),
        .req_valid_i(r32_valid),
        .req_ready_o(r32_ready),
        .rsp_valid_o(r32_rsp_valid),
        .rsp_ready_i(r32_rsp_ready),
        .error_o(r32_error),
        .m_axi_arid(a32_arid),
        .m_axi_araddr(a32_araddr),
        .m_axi_arlen(a32_arlen),
        .m_axi_arsize(a32_arsize),
        .m_axi_arburst(a32_arburst),
        .m_axi_arvalid(a32_arvalid),
        .m_axi_arready(a32_arready),
        .m_axi_rid(a32_rid),
        .m_axi_rdata(a32_rdata),
        .m_axi_rresp(a32_rresp),
        .m_axi_rlast(a32_rlast),
        .m_axi_rvalid(a32_rvalid),
        .m_axi_rready(a32_rready),
        .m_axi_awid(a32_awid),
        .m_axi_awaddr(a32_awaddr),
        .m_axi_awlen(a32_awlen),
        .m_axi_awsize(a32_awsize),
        .m_axi_awburst(a32_awburst),
        .m_axi_awvalid(a32_awvalid),
        .m_axi_awready(a32_awready),
        .m_axi_wdata(a32_wdata),
        .m_axi_wstrb(a32_wstrb),
        .m_axi_wlast(a32_wlast),
        .m_axi_wvalid(a32_wvalid),
        .m_axi_wready(a32_wready),
        .m_axi_bid(a32_bid),
        .m_axi_bresp(a32_bresp),
        .m_axi_bvalid(a32_bvalid),
        .m_axi_bready(a32_bready)
    );

    axi_slave_model #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .ID_WIDTH(4),
        .WORDS(256),
        .RD_LATENCY(3),
        .WR_LATENCY(2)
    ) slv32 (
        .clk(clk),
        .rst_n(rst_n),
        .arid(a32_arid),
        .araddr(a32_araddr),
        .arlen(a32_arlen),
        .arsize(a32_arsize),
        .arburst(a32_arburst),
        .arvalid(a32_arvalid),
        .arready(a32_arready),
        .rid(a32_rid),
        .rdata(a32_rdata),
        .rresp(a32_rresp),
        .rlast(a32_rlast),
        .rvalid(a32_rvalid),
        .rready(a32_rready),
        .awid(a32_awid),
        .awaddr(a32_awaddr),
        .awlen(a32_awlen),
        .awsize(a32_awsize),
        .awburst(a32_awburst),
        .awvalid(a32_awvalid),
        .awready(a32_awready),
        .wdata(a32_wdata),
        .wstrb(a32_wstrb),
        .wlast(a32_wlast),
        .wvalid(a32_wvalid),
        .wready(a32_wready),
        .bid(a32_bid),
        .bresp(a32_bresp),
        .bvalid(a32_bvalid),
        .bready(a32_bready),
        .inject_error(inject32)
    );

    // ================= 64 位 AXI 实例 =================
    // 验证一个 RIB 事务只落在 64 位数据的其中一个 4 字节通道上

    reg [31:0] r64_addr = 0, r64_wdata = 0;
    reg [3:0] r64_sel = 0;
    reg r64_we = 0, r64_valid = 0, r64_rsp_ready = 0;
    wire [31:0] r64_rdata;
    wire r64_ready, r64_rsp_valid, r64_error;

    wire [3:0] a64_arid, a64_rid, a64_awid, a64_bid;
    wire [31:0] a64_araddr, a64_awaddr;
    wire [63:0] a64_rdata, a64_wdata;
    wire [7:0] a64_arlen, a64_awlen, a64_wstrb;
    wire [2:0] a64_arsize, a64_awsize;
    wire [1:0] a64_arburst, a64_awburst, a64_rresp, a64_bresp;
    wire a64_arvalid, a64_arready, a64_rvalid, a64_rready, a64_rlast;
    wire a64_awvalid, a64_awready, a64_wvalid, a64_wready, a64_wlast;
    wire a64_bvalid, a64_bready;

    axi_bridge #(
        .AXI_ID_WIDTH  (4),
        .AXI_ADDR_WIDTH(32),
        .AXI_DATA_WIDTH(64)
    ) dut64 (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(r64_addr),
        .data_i(r64_wdata),
        .sel_i(r64_sel),
        .we_i(r64_we),
        .data_o(r64_rdata),
        .req_valid_i(r64_valid),
        .req_ready_o(r64_ready),
        .rsp_valid_o(r64_rsp_valid),
        .rsp_ready_i(r64_rsp_ready),
        .error_o(r64_error),
        .m_axi_arid(a64_arid),
        .m_axi_araddr(a64_araddr),
        .m_axi_arlen(a64_arlen),
        .m_axi_arsize(a64_arsize),
        .m_axi_arburst(a64_arburst),
        .m_axi_arvalid(a64_arvalid),
        .m_axi_arready(a64_arready),
        .m_axi_rid(a64_rid),
        .m_axi_rdata(a64_rdata),
        .m_axi_rresp(a64_rresp),
        .m_axi_rlast(a64_rlast),
        .m_axi_rvalid(a64_rvalid),
        .m_axi_rready(a64_rready),
        .m_axi_awid(a64_awid),
        .m_axi_awaddr(a64_awaddr),
        .m_axi_awlen(a64_awlen),
        .m_axi_awsize(a64_awsize),
        .m_axi_awburst(a64_awburst),
        .m_axi_awvalid(a64_awvalid),
        .m_axi_awready(a64_awready),
        .m_axi_wdata(a64_wdata),
        .m_axi_wstrb(a64_wstrb),
        .m_axi_wlast(a64_wlast),
        .m_axi_wvalid(a64_wvalid),
        .m_axi_wready(a64_wready),
        .m_axi_bid(a64_bid),
        .m_axi_bresp(a64_bresp),
        .m_axi_bvalid(a64_bvalid),
        .m_axi_bready(a64_bready)
    );

    axi_slave_model #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(64),
        .ID_WIDTH(4),
        .WORDS(256),
        .RD_LATENCY(2),
        .WR_LATENCY(2)
    ) slv64 (
        .clk(clk),
        .rst_n(rst_n),
        .arid(a64_arid),
        .araddr(a64_araddr),
        .arlen(a64_arlen),
        .arsize(a64_arsize),
        .arburst(a64_arburst),
        .arvalid(a64_arvalid),
        .arready(a64_arready),
        .rid(a64_rid),
        .rdata(a64_rdata),
        .rresp(a64_rresp),
        .rlast(a64_rlast),
        .rvalid(a64_rvalid),
        .rready(a64_rready),
        .awid(a64_awid),
        .awaddr(a64_awaddr),
        .awlen(a64_awlen),
        .awsize(a64_awsize),
        .awburst(a64_awburst),
        .awvalid(a64_awvalid),
        .awready(a64_awready),
        .wdata(a64_wdata),
        .wstrb(a64_wstrb),
        .wlast(a64_wlast),
        .wvalid(a64_wvalid),
        .wready(a64_wready),
        .bid(a64_bid),
        .bresp(a64_bresp),
        .bvalid(a64_bvalid),
        .bready(a64_bready),
        .inject_error(1'b0)
    );


    // ================= 访问任务 =================
    // 全部在 negedge 驱动与采样, 避开 posedge 上 valid/ready 的竞争

    task static access32(input logic wr, input logic [31:0] a, input logic [31:0] wd,
                         input logic [3:0] be, input integer hold, output logic [31:0] rd);
        begin
            @(negedge clk);
            r32_addr = a;
            r32_wdata = wd;
            r32_sel = be;
            r32_we = wr;
            r32_valid = 1;
            r32_rsp_ready = 0;

            waited = 0;
            while (!r32_ready) begin
                waited = waited + 1;
                if (waited > 2000) $fatal(1, "32: request timeout");
                @(negedge clk);
            end
            @(posedge clk);  // 请求握手

            @(negedge clk);
            r32_valid = 0;
            r32_addr = 0;
            r32_wdata = 0;
            r32_sel = 0;
            r32_we = 0;

            waited = 0;
            while (!r32_rsp_valid) begin
                waited = waited + 1;
                if (waited > 2000) $fatal(1, "32: response timeout");
                @(negedge clk);
            end
            rd = r32_rdata;

            repeat (hold) begin
                @(negedge clk);
                if (!r32_rsp_valid || r32_rdata !== rd)
                    $fatal(1, "32: response changed while stalled");
            end

            r32_rsp_ready = 1;
            @(posedge clk);  // 响应握手
            @(negedge clk);
            if (r32_rsp_valid) $fatal(1, "32: duplicate response");
            r32_rsp_ready = 0;
        end
    endtask

    task static access64(input logic [31:0] a, input logic [31:0] wd, input logic [3:0] be,
                         output logic [31:0] rd);
        begin
            @(negedge clk);
            r64_addr = a;
            r64_wdata = wd;
            r64_sel = be;
            r64_we = 1;
            r64_valid = 1;
            r64_rsp_ready = 0;

            waited = 0;
            while (!r64_ready) begin
                waited = waited + 1;
                if (waited > 2000) $fatal(1, "64: request timeout");
                @(negedge clk);
            end
            @(posedge clk);

            @(negedge clk);
            r64_valid = 0;
            r64_we = 0;

            waited = 0;
            while (!r64_rsp_valid) begin
                waited = waited + 1;
                if (waited > 2000) $fatal(1, "64: response timeout");
                @(negedge clk);
            end
            rd = r64_rdata;

            r64_rsp_ready = 1;
            @(posedge clk);
            @(negedge clk);
            if (r64_rsp_valid) $fatal(1, "64: duplicate response");
            r64_rsp_ready = 0;
        end
    endtask

    task static read64(input logic [31:0] a, output logic [31:0] rd);
        begin
            @(negedge clk);
            r64_addr = a;
            r64_we = 0;
            r64_valid = 1;
            r64_rsp_ready = 0;
            waited = 0;
            while (!r64_ready) begin
                waited = waited + 1;
                if (waited > 2000) $fatal(1, "64: request timeout");
                @(negedge clk);
            end
            @(posedge clk);
            @(negedge clk);
            r64_valid = 0;
            waited = 0;
            while (!r64_rsp_valid) begin
                waited = waited + 1;
                if (waited > 2000) $fatal(1, "64: response timeout");
                @(negedge clk);
            end
            rd = r64_rdata;
            r64_rsp_ready = 1;
            @(posedge clk);
            @(negedge clk);
            if (r64_rsp_valid) $fatal(1, "64: duplicate response");
            r64_rsp_ready = 0;
        end
    endtask


    // ================= 主测试 =================

    reg [31:0] got;
    integer ar_before, aw_before;
    integer k;
    integer cases = 0;

    initial begin
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // ---- 预置存储器内容(直接按层次写模型内部的数组)----
        slv32.mem[0] = 32'h11223344;  // 0x00
        slv32.mem[1] = 32'h55667788;  // 0x04
        slv32.mem[2] = 32'h9abcdef0;  // 0x08

        // ---- 1. 字读 ----
        ar_before = a32_ar_count;
        access32(0, 32'h0000_0000, 0, 4'hf, 0, got);
        if (got !== 32'h11223344) $fatal(1, "word read got %h", got);
        if (a32_ar_count - ar_before !== 1)
            $fatal(1, "read issued %0d AXI reads", a32_ar_count - ar_before);
        cases = cases + 1;

        // ---- 2. 字节通道 0: 只应改最低字节 ----
        aw_before = a32_aw_count;
        access32(1, 32'h0000_0004, 32'h000000aa, 4'h1, 0, got);
        if (a32_aw_count - aw_before !== 1)
            $fatal(1, "write issued %0d AXI writes", a32_aw_count - aw_before);
        if (a32_w_count - aw_before !== 1)
            $fatal(1, "write issued %0d W beats", a32_w_count - aw_before);
        access32(0, 32'h0000_0004, 0, 4'hf, 0, got);
        if (got !== 32'h556677aa) $fatal(1, "byte0 write got %h", got);
        cases = cases + 1;

        // ---- 3. 字节通道 1 ----
        access32(1, 32'h0000_0004, 32'h0000bb00, 4'h2, 0, got);
        access32(0, 32'h0000_0004, 0, 4'hf, 0, got);
        if (got !== 32'h5566bbaa) $fatal(1, "byte1 write got %h", got);
        cases = cases + 1;

        // ---- 4. 字节通道 2 ----
        access32(1, 32'h0000_0004, 32'h00cc0000, 4'h4, 0, got);
        access32(0, 32'h0000_0004, 0, 4'hf, 0, got);
        if (got !== 32'h55ccbbaa) $fatal(1, "byte2 write got %h", got);
        cases = cases + 1;

        // ---- 5. 字节通道 3 ----
        access32(1, 32'h0000_0004, 32'hdd000000, 4'h8, 0, got);
        access32(0, 32'h0000_0004, 0, 4'hf, 0, got);
        if (got !== 32'hddccbbaa) $fatal(1, "byte3 write got %h", got);
        cases = cases + 1;

        // ---- 6. 半字写(低半字), 高半字应保持 ----
        access32(1, 32'h0000_0004, 32'h00001234, 4'h3, 0, got);
        access32(0, 32'h0000_0004, 0, 4'hf, 0, got);
        if (got !== 32'hddcc1234) $fatal(1, "low halfword write got %h", got);
        cases = cases + 1;

        // ---- 7. 半字写(高半字), 低半字应保持 ----
        access32(1, 32'h0000_0004, 32'h56780000, 4'hc, 0, got);
        access32(0, 32'h0000_0004, 0, 4'hf, 0, got);
        if (got !== 32'h56781234) $fatal(1, "high halfword write got %h", got);
        cases = cases + 1;

        // ---- 8. 字写 ----
        access32(1, 32'h0000_0008, 32'hdeadbeef, 4'hf, 0, got);
        access32(0, 32'h0000_0008, 0, 4'hf, 0, got);
        if (got !== 32'hdeadbeef) $fatal(1, "word write got %h", got);
        cases = cases + 1;

        // ---- 9. 响应背压: 保持 5 拍, 内容与 valid 都不能变 ----
        access32(0, 32'h0000_0000, 0, 4'hf, 5, got);
        if (got !== 32'h11223344) $fatal(1, "backpressure read got %h", got);
        cases = cases + 1;

        // ---- 10. 写响应背压 ----
        access32(1, 32'h0000_000c, 32'h0badf00d, 4'hf, 5, got);
        access32(0, 32'h0000_000c, 0, 4'hf, 0, got);
        if (got !== 32'h0badf00d) $fatal(1, "backpressure write got %h", got);
        cases = cases + 1;

        // ---- 11. 连续 16 个字, 每笔恰好一笔 AXI 事务 ----
        ar_before = a32_ar_count;
        aw_before = a32_aw_count;
        for (k = 0; k < 16; k = k + 1) begin
            access32(1, 32'h0000_0100 + k * 4, 32'hdead0000 + k, 4'hf, 0, got);
        end
        for (k = 0; k < 16; k = k + 1) begin
            access32(0, 32'h0000_0100 + k * 4, 0, 4'hf, 0, got);
            if (got !== (32'hdead0000 + k)) $fatal(1, "burst word %0d got %h", k, got);
        end
        if (a32_aw_count - aw_before !== 16)
            $fatal(1, "16 writes produced %0d AXI writes", a32_aw_count - aw_before);
        if (a32_ar_count - ar_before !== 16)
            $fatal(1, "16 reads produced %0d AXI reads", a32_ar_count - ar_before);
        cases = cases + 32;

        // ---- 12. 64 位数据宽度: 同一地址的两个 4 字节通道互不串扰 ----
        // 0x200 落在 64 位字的低半, 0x204 落在高半
        access64(32'h0000_0200, 32'h11112222, 4'hf, got);
        read64(32'h0000_0200, got);
        if (got !== 32'h11112222) $fatal(1, "64 low lane got %h", got);
        cases = cases + 1;

        access64(32'h0000_0204, 32'h33334444, 4'hf, got);
        read64(32'h0000_0200, got);
        if (got !== 32'h11112222) $fatal(1, "64 low lane clobbered: %h", got);
        read64(32'h0000_0204, got);
        if (got !== 32'h33334444) $fatal(1, "64 high lane got %h", got);
        cases = cases + 2;

        // 64 位下的单字节写: 地址 0x206 是 64 位字里的第 6 字节,
        // 它同时是低 4 字节通道的字节偏移 2, 所以 sel=4'h4、数据在高位字节上
        access64(32'h0000_0206, 32'h00550000, 4'h4, got);
        read64(32'h0000_0204, got);
        if (got !== 32'h33554444) $fatal(1, "64 high byte write got %h", got);
        cases = cases + 1;

        // ---- 13. 错误上报: 非 OKAY 响应置位 error_o 并保持 ----
        if (r32_error !== 1'b0) $fatal(1, "error_o set before injection");
        inject32 = 1;
        access32(0, 32'h0000_0000, 0, 4'hf, 0, got);
        if (r32_error !== 1'b1) $fatal(1, "SLVERR was not reported");
        inject32 = 0;
        access32(0, 32'h0000_0000, 0, 4'hf, 0, got);
        if (r32_error !== 1'b1) $fatal(1, "error_o must stay sticky");
        if (r64_error !== 1'b0) $fatal(1, "64-bit error_o should stay clear");
        cases = cases + 1;

        $display(
            "PASS axi_bridge: %0d cases, byte lanes, backpressure, single-issue, 32/64-bit, SLVERR",
            cases);
        $finish;
    end

    // 超时保护: 任何一笔事务卡住都要显式失败, 而不是静默挂起
    initial begin
        #2000000;
        $fatal(1, "axi_bridge_tb: global timeout");
    end

endmodule
