`timescale 1ns/1ps
// Board-independent CPU harness. Memory is a simulation model, not FPGA IP.
module cpu_tb;
    parameter I_DELAY = 0;
    parameter D_DELAY = 0;
    parameter SEED = 1;
    parameter [31:0] BASE = 32'h80000000;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    wire [31:0] ia, iw, da, dw;
    wire [3:0] isel, dsel;
    wire iwe, dwe, iv, ir, iq, dv, dr, dq;
    reg [31:0] idata, ddata;
    reg ivalid = 0, dvalid = 0;
    tinyriscv_core #(.RESET_PC(BASE)) dut (
        .clk(clk), .rst_n(rst_n), .jtag_halt_i(1'b0), .int_i(8'b0),
        .ibus_addr_o(ia), .ibus_data_o(iw), .ibus_data_i(idata),
        .ibus_sel_o(isel), .ibus_we_o(iwe),
        .ibus_req_valid_o(iv), .ibus_req_ready_i(ir),
        .ibus_rsp_valid_i(ivalid), .ibus_rsp_ready_o(iq),
        .dbus_addr_o(da), .dbus_data_o(dw), .dbus_data_i(ddata),
        .dbus_sel_o(dsel), .dbus_we_o(dwe),
        .dbus_req_valid_o(dv), .dbus_req_ready_i(dr),
        .dbus_rsp_valid_i(dvalid), .dbus_rsp_ready_o(dq)
    );
    reg [31:0] mem [0:16383];
    reg [31:0] rng = SEED;
    reg ibusy = 0, dbusy = 0;
    integer icount, dcount, cycles = 0, stores = 0;
    integer expected_stores = -1;
    reg [31:0] ipayload, dpayload;
    reg completing = 0;
    reg [31:0] status;
    string image_path, wave_path;
    integer unused;
    assign ir = rst_n && !ibusy && !ivalid && (I_DELAY == 0 || rng[0]);
    assign dr = rst_n && !dbusy && !dvalid && (D_DELAY == 0 || rng[4]);

    initial begin
        if (!$value$plusargs("image=%s", image_path)) $fatal(1, "Missing +image=hex");
        unused = $value$plusargs("stores=%d", expected_stores);
        $readmemh(image_path, mem);
        if ($value$plusargs("vcd=%s", wave_path)) begin
            $dumpfile(wave_path);
            $dumpvars(0, cpu_tb);
        end
        repeat (5) @(negedge clk);
        rst_n = 1;
    end

    // Check request stability independently of the memory response generator.
    reg i_wait = 0, d_wait = 0;
    reg [31:0] held_ia;
    reg [68:0] held_d;
    always @(posedge clk) if (rst_n) begin
        if (i_wait && (!iv || ia !== held_ia)) $fatal(1, "Unstable stalled fetch");
        if (d_wait && (!dv || {da,dw,dsel,dwe} !== held_d))
            $fatal(1, "Unstable stalled data request");
        i_wait <= iv && !ir;
        d_wait <= dv && !dr;
        held_ia <= ia;
        held_d <= {da,dw,dsel,dwe};
    end

    always @(posedge clk) if (rst_n) begin
        cycles <= cycles + 1;
        rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
        if (cycles > 1000000) $fatal(1, "Timeout pc=%h", ia);
        if (iv && ir) begin
            if (ia < BASE || ia >= BASE + 65536 || ia[1:0] != 0 || iwe)
                $fatal(1, "Invalid fetch %h", ia);
            ibusy <= 1;
            icount <= I_DELAY == 0 ? 0 : rng[9:6] % (I_DELAY + 1);
            ipayload <= mem[(ia - BASE) >> 2];
        end
        if (ibusy) begin
            if (icount == 0) begin
                ibusy <= 0;
                ivalid <= 1;
                idata <= ipayload;
            end else icount <= icount - 1;
        end
        if (ivalid && iq) begin
            ivalid <= 0;
            idata <= 32'hxxxxxxxx; // catch consumers using a stale response
        end
        if (dv && dr) begin
            dbusy <= 1;
            dcount <= D_DELAY == 0 ? 0 : rng[15:12] % (D_DELAY + 1);
            if (da == 32'h10000000 && dwe && dsel == 4'b1111) begin
                completing <= 1;
                status <= dw;
                dpayload <= 0;
            end else begin
                if (da < BASE || da >= BASE + 65536)
                    $fatal(1, "Invalid data access %h", da);
                dpayload <= mem[(da - BASE) >> 2];
                if (dwe) begin
                    stores <= stores + 1;
                    for (integer lane=0; lane<4; lane=lane+1)
                        if (dsel[lane]) mem[(da - BASE) >> 2][8*lane +: 8] <= dw[8*lane +: 8];
                end
            end
        end
        if (dbusy) begin
            if (dcount == 0) begin
                dbusy <= 0;
                dvalid <= 1;
                ddata <= dpayload;
            end else dcount <= dcount - 1;
        end
        if (dvalid && dq) begin
            dvalid <= 0;
            ddata <= 32'hxxxxxxxx;
            if (completing) begin
                if (status !== 1) $fatal(1, "Program FAIL code=%h pc=%h", status, ia);
                if (expected_stores >= 0 && stores != expected_stores)
                    $fatal(1, "Store count %0d expected %0d", stores, expected_stores);
                $display("PASS CPU %s I=%0d D=%0d seed=%0d cycles=%0d stores=%0d",
                         image_path, I_DELAY, D_DELAY, SEED, cycles, stores);
                $finish;
            end
        end
    end
endmodule
