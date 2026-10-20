// GPIO 矩阵 (仿 ESP32): 任何外设信号可以接到任何引脚, 寄存器和行为见 docs/gpio-matrix.md。
// 引脚 0~IO_N-1 由板级顶层按引脚表接到管脚; 复位后只有控制台串口接在 UART_TX_PIN / UART_RX_PIN 上。
module gpio_matrix #(
    parameter IO_N = 0,
    parameter UART_TX_PIN = 255,
    parameter UART_RX_PIN = 255
) (
    input wire clk,
    input wire rst_n,
    input wire [31:0] addr_i,
    input wire [31:0] data_i,
    input wire [3:0] sel_i,
    input wire we_i,
    output wire [31:0] data_o,
    input wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input wire rsp_ready_i,

    output reg [127:0] io_o,
    output reg [127:0] io_oe,
    input wire [127:0] io_i,
    input wire uart_tx_i,
    output wire uart_rx_o,
    input wire spi_sck_i,
    input wire spi_mosi_i,
    output wire spi_miso_o
);

    reg [127:0] gpio_out, gpio_enable;
    reg [127:0] io_q0, io_q1;  // 引脚是异步输入, 打两拍
    reg [7:0] func_out_sel[0:127];
    reg [7:0] func_in_sel[0:1];  // 0 = UART_RX, 1 = SPI_MISO; 0xFF = 不接
    reg response_valid;
    reg [31:0] data_r;
    wire wen = we_i & req_valid_i & req_ready_o;
    wire ren = (~we_i) & req_valid_i & req_ready_o;

    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i);
    assign rsp_valid_o = response_valid;
    assign data_o = data_r;
    assign uart_rx_o = func_in_sel[0] < IO_N ? io_q1[func_in_sel[0][6:0]] : 1'b1;
    assign spi_miso_o = func_in_sel[1] < IO_N ? io_q1[func_in_sel[1][6:0]] : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            io_q0 <= 0;
            io_q1 <= 0;
        end else begin
            io_q0 <= io_i;
            io_q1 <= io_q0;
        end
    end

    // 地址直接拆成字段选寄存器, 不按引脚逐个比较地址 (128 路比较在 50 MHz 下时序不过)
    wire [1:0] word = addr_i[3:2];  // 0x000~0x06F: 第几组 32 个引脚
    wire [3:0] group = addr_i[7:4];  // 0=OUT 1=W1TS 2=W1TC 3=ENABLE 4=W1TS 5=W1TC 6=IN
    wire [6:0] pin = addr_i[8:2];  // 0x200~0x3FC: FUNC_OUT_SEL[pin]
    wire       is_word = addr_i[11:8] == 4'h0;
    wire       is_out_sel = addr_i[11:9] == 3'b001;
    wire       is_in_sel = addr_i[11:3] == 9'h080;
    localparam [127:0] VALID = ~(~128'h0 << IO_N);  // 只有 0~IO_N-1 存在
    wire [31:0] valid_w = VALID[{word, 5'b0}+:32];
    wire [31:0] out_w = gpio_out[{word, 5'b0}+:32];
    wire [31:0] enable_w = gpio_enable[{word, 5'b0}+:32];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_out <= 0;
            gpio_enable <= 0;
            func_in_sel[0] <= UART_RX_PIN[7:0];
            func_in_sel[1] <= 8'hff;
        end else if (wen) begin
            if (is_word)
                case (group)
                    0: gpio_out[{word, 5'b0}+:32] <= data_i & valid_w;
                    1: gpio_out[{word, 5'b0}+:32] <= (out_w | data_i) & valid_w;
                    2: gpio_out[{word, 5'b0}+:32] <= out_w & ~data_i;
                    3: gpio_enable[{word, 5'b0}+:32] <= data_i & valid_w;
                    4: gpio_enable[{word, 5'b0}+:32] <= (enable_w | data_i) & valid_w;
                    5: gpio_enable[{word, 5'b0}+:32] <= enable_w & ~data_i;
                    default: begin
                    end
                endcase
            if (is_in_sel) func_in_sel[addr_i[2]] <= data_i[7:0];
        end
    end

    // 每个引脚一段: 循环里对数组做非阻塞赋值, 旧版 verilator (5.020) 不支持
    // genvar 单独声明: for 里直接声明是 SystemVerilog 写法, PDS 按 Verilog 解析会报错
    genvar g;
    generate
        for (g = 0; g < 128; g = g + 1) begin : g_out_sel
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) func_out_sel[g] <= (g < IO_N && g == UART_TX_PIN) ? 8'd1 : 8'd0;
                else if (wen && is_out_sel && pin == g && g < IO_N) func_out_sel[g] <= data_i[7:0];
            end
        end
    endgenerate

    integer p;
    always @(*) begin
        io_o  = 0;
        io_oe = 0;
        for (p = 0; p < IO_N; p = p + 1) begin
            case (func_out_sel[p])
                0: begin
                    io_o[p]  = gpio_out[p];
                    io_oe[p] = gpio_enable[p];
                end
                1: begin
                    io_o[p]  = uart_tx_i;
                    io_oe[p] = 1;
                end
                2: begin
                    io_o[p]  = spi_sck_i;
                    io_oe[p] = 1;
                end
                3: begin
                    io_o[p]  = spi_mosi_i;
                    io_oe[p] = 1;
                end
                default: begin
                    io_o[p]  = 0;
                    io_oe[p] = 0;
                end
            endcase
        end
        // MMCM 停钟时复位寄存器尚未采样, 控制台仍必须保持空闲电平。
        if (!rst_n) begin
            io_o  = 0;
            io_oe = 0;
            if (UART_TX_PIN < IO_N) begin
                io_o[UART_TX_PIN]  = 1;
                io_oe[UART_TX_PIN] = 1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_r <= 0;
            response_valid <= 0;
        end else begin
            if (response_valid && rsp_ready_i) response_valid <= 0;
            if (req_valid_i && req_ready_o) begin
                response_valid <= 1;
                data_r <= 0;
            end
            if (ren) begin
                if (is_word)
                    case (group)
                        0: data_r <= out_w;
                        3: data_r <= enable_w;
                        6: data_r <= io_q1[{word, 5'b0}+:32] & valid_w;
                        default: begin
                        end
                    endcase
                if (is_out_sel && pin < IO_N) data_r <= {24'h0, func_out_sel[pin]};
                if (is_in_sel) data_r <= {24'h0, func_in_sel[addr_i[2]]};
            end
        end
    end

endmodule
