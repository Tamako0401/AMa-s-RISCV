`timescale 1ns / 1ps
// handnet 加速器的数值测试: 走总线把整张画面写进输入 RAM -> 启动 -> 轮询 -> 读 300 个字,
// 和 model/nnref.py 算出来的标准答案逐字节比较。
//
//   +in=<文件>   120*160*3 字节的 RGB888 原图 (tests/nn/in.raw)
//   +exp=<文件>  300 字 x 16 字节的期望输出 (tests/nn/expect.raw)
//
// 两个文件都由 model/nn_export.py 生成, 换权重后重新生成即可。
module nn_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg [31:0] addr_i = 0;
    reg [31:0] data_i = 0;
    reg [3:0] sel_i = 0;
    reg we_i = 0;
    reg req_valid_i = 0;
    wire [31:0] data_o;
    wire req_ready_o, rsp_valid_o;
    wire busy_o, done_o;

    nn u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr_i(addr_i),
        .data_i(data_i),
        .sel_i(sel_i),
        .we_i(we_i),
        .data_o(data_o),
        .req_valid_i(req_valid_i),
        .req_ready_o(req_ready_o),
        .rsp_valid_o(rsp_valid_o),
        .rsp_ready_i(1'b1),
        .busy_o(busy_o),
        .done_o(done_o)
    );

    localparam [11:0] R_CTRL = 12'h000;
    localparam [11:0] R_STATUS = 12'h004;
    localparam [11:0] R_IN = 12'h008;
    localparam [11:0] R_OUT_ADDR = 12'h010;
    localparam [11:0] R_OUT = 12'h014;
    localparam [11:0] R_CYCLE = 12'h018;
    localparam [11:0] R_IN_PIX = 12'h020;

    task automatic bus_write(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            addr_i = a;
            data_i = d;
            we_i = 1;
            sel_i = 4'hf;
            req_valid_i = 1;
            @(negedge clk);
            req_valid_i = 0;
            we_i = 0;
            if (!rsp_valid_o) $fatal(1, "写 %h 没有响应", a);
            @(negedge clk);
        end
    endtask

    task automatic bus_read(input [31:0] a, output [31:0] d);
        begin
            @(negedge clk);
            addr_i = a;
            data_i = 0;
            we_i = 0;
            sel_i = 4'hf;
            req_valid_i = 1;
            @(negedge clk);
            req_valid_i = 0;
            if (!rsp_valid_o) $fatal(1, "读 %h 没有响应", a);
            d = data_o;
            @(negedge clk);
        end
    endtask

    reg [7:0] img[0:120*160*3-1];
    reg [7:0] golden[0:300*16-1];

    integer fd, i, px, py, n;
    integer verbose = 0;

    // +verbose: 每层开始时打印这一层的尺寸和源缓冲的头几个字, 对不上时方便定位
    always @(posedge clk) begin
        if (rst_n && verbose && u_dut.state == 3'd1) begin
            $display("第 %0d 层 out=%0dx%0d cout=%0d k=%0d src_base=%0d", u_dut.layer,
                     u_dut.cfg_out_w, u_dut.cfg_out_h, u_dut.cfg_cout, u_dut.cfg_k, u_dut.src_base);
            if (u_dut.layer != 4'd0)
                $display("   源缓冲前 3 字: %h %h %h", u_dut.u_feat.mem[u_dut.src_base],
                         u_dut.u_feat.mem[u_dut.src_base + 13'd1],
                         u_dut.u_feat.mem[u_dut.src_base + 13'd2]);
        end
    end

    string path;
    reg [31:0] v, status;
    integer errors = 0;

    initial begin
        if (!$value$plusargs("in=%s", path)) $fatal(1, "缺少 +in=");
        fd = $fopen(path, "rb");
        if (fd == 0) $fatal(1, "打不开 %0s", path);
        for (i = 0; i < 120 * 160 * 3; i = i + 1) img[i] = $fgetc(fd);
        $fclose(fd);
        if (!$value$plusargs("exp=%s", path)) $fatal(1, "缺少 +exp=");
        fd = $fopen(path, "rb");
        if (fd == 0) $fatal(1, "打不开 %0s", path);
        for (i = 0; i < 300 * 16; i = i + 1) golden[i] = $fgetc(fd);
        $fclose(fd);

        verbose = $test$plusargs("verbose");
        repeat (5) @(negedge clk);
        rst_n = 1;

        bus_read(R_IN_PIX, v);
        if (v != 19200) $fatal(1, "IN_PIX = %0d", v);

        // 整张画面一个一个像素写进去
        for (py = 0; py < 120; py = py + 1) begin
            for (px = 0; px < 160; px = px + 1) begin
                n = (py * 160 + px) * 3;
                bus_write({20'h0, R_IN}, {8'h0, img[n], img[n + 1], img[n + 2]});
            end
        end
        bus_write({20'h0, R_CTRL}, 32'd1);

        // 轮询到完成
        status = 0;
        for (i = 0; i < 4000000 && !(status[1] && !status[0]); i = i + 1) bus_read({20'h0, R_STATUS}, status);
        if (!status[1]) $fatal(1, "推理没有完成, STATUS=%h", status);
        bus_read({20'h0, R_CYCLE}, v);
        $display("[result] 推理完成, 用 %0d 拍", v);

        // 逐字比较前 4 个通道
        for (i = 0; i < 300; i = i + 1) begin
            bus_write({20'h0, R_OUT_ADDR}, i[31:0]);
            bus_read({20'h0, R_OUT}, v);
            if (v[7:0] !== golden[i * 16 + 0] || v[15:8] !== golden[i * 16 + 1] ||
                v[23:16] !== golden[i * 16 + 2] || v[31:24] !== golden[i * 16 + 3]) begin
                if (errors < 5)
                    $display("字 %0d: 得到 %h%h%h%h, 期望 %h%h%h%h", i,
                             v[7:0], v[15:8], v[23:16], v[31:24],
                             golden[i * 16 + 0], golden[i * 16 + 1], golden[i * 16 + 2], golden[i * 16 + 3]);
                errors = errors + 1;
            end
        end
        if (errors != 0) $fatal(1, "%0d 个字和参考实现不一致", errors);
        $display("[result] 300 个字全部一致");
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "timeout");
    end
endmodule
