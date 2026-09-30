`timescale 1ns/1ps
module spi_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] addr = 0, wdata = 0;
    reg [3:0] sel = 0;
    reg we = 0, valid = 0, rsp_ready = 0, miso = 0;
    wire ready, rsp_valid, mosi, sck;
    wire [31:0] rdata;
    spi dut(.clk(clk), .rst_n(rst_n), .data_i(wdata), .addr_i(addr),
        .sel_i(sel), .we_i(we), .data_o(rdata), .req_valid_i(valid),
        .req_ready_o(ready), .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready),
        .spi_mosi(mosi), .spi_miso(miso), .spi_clk(sck));

    // Independent target model: only observe SCK/MOSI and drive MISO. Do not
    // use DUT internal counters, buffers or completion signals as an oracle.
    reg monitor_on = 0;
    bit target_cpol, target_cpha;
    integer half_clocks, edge_number = 0, frames = 0, wanted = 0;
    time previous_edge;
    reg [7:0] decoded = 0;
    reg [7:0] expected_tx [0:7], target_rx [0:7];
    always @(sck) if (rst_n && monitor_on) begin
        if (frames >= wanted) $fatal(1, "Unexpected extra SPI clocks");
        if (sck !== (target_cpol ^ !(edge_number % 2)))
            $fatal(1, "SCK polarity/order mode=%0d/%0d edge=%0d", target_cpol, target_cpha, edge_number);
        if (edge_number != 0 && $time - previous_edge != half_clocks * 10)
            $fatal(1, "Incorrect divider: half period=%0t expected=%0d ns", $time-previous_edge, half_clocks*10);
        previous_edge = $time;
        #1; // sample after output propagation, before the next system clock
        if (edge_number % 2 == target_cpha) decoded = {decoded[6:0], mosi};
        else if (target_cpha) miso = target_rx[frames][7-edge_number/2];
        else if (edge_number < 15) miso = target_rx[frames][6-edge_number/2];
        if (edge_number == 15) begin
            if (decoded !== expected_tx[frames])
                $fatal(1, "MOSI frame %0d got %h expected %h", frames, decoded, expected_tx[frames]);
            frames = frames + 1;
            edge_number = 0;
            decoded = 0;
            if (!target_cpha && frames < wanted) miso = target_rx[frames][7];
        end else edge_number = edge_number + 1;
    end

    integer waited;
    task access(input bit write_en, input [31:0] offset, input [31:0] value,
                input [3:0] lanes, input integer hold_cycles, output [31:0] result);
        @(negedge clk);
        addr = offset; wdata = value; sel = lanes; we = write_en; valid = 1; rsp_ready = 0;
        waited = 0;
        do begin
            @(posedge clk);
            waited = waited + 1;
            if (waited > 10000) $fatal(1, "MMIO request timeout");
        end while (!ready);
        #1;
        if (!rsp_valid) $fatal(1, "Missing registered response");
        result = rdata;
        @(negedge clk);
        valid = 0; addr = 0; wdata = 0; sel = 0; we = 0;
        repeat (hold_cycles) begin
            @(posedge clk); #1;
            if (!rsp_valid || rdata !== result) $fatal(1, "Response changed while stalled");
        end
        @(negedge clk); rsp_ready = 1;
        @(posedge clk); #1;
        if (rsp_valid) $fatal(1, "Duplicate response");
        @(negedge clk); rsp_ready = 0;
    endtask
    task reset_dut;
        @(negedge clk); monitor_on = 0; rst_n = 0; valid = 0; rsp_ready = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        frames = 0; edge_number = 0; decoded = 0;
    endtask
    task watch(input integer mode, input integer baud, input integer count);
        target_cpol = (mode >> 1) & 1; target_cpha = mode & 1;
        half_clocks = 1 << baud; wanted = count;
        frames = 0; edge_number = 0; decoded = 0;
        miso = target_cpha ? 0 : target_rx[0][7];
        monitor_on = 1;
    endtask
    task wait_frames(input integer count);
        integer cycles;
        cycles = 0;
        while (frames < count) begin
            @(negedge clk); cycles = cycles + 1;
            if (cycles > 20000) $fatal(1, "SPI frame timeout");
        end
    endtask
    reg [31:0] result, cfg;
    integer mode, baud, cases = 0;
    integer test_pass = 0;
    initial begin
        for (mode = 0; mode < 4; mode = mode + 1) begin
            for (baud = 0; baud < 8; baud = baud + 1) begin
                reset_dut();
                access(0, 0, 0, 15, 0, result);
                if (result !== 4) $fatal(1, "CR1 reset/MSTR");
                cfg = 32'h44 | (baud << 3) | ((mode >> 1) << 1) | (mode & 1);
                access(1, 0, cfg, 1, 0, result);
                expected_tx[0] = baud == 0 ? 8'h00 : baud == 1 ? 8'hff :
                    8'ha5 ^ (mode * 17 + baud) ^ ((baud & 1) ? 8'h80 : 8'h00);
                target_rx[0] = baud == 0 ? 8'hff : baud == 1 ? 8'h00 :
                    8'h3c ^ (mode * 23 + baud) ^ ((baud & 1) ? 8'h80 : 8'h00);
                watch(mode, baud, 1);
                // Configuration must not start a transfer; upper DR bytes do nothing.
                access(1, 13, 32'hffff0000, 2, 0, result);
                access(0, 8, 0, 15, 0, result);
                if (result !== 2 || frames != 0 || edge_number != 0) $fatal(1, "Spurious start");
                access(1, 12, expected_tx[0], 1, 0, result);
                wait_frames(1);
                access(0, 8, 0, 15, 0, result);
                if (result !== 3) $fatal(1, "RXNE/TXE/BSY after frame %h", result);
                access(0, 13, 0, 2, 0, result); // no low-byte lane, must not consume RX
                access(0, 8, 0, 15, 0, result);
                if (result !== 3) $fatal(1, "Upper-byte DR read consumed RX");
                access(0, 12, 0, 1, 3, result);
                if (result !== {24'b0, target_rx[0]}) $fatal(1, "MISO mode=%0d baud=%0d got=%h", mode, baud, result);
                access(0, 8, 0, 15, 0, result);
                if (result !== 2) $fatal(1, "RXNE did not clear");
                access(0, 0, 0, 15, 0, result);
                if (result !== cfg) $fatal(1, "CR1 did not persist");
                access(1, 4, 32'hffffffff, 15, 0, result);
                access(0, 4, 0, 15, 0, result);
                if (result !== 0) $fatal(1, "CR2 reserved bits");
                cases = cases + 1;
            end
        end

        // One byte in the shifter plus one pending byte; third write must wait.
        for (mode = 0; mode < 4; mode = mode + 1) begin
        reset_dut();
        cfg = 32'h64 | ((mode >> 1) << 1) | (mode & 1); // /32
        access(1, 0, cfg, 1, 0, result);
        expected_tx[0] = 8'ha5; expected_tx[1] = 8'h3c; expected_tx[2] = 8'h96;
        target_rx[0] = 8'h12; target_rx[1] = 8'h34; target_rx[2] = 8'h56;
        watch(mode, 4, 3);
        access(1, 12, expected_tx[0], 1, 0, result);
        access(0, 8, 0, 15, 0, result);
        if ((result & 32'h82) !== 32'h82) $fatal(1, "TXE should precede BSY clear");
        access(1, 12, expected_tx[1], 1, 0, result);
        access(0, 8, 0, 15, 0, result);
        if ((result & 32'h82) !== 32'h80) $fatal(1, "TX buffer not full");
        access(1, 12, expected_tx[2], 1, 0, result);
        if (waited <= 1 || frames != 1) $fatal(1, "Full TX buffer did not stall");
        access(0, 12, 0, 1, 0, result);
        if (result !== 8'h12) $fatal(1, "RX frame 0");
        wait_frames(2);
        access(0, 12, 0, 1, 0, result);
        if (result !== 8'h34) $fatal(1, "RX frame 1");
        wait_frames(3);
        access(0, 12, 0, 1, 0, result);
        if (result !== 8'h56) $fatal(1, "RX frame 2");
        access(0, 8, 0, 15, 0, result);
        if (result !== 2) $fatal(1, "Final queue did not drain");
        end

        // Hold a status response across two completions; preserve unread RX on OVR.
        reset_dut();
        access(1, 0, 32'h64, 1, 0, result);
        watch(0, 4, 2);
        access(1, 12, expected_tx[0], 1, 0, result);
        access(1, 12, expected_tx[1], 1, 0, result);
        access(0, 8, 0, 15, 600, result);
        if (frames != 2) $fatal(1, "Response stall stopped SPI");
        access(1, 8, 0, 15, 0, result); // SR write cannot clear hardware flags
        access(0, 8, 0, 15, 0, result);
        if (result !== 32'h43) $fatal(1, "Expected overrun with oldest RX retained");
        access(0, 12, 0, 1, 0, result);
        if (result !== 8'h12) $fatal(1, "Overrun overwrote unread RX");
        access(0, 8, 0, 15, 0, result);
        if (result !== 32'h42) $fatal(1, "SR must return pre-clear OVR");
        access(0, 8, 0, 15, 0, result);
        if (result !== 2) $fatal(1, "DR/SR sequence did not clear OVR");

        // Consume old RX on the exact clock that the next byte completes.
        reset_dut();
        access(1, 0, 32'h64, 1, 0, result);
        watch(0, 4, 2);
        access(1, 12, expected_tx[0], 1, 0, result);
        access(1, 12, expected_tx[1], 1, 0, result);
        wait_frames(1);
        wait (frames == 1 && edge_number == 15);
        repeat (half_clocks) @(negedge clk);
        addr = 12; sel = 1; we = 0; valid = 1; rsp_ready = 0;
        @(posedge clk); #2;
        if (!rsp_valid || rdata !== 8'h12 || frames != 2)
            $fatal(1, "Simultaneous DR read / RX completion");
        @(negedge clk); valid = 0; rsp_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); rsp_ready = 0;
        access(0, 8, 0, 15, 0, result);
        if (result !== 3) $fatal(1, "Simultaneous RX pop/push lost RX or caused OVR");
        access(0, 12, 0, 1, 0, result);
        if (result !== 8'h34) $fatal(1, "Simultaneous RX push value");

        // Keep a DR request asserted after acceptance while response is stalled:
        // no repeated write or repeated transfer is allowed.
        reset_dut();
        access(1, 0, 32'h64, 1, 0, result);
        watch(0, 4, 1);
        @(negedge clk); addr = 12; sel = 1; wdata = expected_tx[0]; we = 1; valid = 1;
        @(posedge clk); #1;
        if (!rsp_valid) $fatal(1, "DR write response");
        repeat (300) begin
            @(posedge clk); #1;
            if (ready || !rsp_valid || rdata !== 0) $fatal(1, "Repeated request accepted under response stall");
        end
        @(negedge clk); valid = 0; we = 0; rsp_ready = 1;
        @(posedge clk); #1;
        if (rsp_valid || frames != 1) $fatal(1, "Stalled DR response caused duplicate TX");
        @(negedge clk); rsp_ready = 0;

        // Configuration is serialized after a complete frame, not mid-bit.
        reset_dut();
        access(1, 0, 32'h64, 1, 0, result);
        watch(0, 4, 1);
        access(1, 12, expected_tx[0], 1, 0, result);
        access(1, 0, 32'h45, 1, 0, result); // same CPOL, change CPHA and BR
        if (waited <= 1 || frames != 1) $fatal(1, "CR1 changed during transfer");
        access(0, 0, 0, 15, 0, result);
        if (result !== 32'h45) $fatal(1, "CR1 update after idle");

        // DR can be preloaded while disabled; reset aborts active and pending TX.
        reset_dut();
        target_rx[0] = 8'h12;
        access(1, 12, expected_tx[0], 1, 0, result);
        access(0, 8, 0, 15, 0, result);
        if (result !== 0 || sck !== 0) $fatal(1, "Disabled SPI should retain pending TX without clocks");
        watch(0, 4, 1);
        access(1, 0, 32'h64, 1, 0, result);
        wait_frames(1);
        reset_dut();
        access(1, 0, 32'h64, 1, 0, result);
        watch(0, 4, 2);
        access(1, 12, expected_tx[0], 1, 0, result);
        access(1, 12, expected_tx[1], 1, 0, result);
        repeat (20) @(negedge clk);
        reset_dut();
        access(0, 8, 0, 15, 0, result);
        if (result !== 2 || sck !== 0 || mosi !== 0) $fatal(1, "Reset did not abort TX queue");
        access(0, 0, 0, 15, 0, result);
        if (result !== 4) $fatal(1, "Reset did not disable SPI");
        $display("PASS SPI: %0d mode/divider cases, TX queue/backpressure, RX/OVR, response stalls, config and reset", cases);
        test_pass = 1;
        $finish;
    end
    initial begin #10000000; $fatal(1, "SPI test timeout"); end
endmodule
