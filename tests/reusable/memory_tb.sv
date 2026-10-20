`timescale 1ns / 1ps
// 组件级回归: 哈佛式的 rom(只读、$readmemh 初始化) 与 ram(可读写、$readmemh 初值)
// 从设备。覆盖: 初值载入、握手时序、字节/半字掩码、ROM 只读、背压保持、
// 保持写请求不重复写入。
module memory_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    // ROM 端口
    reg [31:0] rom_addr = 0, rom_wdata = 0;
    reg [3:0] rom_sel = 0;
    reg rom_we = 0, rom_vld = 0, rom_rspr = 1;
    wire [31:0] rom_rdata;
    wire rom_rdy, rom_rspv;

    // ROM 取指口
    reg [31:0] romi_addr = 0;
    reg romi_vld = 0, romi_rspr = 1;
    wire [31:0] romi_rdata;
    wire romi_rdy, romi_rspv;

    // RAM 端口
    reg [31:0] ram_addr = 0, ram_wdata = 0;
    reg [3:0] ram_sel = 0;
    reg ram_we = 0, ram_vld = 0, ram_rspr = 1;
    wire [31:0] ram_rdata;
    wire ram_rdy, ram_rspv;

    rom #(
        .DP(8),
        .ROM_INIT_FILE("tests/reusable/rom_init.mem")
    ) u_rom (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(rom_addr),
        .data_i(rom_wdata),
        .sel_i(rom_sel),
        .we_i(rom_we),
        .data_o(rom_rdata),
        .req_valid_i(rom_vld),
        .req_ready_o(rom_rdy),
        .rsp_valid_o(rom_rspv),
        .rsp_ready_i(rom_rspr),
        .i_addr_i(romi_addr),
        .i_data_o(romi_rdata),
        .i_req_valid_i(romi_vld),
        .i_req_ready_o(romi_rdy),
        .i_rsp_valid_o(romi_rspv),
        .i_rsp_ready_i(romi_rspr)
    );

    ram #(
        .DP(8),
        .RAM_INIT_FILE("tests/reusable/ram_init.mem")
    ) u_ram (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(ram_addr),
        .data_i(ram_wdata),
        .sel_i(ram_sel),
        .we_i(ram_we),
        .data_o(ram_rdata),
        .req_valid_i(ram_vld),
        .req_ready_o(ram_rdy),
        .rsp_valid_o(ram_rspv),
        .rsp_ready_i(ram_rspr)
    );

    reg [31:0] result;
    reg [31:0] held;
    integer i;

    // 一次 ROM 访问; wr=1 用于验证写请求被忽略
    task static rom_access(input bit wr, input logic [31:0] off, input logic [31:0] value,
                           input logic [3:0] lanes);
        begin
            @(negedge clk);
            rom_addr = off;
            rom_wdata = value;
            rom_sel = lanes;
            rom_we = wr;
            rom_vld = 1'b1;
            #1;
            if (rom_rdy !== 1'b1) $fatal(1, "ROM request not ready");
            @(posedge clk);
            #1;
            if (rom_rspv !== 1'b1) $fatal(1, "ROM missing response");
            result = rom_rdata;
            @(negedge clk);
            rom_vld = 1'b0;
            rom_we  = 1'b0;
            @(posedge clk);
            #1;
            if (rom_rspv) $fatal(1, "ROM unexpected extra response");
        end
    endtask

    // 一次 ROM 取指口读; 与数据口完全独立
    task static rom_ifetch(input logic [31:0] off);
        begin
            @(negedge clk);
            romi_addr = off;
            romi_vld = 1'b1;
            #1;
            if (romi_rdy !== 1'b1) $fatal(1, "ROM ifetch request not ready");
            @(posedge clk);
            #1;
            if (romi_rspv !== 1'b1) $fatal(1, "ROM ifetch missing response");
            result = romi_rdata;
            @(negedge clk);
            romi_vld = 1'b0;
            @(posedge clk);
            #1;
            if (romi_rspv) $fatal(1, "ROM ifetch unexpected extra response");
        end
    endtask

    // 一次 RAM 访问
    task static ram_access(input bit wr, input logic [31:0] off, input logic [31:0] value,
                           input logic [3:0] lanes);
        begin
            @(negedge clk);
            ram_addr = off;
            ram_wdata = value;
            ram_sel = lanes;
            ram_we = wr;
            ram_vld = 1'b1;
            #1;
            if (ram_rdy !== 1'b1) $fatal(1, "RAM request not ready");
            @(posedge clk);
            #1;
            if (ram_rspv !== 1'b1) $fatal(1, "RAM missing response");
            result = ram_rdata;
            @(negedge clk);
            ram_vld = 1'b0;
            ram_we  = 1'b0;
            @(posedge clk);
            #1;
            if (ram_rspv) $fatal(1, "RAM unexpected extra response");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1;

        // ---- ROM: 读出 $readmemh 载入的初值 ----
        for (i = 0; i < 8; i = i + 1) begin
            rom_access(1'b0, i * 4, 32'h0, 4'b1111);
            if (result !== (32'hA5A50000 + i)) $fatal(1, "ROM read word %0d = %h", i, result);
        end

        // ---- ROM: 写请求被忽略 ----
        rom_access(1'b1, 32'h0, 32'hDEADBEEF, 4'b1111);
        rom_access(1'b0, 32'h0, 32'h0, 4'b1111);
        if (result !== 32'hA5A50000) $fatal(1, "ROM is not read-only: %h", result);

        // ---- ROM 取指口: 与数据口共享存储体 ----
        for (i = 0; i < 8; i = i + 1) begin
            rom_ifetch(i * 4);
            if (result !== (32'hA5A50000 + i)) $fatal(1, "ROM ifetch word %0d = %h", i, result);
        end

        // ---- ROM 两个口同拍访问: 互不阻塞, 各自返回自己的地址 ----
        @(negedge clk);
        rom_addr = 32'h8;
        rom_wdata = 32'h0;
        rom_sel = 4'b1111;
        rom_we = 1'b0;
        rom_vld = 1'b1;
        romi_addr = 32'h4;
        romi_vld = 1'b1;
        #1;
        if (rom_rdy !== 1'b1 || romi_rdy !== 1'b1)
            $fatal(1, "ROM ports not independent: data_rdy=%b ifetch_rdy=%b", rom_rdy, romi_rdy);
        @(posedge clk);
        #1;
        if (rom_rspv !== 1'b1 || romi_rspv !== 1'b1)
            $fatal(1, "ROM ports missing response: data=%b ifetch=%b", rom_rspv, romi_rspv);
        if (rom_rdata !== 32'hA5A50002 || romi_rdata !== 32'hA5A50001)
            $fatal(1, "ROM concurrent read wrong: data=%h ifetch=%h", rom_rdata, romi_rdata);
        @(negedge clk);
        rom_vld = 1'b0;
        romi_vld = 1'b0;
        @(posedge clk);
        #1;
        if (rom_rspv || romi_rspv) $fatal(1, "ROM response not cleared");

        // ---- RAM: 读出 $readmemh 载入的初值(必须在任何写之前) ----
        for (i = 0; i < 8; i = i + 1) begin
            ram_access(1'b0, i * 4, 32'h0, 4'b1111);
            if (result !== (32'h5A5A0000 + i)) $fatal(1, "RAM init word %0d = %h", i, result);
        end

        // ---- RAM: 整字读写 ----
        ram_access(1'b1, 32'h4, 32'h12345678, 4'b1111);
        ram_access(1'b0, 32'h4, 32'h0, 4'b1111);
        if (result !== 32'h12345678) $fatal(1, "RAM word readback = %h", result);

        // ---- RAM: 字节掩码 ----
        ram_access(1'b1, 32'h0, 32'hFFFFFFFF, 4'b1111);
        ram_access(1'b1, 32'h0, 32'h000000AA, 4'b0001);
        ram_access(1'b1, 32'h0, 32'h0000BB00, 4'b0010);
        ram_access(1'b1, 32'h0, 32'h00CC0000, 4'b0100);
        ram_access(1'b1, 32'h0, 32'hDD000000, 4'b1000);
        ram_access(1'b0, 32'h0, 32'h0, 4'b1111);
        if (result !== 32'hDDCCBBAA) $fatal(1, "RAM byte mask failed: %h", result);

        // ---- RAM: 半字掩码与地址不串扰 ----
        ram_access(1'b1, 32'h8, 32'hFFFFFFFF, 4'b1111);
        ram_access(1'b1, 32'h8, 32'h0000BEEF, 4'b0011);
        ram_access(1'b0, 32'h8, 32'h0, 4'b1111);
        if (result !== 32'hFFFFBEEF) $fatal(1, "RAM halfword mask failed: %h", result);
        ram_access(1'b1, 32'hc, 32'hCAFEBABE, 4'b1111);
        ram_access(1'b0, 32'h8, 32'h0, 4'b1111);
        if (result !== 32'hFFFFBEEF) $fatal(1, "RAM word 0x8 clobbered by neighbour");
        ram_access(1'b0, 32'hc, 32'h0, 4'b1111);
        if (result !== 32'hCAFEBABE) $fatal(1, "RAM word 0xc readback = %h", result);

        // ---- RAM: 响应未被消费时必须保持, 且不再接受新请求 ----
        ram_rspr = 1'b0;
        @(negedge clk);
        ram_addr = 32'h4;
        ram_wdata = 32'h0;
        ram_sel = 4'b1111;
        ram_we = 1'b0;
        ram_vld = 1'b1;
        #1;
        if (ram_rdy !== 1'b1) $fatal(1, "RAM read not ready under backpressure");
        @(posedge clk);
        #1;
        if (ram_rspv !== 1'b1) $fatal(1, "RAM missing response under backpressure");
        held = ram_rdata;
        repeat (3) @(posedge clk);
        #1;
        if (ram_rspv !== 1'b1) $fatal(1, "RAM response was dropped");
        if (ram_rdata !== held) $fatal(1, "RAM response data changed while held");
        if (ram_rdy !== 1'b0) $fatal(1, "RAM accepted a second request while holding");
        @(negedge clk);
        ram_vld = 1'b0;
        @(negedge clk);
        ram_rspr = 1'b1;
        @(posedge clk);
        #1;
        if (ram_rspv) $fatal(1, "RAM response not cleared after consume");

        // ---- RAM: 保持写请求期间只能写入一次 ----
        ram_rspr = 1'b0;
        @(negedge clk);
        ram_addr = 32'h10;
        ram_wdata = 32'h00000001;
        ram_sel = 4'b1111;
        ram_we = 1'b1;
        ram_vld = 1'b1;
        #1;
        if (ram_rdy !== 1'b1) $fatal(1, "RAM write not ready");
        @(posedge clk);
        #1;
        if (ram_rspv !== 1'b1) $fatal(1, "RAM missing write response");
        repeat (4) @(posedge clk);
        #1;
        if (ram_rdy !== 1'b0) $fatal(1, "RAM write request re-accepted while pending");
        @(negedge clk);
        ram_vld = 1'b0;
        ram_we  = 1'b0;
        @(negedge clk);
        ram_rspr = 1'b1;
        @(posedge clk);
        #1;
        if (ram_rspv) $fatal(1, "RAM write response not cleared");
        ram_access(1'b0, 32'h10, 32'h0, 4'b1111);
        if (result !== 32'h00000001) $fatal(1, "RAM held write result = %h", result);

        $display(
            "PASS memory: ROM/RAM init, ROM read-only, RAM word/byte/halfword, backpressure, single write");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
