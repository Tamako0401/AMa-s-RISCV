`timescale 1ns / 1ps
module ov7670_sccb_tb #(
    parameter DIVIDER = 250,
    parameter RESET_DELAY = 500000
);
    reg clk = 0;
    reg rst_n = 0;
    reg sda_in = 0;
    wire scl_low, sda_low, done, error;
    reg [7:0] sent [0:11];
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
        if (error || sent_count != 12)
            $fatal(1, "SCCB init done=%b error=%b bytes=%0d", done, error, sent_count);
        expect_byte(0, 8'h42); expect_byte(1, 8'h12); expect_byte(2, 8'h80);
        expect_byte(3, 8'h42); expect_byte(4, 8'h12); expect_byte(5, 8'h04);
        expect_byte(6, 8'h42); expect_byte(7, 8'h40); expect_byte(8, 8'hD0);
        expect_byte(9, 8'h42); expect_byte(10, 8'h3A); expect_byte(11, 8'h04);
        $display("[result] OV7670 SCCB reset, RGB mode, RGB565 and byte order registers");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "OV7670 SCCB test timed out");
    end
endmodule
