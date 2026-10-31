// 真实视频前端接 NN, 检查完整 RGB888 与抓帧的隔离边界。
`timescale 1ns / 1ps
module capture_tb;
    parameter W = 1280, H = 720, HT = 1650, VT = 750;
    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;
    wire pclk, de;
    wire [23:0] rgb;
    video_source #(.W(W), .H(H), .H_TOTAL(HT), .V_TOTAL(VT),
        .HALF_PERIOD(W == 1280 ? 6.734006734 : 12.5)) source (.pclk(pclk), .de(de), .rgb(rgb));
    wire valid, sof, eol, boundary, commit;
    wire [23:0] pixel;
    vision vision_dut (.clk(clk), .rst_n(rst_n), .addr_i(32'b0), .data_i(32'b0), .sel_i(4'b0),
        .we_i(1'b0), .req_valid_i(1'b0), .rsp_ready_i(1'b1), .data_o(), .req_ready_o(), .rsp_valid_o(),
        .vin_pclk(pclk), .vin_de(de), .vin_rgb(rgb), .win_rclk(clk), .win_raddr(15'b0), .win_rdata(),
        .nn_valid(valid), .nn_sof(sof), .nn_eol(eol), .nn_data(pixel), .nn_boundary(boundary), .nn_commit(commit));
    reg [31:0] addr = 0, data = 0;
    reg req = 0, we = 0;
    wire ready, rsp, busy, done;
    wire [31:0] rdata;
    nn dut (.clk(clk), .rst_n(rst_n), .addr_i(addr), .data_i(data), .sel_i(4'hf), .we_i(we),
        .req_valid_i(req), .req_ready_o(ready), .rsp_valid_o(rsp), .rsp_ready_i(1'b1), .data_o(rdata),
        .busy_o(busy), .done_o(done), .vin_pclk(pclk), .vin_valid(valid), .vin_sof(sof), .vin_eol(eol),
        .vin_data(pixel), .vin_boundary(boundary), .vin_commit(commit));
    task automatic access(input bit wr, input integer a, input integer d);
        @(negedge clk); addr=a; data=d; we=wr; req=1;
        do @(posedge clk); while (!ready);
        @(negedge clk); req=0; we=0;
        if (!rsp) $fatal(1,"总线没有响应");
    endtask
    task automatic capture;
        access(1,0,4);
        access(0,4,0);
        if (rdata[3:0] != 5) $fatal(1,"抓帧状态 %h",rdata);
    endtask
    task automatic check_pixels(input integer width, input integer height);
        integer x,y,i,r,g,b;
        reg [23:0] p;
        reg [31:0] want;
        for(y=0;y<120;y++) for(x=0;x<160;x++) begin
            r=0; g=0; b=0;
            for(i=0;i<16;i++) begin
                p=source.pattern((width-640)/2+x*4+i%4,(height-480)/2+y*4+i/4);
                r+=int'(p[23:16]); g+=int'(p[15:8]); b+=int'(p[7:0]);
            end
            want={8'b0,8'(r/16)^8'h80,8'(g/16)^8'h80,8'(b/16)^8'h80};
            if(dut.u_in_ram.mem[y*160+x] !== want)
                $fatal(1,"输入 (%0d,%0d)=%h 期望 %h",x,y,dut.u_in_ram.mem[y*160+x],want);
        end
    endtask
    integer starts=0, busy_pixels=0;
    reg was_busy=0;
    always @(posedge clk) if(rst_n) begin
        was_busy <= busy;
        if(busy && !was_busy) starts++;
        if(busy && dut.in_we) $fatal(1,"推理期间输入 RAM 被写");
    end
    always @(posedge pclk) if(busy && valid) busy_pixels++;
    task automatic rejected(input integer old_starts);
        wait(!dut.capture_r); repeat(8) @(negedge clk);
        access(0,4,0);
        if(rdata[3:0] != 8 || starts != old_starts || done)
            $fatal(1,"坏帧触发推理/完成: status=%h starts=%0d",rdata,starts);
    endtask
    initial begin
        repeat(6) @(negedge clk); rst_n=1;
        wait(vision_dut.frame>=1);
        // 在帧中请求, 必须等下一完整帧; 忙时的 IN/START/CAPTURE 都不能抢走 RAM。
        do @(posedge pclk); while(source.h!=0 || source.v!=H/2);
        capture();
        access(1,8,32'h123456);
        access(1,0,5);
        wait(busy); #1; check_pixels(W,H);
        access(1,8,32'habcdef);
        access(1,0,5);
        wait(done); #1; check_pixels(W,H);
        if(busy_pixels==0 || starts!=1) $fatal(1,"未覆盖推理与新帧重叠");
        $display("[result] %0dx%0d 全部 19200 RGB888/XOR 像素一致; 推理隔离 (%0d 个新像素)",W,H,busy_pixels);
        capture();
        source.set_mode(W,H,HT,VT);
        do @(posedge pclk); while(source.h!=0 || source.v!=H/2);
        source.active_w=W-1;
        do @(posedge pclk); while(source.h!=0 || source.v!=H/2+1);
        source.active_w=W;
        rejected(1);
        wait(vision_dut.stable);
        capture();
        source.set_mode(W,H-20,HT,VT);
        rejected(1);
        source.set_mode(320,240,HT,VT);
        repeat(3) begin @(posedge boundary); @(negedge pclk); end
        capture(); rejected(1);
        source.set_mode(W,H,HT,VT);
        wait(vision_dut.stable);
        capture(); wait(busy); #1; check_pixels(W,H); wait(done);
        if(starts!=2) $fatal(1,"恢复后的推理次数 %0d",starts);
        $display("[result] 坏行/ROI 后高度变化/不支持尺寸均拒绝; 恢复后自动推理完成");
        $finish;
    end
    initial begin #500000000; $fatal(1,"抓帧测试超时"); end
endmodule
