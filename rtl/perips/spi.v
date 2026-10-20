/*
 Copyright 2020 Blue Liang, liangkangnan@163.com

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

// AMa-s-RISCV, 2026-09-30: replace the inherited transfer engine/registers.
// STM32F1/F4-style subset: master, 8-bit, MSB first, all four SPI modes.
// CR1 0x00: CPHA[0], CPOL[1], MSTR[2]=1, BR[5:3], SPE[6].
// CR2 0x04: reserved, reads zero. SR 0x08: RXNE[0], TXE[1], OVR[6], BSY[7].
// DR  0x0c: low-byte writes enqueue TX; low-byte reads consume RX.
// BR selects clk / (2 ** (BR+1)); CR1 writes wait until the enabled TX queue
// has drained. Chip select, display DC and display reset belong to GPIO.
module spi (
    input wire clk,
    input wire rst_n,
    input wire [31:0] data_i,
    input wire [31:0] addr_i,
    input wire [3:0] sel_i,
    input wire we_i,
    output wire [31:0] data_o,
    input wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input wire rsp_ready_i,
    output reg spi_mosi,
    input wire spi_miso,
    output reg spi_clk
);
    localparam CR1 = 2'd0, CR2 = 2'd1, SR = 2'd2, DR = 2'd3;
    reg [6:0] cr1;
    reg [7:0] tx_buffer, tx_shift, rx_shift, rx_buffer;
    reg tx_full, rx_full, busy, overrun, overrun_dr_read;
    reg cpha;
    reg [7:0] half_period, ticks_left;
    reg [3:0] edge_index;
    reg response_valid;
    reg [31:0] response_data;

    wire write_dr = we_i && addr_i[3:2] == DR && sel_i[0];
    wire write_cr1 = we_i && addr_i[3:2] == CR1 && sel_i[0];
    wire start_byte = !busy && tx_full && cr1[6];
    wire active = busy || (tx_full && cr1[6]);
    wire tick = busy && ticks_left == 0;
    wire finish_byte = tick && edge_index == 4'd15;
    wire [7:0] completed_rx = cpha ? {rx_shift[6:0], spi_miso} : rx_shift;
    wire [31:0] status = {24'b0, active, overrun, 4'b0, !tx_full, rx_full};

    // Full TX buffer stalls the request; responses retain their payload.
    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i) &&
                         (!write_dr || !tx_full || start_byte) &&
                         (!write_cr1 || !active);
    assign rsp_valid_o = response_valid;
    assign data_o = response_data;
    wire fire = req_valid_i && req_ready_o;
    wire push_tx = fire && write_dr;
    wire pop_rx = fire && !we_i && addr_i[3:2] == DR && sel_i[0];
    wire read_sr = fire && !we_i && addr_i[3:2] == SR;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cr1 <= 7'h04;  // MSTR fixed high; SPE is a persistent enable.
            response_valid <= 0;
            response_data <= 0;
        end else begin
            if (response_valid && rsp_ready_i) response_valid <= 0;
            if (fire) begin
                response_valid <= 1;
                response_data  <= 0;
                if (!we_i) begin
                    case (addr_i[3:2])
                        CR1: response_data <= {25'b0, cr1};
                        CR2: response_data <= 0;
                        SR:  response_data <= status;
                        DR:  response_data <= {24'b0, rx_buffer};
                        default: begin
                        end
                    endcase
                end
                if (write_cr1) cr1 <= data_i[6:0] | 7'h04;
            end
        end
    end

    // Separate buffer and shifter: accepting the next byte cannot corrupt TX.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_full   <= 0;
            tx_buffer <= 0;
        end else begin
            if (start_byte) tx_full <= 0;
            if (push_tx) begin
                tx_buffer <= data_i[7:0];
                tx_full   <= 1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk <= 0;
            spi_mosi <= 0;
            busy <= 0;
            cpha <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
            edge_index <= 0;
            half_period <= 1;
            ticks_left <= 0;
        end else begin
            if (!busy) spi_clk <= cr1[1];
            if (start_byte) begin
                busy <= 1;
                cpha <= cr1[0];
                spi_clk <= cr1[1];
                half_period <= 8'd1 << cr1[5:3];
                ticks_left <= (8'd1 << cr1[5:3]) - 1'b1;
                edge_index <= 0;
                rx_shift <= 0;
                if (!cr1[0]) begin
                    spi_mosi <= tx_buffer[7];  // CPHA=0 preload before first edge.
                    tx_shift <= {tx_buffer[6:0], 1'b0};
                end else tx_shift <= tx_buffer;
            end else if (busy) begin
                if (tick) begin
                    spi_clk <= ~spi_clk;
                    ticks_left <= half_period - 1'b1;
                    edge_index <= edge_index + 1'b1;
                    // Even indices are leading edges; odd indices are trailing.
                    if (edge_index[0] == cpha) rx_shift <= {rx_shift[6:0], spi_miso};
                    else begin
                        spi_mosi <= tx_shift[7];
                        tx_shift <= {tx_shift[6:0], 1'b0};
                    end
                    // Complete on the eighth trailing edge, including CPHA=0.
                    if (finish_byte) busy <= 0;
                end else ticks_left <= ticks_left - 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_full <= 0;
            rx_buffer <= 0;
            overrun <= 0;
            overrun_dr_read <= 0;
        end else begin
            if (pop_rx) begin
                rx_full <= 0;
                overrun_dr_read <= overrun;
            end
            // OVR clears on DR read followed by SR read. SR returns pre-clear
            // status; a new overrun on this clock wins over clearing.
            if (read_sr && overrun_dr_read) begin
                overrun <= 0;
                overrun_dr_read <= 0;
            end
            if (finish_byte) begin
                if (!rx_full || pop_rx) begin
                    rx_buffer <= completed_rx;
                    rx_full   <= 1;
                end else begin
                    overrun <= 1;
                    overrun_dr_read <= 0;
                end
            end
        end
    end
endmodule
