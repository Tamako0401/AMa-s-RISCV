module ov7670_sccb_init #(
    parameter DIVIDER = 250,
    parameter RESET_DELAY = 500000
) (
    input wire clk,
    input wire rst_n,
    input wire sda_in,
    output reg scl_low,
    output reg sda_low,
    output reg done,
    output reg error
);
    localparam WAIT_START = 4'd0;
    localparam START_HIGH = 4'd1;
    localparam START_LOW = 4'd2;
    localparam SEND_LOW = 4'd3;
    localparam SEND_HIGH = 4'd4;
    localparam ACK_LOW = 4'd5;
    localparam ACK_HIGH = 4'd6;
    localparam STOP_LOW = 4'd7;
    localparam STOP_HIGH = 4'd8;
    localparam STOP_RELEASE = 4'd9;
    localparam POST_RESET = 4'd10;
    localparam COMPLETE = 4'd11;
    localparam FAILED = 4'd12;

    reg [3:0] state;
    reg [15:0] divider_count;
    reg [19:0] delay_count;
    reg [1:0] byte_index;
    reg [2:0] register_index;
    reg [2:0] bit_index;
    reg [7:0] tx_byte;
    wire phase_tick = divider_count == DIVIDER-1;

    function [7:0] register_address(input [2:0] index);
        begin
            case (index)
                0: register_address = 8'h12;
                1: register_address = 8'h12;
                2: register_address = 8'h40;
                default: register_address = 8'h3A;
            endcase
        end
    endfunction

    function [7:0] register_value(input [2:0] index);
        begin
            case (index)
                0: register_value = 8'h80;
                1: register_value = 8'h04;
                2: register_value = 8'hD0;
                default: register_value = 8'h04;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) divider_count <= 0;
        else if (phase_tick) divider_count <= 0;
        else divider_count <= divider_count + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_START;
            delay_count <= 0;
            byte_index <= 0;
            register_index <= 0;
            bit_index <= 7;
            tx_byte <= 8'h42;
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
        end else if (state == WAIT_START) begin
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            if (delay_count == RESET_DELAY-1) begin
                delay_count <= 0;
                state <= START_HIGH;
            end else begin
                delay_count <= delay_count + 1'b1;
            end
        end else if (state == POST_RESET) begin
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            if (delay_count == RESET_DELAY-1) begin
                delay_count <= 0;
                register_index <= 1;
                byte_index <= 0;
                bit_index <= 7;
                tx_byte <= 8'h42;
                state <= START_HIGH;
            end else begin
                delay_count <= delay_count + 1'b1;
            end
        end else if (phase_tick) begin
            case (state)
                START_HIGH: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b1;
                    state <= START_LOW;
                end
                START_LOW: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b1;
                    state <= SEND_LOW;
                end
                SEND_LOW: begin
                    scl_low <= 1'b1;
                    sda_low <= !tx_byte[bit_index];
                    state <= SEND_HIGH;
                end
                SEND_HIGH: begin
                    scl_low <= 1'b0;
                    if (bit_index == 0) state <= ACK_LOW;
                    else begin
                        bit_index <= bit_index - 1'b1;
                        state <= SEND_LOW;
                    end
                end
                ACK_LOW: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;
                    state <= ACK_HIGH;
                end
                ACK_HIGH: begin
                    scl_low <= 1'b0;
                    if (sda_in) begin
                        error <= 1'b1;
                        state <= FAILED;
                    end else if (byte_index == 0) begin
                        byte_index <= 1;
                        bit_index <= 7;
                        tx_byte <= register_address(register_index);
                        state <= SEND_LOW;
                    end else if (byte_index == 1) begin
                        byte_index <= 2;
                        bit_index <= 7;
                        tx_byte <= register_value(register_index);
                        state <= SEND_LOW;
                    end else begin
                        state <= STOP_LOW;
                    end
                end
                STOP_LOW: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b1;
                    state <= STOP_HIGH;
                end
                STOP_HIGH: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b1;
                    state <= STOP_RELEASE;
                end
                STOP_RELEASE: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    if (register_index == 3) begin
                        done <= 1'b1;
                        state <= COMPLETE;
                    end else if (register_index == 0) begin
                        delay_count <= 0;
                        state <= POST_RESET;
                    end else begin
                        register_index <= register_index + 1'b1;
                        byte_index <= 0;
                        bit_index <= 7;
                        tx_byte <= 8'h42;
                        state <= START_HIGH;
                    end
                end
                default: ;
            endcase
        end
    end
endmodule
