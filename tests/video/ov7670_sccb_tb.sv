`timescale 1ns / 1ps
module ov7670_sccb_tb #(
    parameter DIVIDER = 250,
    parameter RESET_DELAY = 500000
);
    reg clk = 0;
    reg rst_n = 0;
    reg sda_in = 0;
    wire scl_low, sda_low, done, error;
    reg [7:0] sent [0:127];
    integer sent_count = 0;

    always #10 clk = ~clk;

    ov7670_sccb_init #(
        .DIVIDER(DIVIDER),
        .RESET_DELAY(RESET_DELAY)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .sda_in(sda_in),
        .scl_low(scl_low),
        .sda_low(sda_low),
        .done(done),
        .error(error)
    );

    always @(posedge clk) begin
        if (rst_n && dut.state == 6 && dut.phase_tick) begin
            sent[sent_count] = dut.tx_byte;
            sent_count = sent_count + 1;
        end
    end

    task automatic expect_byte(input integer index, input [7:0] value);
        begin
            if (sent[index] !== value)
                $fatal(1, "SCCB byte %0d = %02h, expected %02h", index, sent[index], value);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        wait (done);
        if (error || sent_count != 90)
            $fatal(1, "SCCB init done=%b error=%b bytes=%0d", done, error, sent_count);
        expect_byte(0, 8'h42); expect_byte(1, 8'h12); expect_byte(2, 8'h80);
        expect_byte(3, 8'h42); expect_byte(4, 8'h12); expect_byte(5, 8'h04);
        expect_byte(6, 8'h42); expect_byte(7, 8'h40); expect_byte(8, 8'hD0);
        expect_byte(9, 8'h42); expect_byte(10, 8'h3A); expect_byte(11, 8'h04);
        /* 自动曝光/自动增益/自动白平衡必须打开, 否则画面很暗 */
        expect_byte(12, 8'h42); expect_byte(13, 8'h13); expect_byte(14, 8'hE7);
        expect_byte(15, 8'h42); expect_byte(16, 8'h6C); expect_byte(17, 8'h40);
        expect_byte(18, 8'h42); expect_byte(19, 8'h6D); expect_byte(20, 8'h40);
        expect_byte(21, 8'h42); expect_byte(22, 8'h6E); expect_byte(23, 8'h40);
        expect_byte(24, 8'h42); expect_byte(25, 8'h6F); expect_byte(26, 8'h40);
        /* gamma 曲线 0x7B..0x8B, 最后一条是 0x8B=0xD0 */
        expect_byte(27, 8'h42); expect_byte(28, 8'h7B); expect_byte(29, 8'h04);
        expect_byte(75, 8'h42); expect_byte(76, 8'h8B); expect_byte(77, 8'hD0);
        /* 亮度: 自动增益上限、自动曝光目标、亮度偏移 */
        expect_byte(78, 8'h42); expect_byte(79, 8'h0F); expect_byte(80, 8'h60);
        expect_byte(81, 8'h42); expect_byte(82, 8'h24); expect_byte(83, 8'h75);
        expect_byte(84, 8'h42); expect_byte(85, 8'h25); expect_byte(86, 8'h63);
        expect_byte(87, 8'h42); expect_byte(88, 8'h55); expect_byte(89, 8'h10);
        $display("[result] OV7670 SCCB: RGB565, AEC/AGC/AWB, gamma, AGC ceiling, AEC target, BRIGHT");
        $finish;
    end

    initial begin
        #60000000;
        $fatal(1, "OV7670 SCCB test timed out");
    end
endmodule
