`timescale 1ns/1ps
module board_tb;
    reg clk=0;
    always #10 clk=~clk; // physical 50 MHz, real UART divisor
    reg key1_n=1, uart_rx=1;
    wire uart_tx;
    wire [7:0] led;
    wire lcd_sck, lcd_mosi, lcd_cs, lcd_dc, lcd_rst_n, lcd_bl;
    mes50hp_top dut(.*);
    defparam dut.soc.MEM_FILE = "sim.hex";
    localparam BIT_NS=8680;
    integer count=0;
    integer boots=0;
    reg [7:0] byte_rx;
    reg [7:0] expected [0:13];
    reg boot_done=0;
    reg saw_led2=0;
    initial begin
        expected[0]="A"; expected[1]="M"; expected[2]="A"; expected[3]=" ";
        expected[4]="C"; expected[5]="P"; expected[6]="U"; expected[7]=" ";
        expected[8]="P"; expected[9]="A"; expected[10]="S"; expected[11]="S";
        expected[12]=13; expected[13]=10;
    end
    // Decode serial output independently of the UART's internal registers.
    initial begin
        wait(dut.reset_pipe[15]);
        wait(uart_tx==1);
        forever begin
            @(negedge uart_tx);
            #(BIT_NS/2);
            if (uart_tx !== 0) $fatal(1,"Invalid start bit");
            for(integer b=0;b<8;b=b+1) begin
                #BIT_NS; byte_rx[b]=uart_tx;
            end
            #BIT_NS;
            if (uart_tx !== 1) $fatal(1,"Invalid stop bit");
            if(count<14) begin
                if(byte_rx !== expected[count]) $fatal(1,"UART byte %0d got %h expected %h",count,byte_rx,expected[count]);
            end else begin
                if(byte_rx !== 8'h5a) $fatal(1,"Echo mismatch %h",byte_rx);
                wait(saw_led2);
                $display("PASS board boot %0d: BSS/RAM/stack/byte masks, UART + Z echo, CPU GPIO",boots);
                if(boots==1) begin
                    $display("PASS board: power-on and KEY1 reset/reboot");
                    $finish;
                end
                boots=boots+1;
                @(negedge clk); key1_n=0;
                boot_done=0; saw_led2=0; count=-1;
                repeat(8) @(negedge clk);
                key1_n=1;
                wait(dut.reset_pipe[15]);
                wait(uart_tx==1);
            end
            count=count+1;
            if(count==14) boot_done=1;
        end
    end
    initial begin
        forever begin
            wait(boot_done);
            #(BIT_NS*2);
            uart_rx=0; #BIT_NS;
            for(integer b=0;b<8;b=b+1) begin uart_rx=(8'h5a>>b)&1; #BIT_NS; end
            uart_rx=1;
            wait(!boot_done);
        end
    end
    always @(posedge clk) begin
        if(dut.fault) $fatal(1,"SoC bus fault");
        if(led==2) saw_led2<=1;
    end
    initial begin #10000000; $fatal(1,"Board test timeout"); end
endmodule
