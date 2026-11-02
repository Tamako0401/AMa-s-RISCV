// 检查自动测量、整帧提交、切模式隔离以及小窗的异步读口。
`timescale 1ns / 1ps
module input_tb;
    parameter W = 800, H = 600, HT = 1056, VT = 628;
    localparam ALT_H = H == 480 ? 500 : H-20;
    reg clk = 0, rclk = 0, rst_n = 0;
    always #10 clk = ~clk;
    always #6.734006734 rclk = ~rclk;
    wire pclk, de;
    wire [23:0] rgb;
    video_source #(.W(W), .H(H), .H_TOTAL(HT), .V_TOTAL(VT),
        .HALF_PERIOD(W == 1280 ? 6.734006734 : W == 640 ? 20.0 : 12.5)) source (.pclk(pclk), .de(de), .rgb(rgb));
    reg [31:0] addr = 0;
    reg valid = 0;
    wire ready, rsp;
    wire [31:0] rdata;
    reg [14:0] raddr = 0;
    wire [7:0] q;
    vision dut (.clk(clk), .rst_n(rst_n), .addr_i(addr), .data_i(32'hff8080), .sel_i(4'hf),
        .we_i(addr == 0), .data_o(rdata), .req_valid_i(valid), .req_ready_o(ready),
        .rsp_valid_o(rsp), .rsp_ready_i(1'b1), .vin_pclk(pclk), .vin_de(de), .vin_rgb(rgb),
        .win_rclk(rclk), .win_raddr(raddr), .win_rdata(q),
        .nn_valid(), .nn_sof(), .nn_eol(), .nn_data(), .nn_boundary(), .nn_commit());
    task automatic access(input integer a);
        @(negedge clk); addr = a; valid = 1;
        do @(posedge clk); while (!ready);
        @(negedge clk); valid = 0;
        if (!rsp) $fatal(1, "没有响应");
    endtask
    task automatic read_size(input integer width, input integer height, input integer status);
        access(24);
        if (rdata != (height<<16 | width)) $fatal(1, "尺寸 %08h 期望 %0dx%0d", rdata, width, height);
        access(28);
        if (rdata != status) $fatal(1, "状态 %0d 期望 %0d", rdata, status);
    endtask
    task automatic check_window(input integer width, input integer height);
        integer x, y, i, r, g, b;
        reg [23:0] p;
        reg [7:0] want;
        for (y=0; y<120; y++) for (x=0; x<160; x++) begin
            r=0; g=0; b=0;
            for (i=0; i<16; i++) begin
                p = source.pattern((width-640)/2+x*4+i%4, (height-480)/2+y*4+i/4);
                r += p[23:16]; g += p[15:8]; b += p[7:0];
            end
            r /= 16; g /= 16; b /= 16;
            want = {r[7:5], g[7:5], b[7:6]};
            @(negedge rclk); raddr = y*160+x;
            @(posedge rclk); #1;
            if (q !== want) $fatal(1, "小窗 (%0d,%0d) 实际 %02h 期望 %02h", x,y,q,want);
        end
    endtask
    integer old_frame, toggles = 0;
    reg mt = 0;
    always @(posedge clk) if (dut.measured_s[2] != mt) begin
        toggles++; mt = dut.measured_s[2];
    end
    task automatic measurements(input integer n);
        integer target;
        target = toggles+n;
        wait(toggles >= target); repeat(8) @(negedge clk);
    endtask
    initial begin
        repeat (6) @(negedge clk); rst_n = 1;
        access(0);
        wait (dut.frame >= 2);
        read_size(W,H,3);
        if (dut.count != 19200 || dut.sum_x != 1526400 || dut.sum_y != 1142400)
            $fatal(1, "完整帧颜色统计错误 %0d %0d %0d", dut.count, dut.sum_x, dut.sum_y);
        check_window(W,H);
        // 帧中一行短一个像素: 不得把不等宽的帧提交为完整图。
        do @(posedge pclk); while (source.h != 0 || source.v != 0);
        repeat(16) @(negedge clk); old_frame = dut.frame;
        do @(posedge pclk); while (source.h != 0 || source.v != H/2);
        source.active_w = W-1;
        do @(posedge pclk); while (source.h != 0 || source.v != H/2+1);
        source.active_w = W;
        measurements(1);
        read_size(W,H,4);
        if (dut.frame != old_frame) $fatal(1, "坏行帧发布了结果");
        check_window(W,H);
        wait(dut.frame > old_frame);
        // 高度在 ROI 下边之后才缩短: 已写后台的像素也不能发布。
        source.set_mode(W,ALT_H,HT,VT);
        repeat(16) @(negedge clk); old_frame = dut.frame;
        measurements(2);
        if (dut.frame != old_frame) $fatal(1, "高度过渡帧发布了结果");
        source.set_mode(320,240,HT,VT);
        repeat(16) @(negedge clk); old_frame = dut.frame;
        measurements(3);
        read_size(320,240,4);
        if (dut.frame != old_frame) $fatal(1, "不支持的尺寸发布了结果");
        // 切小尺寸前 H-20 的第 3 帧已验证通过, 应保留它。
        check_window(W,ALT_H);
        source.set_mode(W,H,HT,VT);
        old_frame = dut.frame;
        wait(dut.frame > old_frame);
        read_size(W,H,3); check_window(W,H);
        $display("[result] %0dx%0d 尺寸寄存器/19200 点/全部小窗像素/坏行/高度过渡/小尺寸/恢复", W,H);
        $finish;
    end
    initial begin #400000000; $fatal(1, "输入测试超时"); end
endmodule
