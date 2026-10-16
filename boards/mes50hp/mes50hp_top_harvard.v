// MES50HP / PGL50H-6IFBG484, 哈佛式 SoC (rtl/soc_top/soc_top.v) 版板级顶层。
// 与 mes50hp_top.v (minimal_soc) 端口、模块名完全相同, 共用 mes50hp.fdc 和板级
// 测试台; 构建时二选一 (scripts/build-board.py --harvard)。
//
// 存储器: ROM 0x0000_0000 (指令/常量/.data 初值, 配置时装入, CPU 只读),
//         RAM 0x1000_0000 (变量/栈, 不预装)。复位后由 sw/board/start.S 把 .data
//         初值从 ROM 拷到 RAM, 所以 KEY1 复位与上电行为一致, 像单片机一样。
// 外设: GPIO 0x4000_0000, UART 0x4000_1000, SPI 0x4000_2000。
module mes50hp_top #(
    // ROM 镜像; 测试台覆盖为仿真镜像, PDS 使用默认值
    parameter MEM_FILE = "firmware.hex"
) (
    input wire clk, input wire key1_n,
    input wire uart_rx, output wire uart_tx,
    output wire [7:0] led,
    output wire lcd_sck, output wire lcd_mosi, output wire lcd_cs,
    output wire lcd_dc, output wire lcd_rst_n, output wire lcd_bl
);
    // 配置完成即上电复位; KEY1 异步拉低, 同步释放 (与 minimal_soc 版相同)
    reg [15:0] reset_pipe = 16'b0;
    always @(posedge clk or negedge key1_n) begin
        if (!key1_n) reset_pipe <= 16'b0;
        else reset_pipe <= {reset_pipe[14:0], 1'b1};
    end
    reg [1:0] rx_sync = 2'b11;
    always @(posedge clk) rx_sync <= {rx_sync[0], uart_rx};
    // soc_top 没有总线故障输出 (未映射地址会一直等待); 保留该信号供测试台检查
    wire fault = 1'b0;
    soc_top #(.ROM_INIT_FILE(MEM_FILE)) soc (
        .clk(clk), .rst_n(reset_pipe[15]),
        .uart_rx(rx_sync[1]), .uart_tx(uart_tx), .led(led),
        .spi_mosi(lcd_mosi), .spi_miso(1'b0), .spi_ss(lcd_cs), .spi_clk(lcd_sck),
        .lcd_dc(lcd_dc), .lcd_rst_n(lcd_rst_n)
    );
    assign lcd_bl = 1'b1; // 背光常亮
endmodule
