`timescale 1ns / 1ps
module ov7670_tb;
    reg pclk = 0;
    reg rst_n = 0;
    reg vsync = 1;
    reg href = 0;
    reg [7:0] data = 0;
    wire valid, sof, eol;
    wire [23:0] rgb;

    always #10 pclk = ~pclk;

    ov7670_rgb565_rx dut (
        .clk(pclk),
        .rst_n(rst_n),
        .vsync(vsync),
        .href(href),
        .data(data),
        .out_valid(valid),
        .out_sof(sof),
        .out_eol(eol),
        .out_data(rgb)
    );

    reg [23:0] pixels [0:7];
    reg [7:0] markers [0:7];
    integer count = 0;

    always @(posedge pclk) begin
        #1;
        if (valid) begin
            pixels[count] = rgb;
            markers[count] = {6'b0, sof, eol};
            count = count + 1;
        end
    end

    task automatic send_byte(input [7:0] value);
        begin
            @(negedge pclk);
            data = value;
        end
    endtask

    task automatic send_line(input [31:0] bytes);
        begin
            @(negedge pclk);
            href = 1'b1;
            data = bytes[31:24];
            send_byte(bytes[23:16]);
            send_byte(bytes[15:8]);
            send_byte(bytes[7:0]);
            @(negedge pclk);
            href = 1'b0;
        end
    endtask

    task automatic send_odd_line(input [23:0] bytes);
        begin
            @(negedge pclk);
            href = 1'b1;
            data = bytes[23:16];
            send_byte(bytes[15:8]);
            send_byte(bytes[7:0]);
            @(negedge pclk);
            href = 1'b0;
        end
    endtask

    task automatic check_pixel(input integer index, input [23:0] value, input bit first, input bit last);
        begin
            if (pixels[index] !== value)
                $fatal(1, "pixel %0d = %06h, expected %06h", index, pixels[index], value);
            if (markers[index][1] !== first || markers[index][0] !== last)
                $fatal(1, "pixel %0d markers = %b, expected SOF=%b EOL=%b",
                    index, markers[index][1:0], first, last);
        end
    endtask

    initial begin
        repeat (4) @(negedge pclk);
        rst_n = 1'b1;
        repeat (2) @(negedge pclk);
        vsync = 1'b0;

        send_line(32'hF800_07E0);
        send_line(32'h001F_FFFF);
        repeat (2) @(negedge pclk);
        if (count != 4) $fatal(1, "first frame pixel count %0d, expected 4", count);
        check_pixel(0, 24'hFF0000, 1, 0);
        check_pixel(1, 24'h00FF00, 0, 1);
        check_pixel(2, 24'h0000FF, 0, 0);
        check_pixel(3, 24'hFFFFFF, 0, 1);

        vsync = 1'b1;
        repeat (3) @(negedge pclk);
        vsync = 1'b0;
        repeat (2) @(negedge pclk);
        send_odd_line(24'hF80007);
        repeat (2) @(negedge pclk);
        if (count != 5) $fatal(1, "odd-byte line emitted %0d pixels, expected one", count-4);
        check_pixel(4, 24'hFF0000, 1, 1);

        $display("[result] OV7670 RGB565 byte pairing, RGB888 expansion, SOF/EOL and odd-byte discard");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "OV7670 adapter test timed out");
    end
endmodule
