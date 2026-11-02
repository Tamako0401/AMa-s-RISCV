// 断流不会把半帧提交; 强制 FIFO 溢出和跨域复位也必须拒绝。
`timescale 1ns / 1ps
module capture_cdc_tb;
    reg clk=0, pclk=0, run_clk=1, rst_n=0, request=0;
    always #10 if(run_clk) clk=~clk;
    always #6.734006734 pclk=~pclk;
    reg valid=0, sof=0, eol=0, boundary=0, commit=0;
    wire pixel_valid, done, ok;
    wire [23:0] pixel;
    nn_capture dut(.clk(clk),.rst_n(rst_n),.request(request),.pixel_valid(pixel_valid),.pixel_data(pixel),
        .done(done),.ok(ok),.pclk(pclk),.in_valid(valid),.in_sof(sof),.in_eol(eol),.in_data(24'h123456),
        .boundary(boundary),.commit(commit));
    integer completions=0;
    always @(posedge clk) if(rst_n && done) begin
        if(ok) $fatal(1,"无效帧被提交");
        completions++;
    end
    task automatic start_frame;
        @(negedge clk); request=~request;
        wait(dut.state==1);
        @(negedge pclk); boundary=1;
        @(negedge pclk); boundary=0;
    endtask
    task automatic send_pixel(input integer n);
        @(negedge pclk); valid=1; sof=n==0; eol=n%160==159;
        @(negedge pclk); valid=0; sof=0; eol=0;
        repeat(2) @(negedge pclk);
    endtask
    task automatic finish_frame;
        @(negedge pclk); boundary=1; commit=1;
        @(negedge pclk); boundary=0; commit=0;
    endtask
    initial begin
        repeat(6) @(negedge clk); rst_n=1;
        start_frame();
        for(integer i=0;i<80;i++) send_pixel(i);
        repeat(100) @(negedge clk);
        if(completions!=0 || dut.state!=2) $fatal(1,"断流提交了半帧");
        finish_frame();
        wait(completions==1);
        start_frame();
        @(negedge clk); run_clk=0;
        for(integer i=0;i<19200;i++) send_pixel(i);
        if(!dut.bad) $fatal(1,"没有检测 FIFO 溢出");
        finish_frame();
        run_clk=1;
        wait(completions==2);
        start_frame();
        for(integer i=0;i<8;i++) send_pixel(i);
        @(negedge clk); rst_n=0; request=0;
        repeat(6) @(negedge clk); rst_n=1;
        repeat(20) @(negedge clk);
        if(pixel_valid || done || dut.state!=0) $fatal(1,"复位残留跨域事件");
        $display("[result] 半帧断流保持等待/不足帧拒绝/FIFO 溢出拒绝/抓帧中复位通过");
        $finish;
    end
    initial begin #3000000; $fatal(1,"CDC 测试超时"); end
endmodule
