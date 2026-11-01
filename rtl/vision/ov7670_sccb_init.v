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
    reg [4:0] register_index;
    reg [2:0] bit_index;
    reg [7:0] tx_byte;
    wire phase_tick = divider_count == DIVIDER-1;

    // 写入的寄存器表: 复位 -> RGB565 全范围 -> 打开自动曝光/自动增益/自动白平衡 -> 中性白平衡增益 -> 标准 gamma 曲线。
    // 只写影响亮度/颜色的寄存器, 不动已经在用的窗口和时序寄存器。
    localparam REG_COUNT = 5'd30;

    function [7:0] register_address(input [4:0] index);
        begin
            case (index)
                5'd0: register_address = 8'h12;  // COM7: 软复位
                5'd1: register_address = 8'h12;  // COM7: RGB 输出
                5'd2: register_address = 8'h40;  // COM15: RGB565, 全输出范围
                5'd3: register_address = 8'h3A;  // TSLB
                5'd4: register_address = 8'h13;  // COM8
                5'd5: register_address = 8'h6C;  // AWB 蓝增益
                5'd6: register_address = 8'h6D;  // AWB 红增益
                5'd7: register_address = 8'h6E;  // AWB 绿增益
                5'd8: register_address = 8'h6F;  // AWB 绿增益
                5'd26: register_address = 8'h0F;  // COM9: 自动增益上限
                5'd27: register_address = 8'h24;  // AEW: 自动曝光目标上限
                5'd28: register_address = 8'h25;  // AEB: 自动曝光目标下限
                5'd29: register_address = 8'h55;  // BRIGHT
                default: register_address = 8'h72 + {3'b0, index};  // index 9..25 -> 0x7B..0x8B gamma 曲线
            endcase
        end
    endfunction

    function [7:0] register_value(input [4:0] index);
        begin
            case (index)
                5'd0: register_value = 8'h80;
                5'd1: register_value = 8'h04;
                5'd2: register_value = 8'hD0;
                5'd3: register_value = 8'h04;
                5'd4: register_value = 8'hE7;  // 自动曝光 + 自动增益 + 自动白平衡, 快速跟踪
                5'd5: register_value = 8'h40;
                5'd6: register_value = 8'h40;
                5'd7: register_value = 8'h40;
                5'd8: register_value = 8'h40;
                5'd9: register_value = 8'h04;   // 0x7B
                5'd10: register_value = 8'h0F;  // 0x7C
                5'd11: register_value = 8'h14;  // 0x7D
                5'd12: register_value = 8'h19;  // 0x7E
                5'd13: register_value = 8'h24;  // 0x7F
                5'd14: register_value = 8'h2F;  // 0x80
                5'd15: register_value = 8'h40;  // 0x81
                5'd16: register_value = 8'h55;  // 0x82
                5'd17: register_value = 8'h6B;  // 0x83
                5'd18: register_value = 8'h81;  // 0x84
                5'd19: register_value = 8'h95;  // 0x85
                5'd20: register_value = 8'hA7;  // 0x86
                5'd21: register_value = 8'hB4;  // 0x87
                5'd22: register_value = 8'hBE;  // 0x88
                5'd23: register_value = 8'hC5;  // 0x89
                5'd24: register_value = 8'hCB;  // 0x8A
                5'd25: register_value = 8'hD0;  // 0x8B
                5'd26: register_value = 8'h60;  // COM9: 自动增益上限放宽到 16x
                5'd27: register_value = 8'h75;  // AEW
                5'd28: register_value = 8'h63;  // AEB
                default: register_value = 8'h10; // BRIGHT: +16
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
                    if (register_index == REG_COUNT - 1) begin
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
