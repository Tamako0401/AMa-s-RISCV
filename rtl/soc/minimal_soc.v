// AMa-s-RISCV board bring-up: single shared RAM port, GPIO, UART and SPI.
// Each accepted transaction is executed once, then its response is held.
// GPIO 0/1/2 = LCD CS_N/DC/RST_N, GPIO 8~15 = LED, same as rtl/soc_top.
module minimal_soc #(
    parameter CPU_CLOCK_HZ = 50000000,
    parameter MEM_FILE = "firmware.hex"
)(
    input wire clk, input wire rst_n,
    input wire uart_rx, output wire uart_tx,
    output wire [7:0] led, output reg fault,
    output wire spi_clk, output wire spi_mosi,
    output wire lcd_cs, output wire lcd_dc, output wire lcd_rst_n
);
    wire [31:0] ia, iw, da, dw;
    wire [3:0] isel, dsel;
    wire iwe, dwe, iv, ir, iq, dv, dr, dq;
    reg [31:0] response;
    reg owner_data;
    localparam IDLE=0, READ=1, RESP=2;
    reg [1:0] state;
    reg [1:0] target;
    wire core_reset_n = rst_n && !fault;
    tinyriscv_core #(.RESET_PC(32'h80000000)) cpu (
        .clk(clk), .rst_n(core_reset_n), .jtag_halt_i(1'b0), .int_i(8'b0),
        .ibus_addr_o(ia), .ibus_data_o(iw), .ibus_data_i(response),
        .ibus_sel_o(isel), .ibus_we_o(iwe),
        .ibus_req_valid_o(iv), .ibus_req_ready_i(ir),
        .ibus_rsp_valid_i(state == RESP && !owner_data), .ibus_rsp_ready_o(iq),
        .dbus_addr_o(da), .dbus_data_o(dw), .dbus_data_i(response),
        .dbus_sel_o(dsel), .dbus_we_o(dwe),
        .dbus_req_valid_o(dv), .dbus_req_ready_i(dr),
        .dbus_rsp_valid_i(state == RESP && owner_data), .dbus_rsp_ready_o(dq)
    );
    // SPI backpressure (full TX buffer, CR1 write while active) stalls the
    // data port; UART/GPIO are always ready, RAM completes in one cycle.
    wire spi_ready;
    assign dr = core_reset_n && state == IDLE && (!spi_hit || spi_ready);
    assign ir = core_reset_n && state == IDLE && !dv;
    wire dfire = dv && dr;
    wire ifire = iv && ir;
    wire [31:0] address = dfire ? da : ia;
    wire ram_hit = address[31:16] == 16'h8000;
    wire uart_hit = da >= 32'h30000000 && da <= 32'h30000013;
    wire gpio_hit = da >= 32'h40000000 && da <= 32'h4000000b;
    wire spi_hit = da >= 32'h40002000 && da <= 32'h4000200f;
    wire ram_en = (dfire || ifire) && ram_hit;
    wire [13:0] word_address = address[15:2];
    reg [31:0] ram [0:16383];
    reg [31:0] ram_q;
    initial $readmemh(MEM_FILE, ram);
    // Synchronous read, byte writes, no reset of the array: infer block RAM.
    always @(posedge clk) begin
        if (ram_en) begin
            ram_q <= ram[word_address];
            if (dfire && dwe) begin
                if (dsel[0]) ram[word_address][7:0] <= dw[7:0];
                if (dsel[1]) ram[word_address][15:8] <= dw[15:8];
                if (dsel[2]) ram[word_address][23:16] <= dw[23:16];
                if (dsel[3]) ram[word_address][31:24] <= dw[31:24];
            end
        end
    end
    wire [31:0] uart_data, gpio_data, spi_data, gpio_ctrl, gpio_pins;
    wire uart_ready, uart_valid, gpio_ready, gpio_valid, spi_valid;
    uart #(.CPU_CLOCK_HZ(CPU_CLOCK_HZ)) serial (
        .clk(clk), .rst_n(rst_n), .addr_i(da), .data_i(dw), .sel_i(dsel), .we_i(dwe),
        .data_o(uart_data), .req_valid_i(dfire && uart_hit), .req_ready_o(uart_ready),
        .rsp_valid_o(uart_valid), .rsp_ready_i(1'b1), .tx_pin(uart_tx), .rx_pin(uart_rx)
    );
    gpio pins (
        .clk(clk), .rst_n(rst_n), .addr_i(da), .data_i(dw), .sel_i(dsel), .we_i(dwe),
        .data_o(gpio_data), .req_valid_i(dfire && gpio_hit), .req_ready_o(gpio_ready),
        .rsp_valid_o(gpio_valid), .rsp_ready_i(1'b1), .io_pin_i(2'b00),
        .reg_ctrl(gpio_ctrl), .reg_data(gpio_pins)
    );
    // Write-only display: MISO tied low. Register subset per docs/spi.md.
    spi display_spi (
        .clk(clk), .rst_n(rst_n), .addr_i(da), .data_i(dw), .sel_i(dsel), .we_i(dwe),
        .data_o(spi_data), .req_valid_i(dfire && spi_hit), .req_ready_o(spi_ready),
        .rsp_valid_o(spi_valid), .rsp_ready_i(1'b1),
        .spi_mosi(spi_mosi), .spi_miso(1'b0), .spi_clk(spi_clk)
    );
    // Unconfigured pins hold safe levels: not selected, command, reset released.
    assign lcd_cs = gpio_ctrl[1:0] == 2'b01 ? gpio_pins[0] : 1'b1;
    assign lcd_dc = gpio_ctrl[3:2] == 2'b01 ? gpio_pins[1] : 1'b0;
    assign lcd_rst_n = gpio_ctrl[5:4] == 2'b01 ? gpio_pins[2] : 1'b1;
    genvar pin;
    generate for (pin=0; pin<8; pin=pin+1) begin: leds
        assign led[pin] = fault ? (pin == 7) :
                         (gpio_ctrl[(8+pin)*2 +: 2] == 2'b01 && gpio_pins[8+pin]);
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            target <= 0;
            owner_data <= 0;
            response <= 0;
            fault <= 0;
        end else begin
            case (state)
                IDLE: if (dfire || ifire) begin
                    owner_data <= dfire;
                    target <= ram_hit ? 0 : uart_hit ? 1 : gpio_hit ? 2 : 3;
                    state <= READ;
                    if (ifire && (!ram_hit || ia[1:0] != 0)) fault <= 1;
                    if (dfire && !(ram_hit || uart_hit || gpio_hit || spi_hit)) fault <= 1;
                end
                READ: begin
                    response <= target == 0 ? ram_q : target == 1 ? uart_data :
                                target == 2 ? gpio_data : spi_data;
                    state <= RESP;
                end
                RESP: if (owner_data ? dq : iq) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
