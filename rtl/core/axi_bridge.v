// AMa-s-RISCV, 2026-10-01: RIB 与 AXI4 之间的协议桥。
//
// 用途: 把 AXI4 / AXI4-Lite 接口的控制器(例如 DDR3 控制器等厂商 IP)接到 RIB 上,
//       让 CPU 像访问普通存储器一样访问它。RIB 从设备侧的端口命名与
//       perips/spi.v、perips/gpio.v 一致, 因此可以像普通外设一样挂进任意槽位。
//
// 设计取舍:
//   1. 只发单拍事务(arlen/awlen = 0, arburst/awburst = INCR)。
//      RIB 每次只搬 4 字节且没有 burst 语义, 单拍足以覆盖; 而单拍 AXI4 的语义与
//      AXI4-Lite 一致, 所以同一份 RTL 可以接两种从设备。
//      代价: 用不上 DDR3 的 burst 带宽。但 SPI 只有 3 MB/s, 这不是当前瓶颈。
//   2. 字节使能不用 AXI 的窄传输, 而用「整宽传输 + WSTRB」:
//        写: awaddr 向下对齐到 AXI 数据宽度, WSTRB 为移位后的 sel_i
//        读: araddr 向下对齐, 读回整拍后按地址低位挑出 RIB 需要的 4 字节
//      这是简化桥的常规做法; 存储控制器只把 WSTRB 当字节使能, 普遍接受。
//   3. 同一时刻只允许一笔 AXI 事务在飞, 与 RIB 的单事务语义一致。
//   4. 不支持 ID 重排与独占访问; cache/protection/region/QoS 全部输出常量。
//
// 时钟: 本模块假定 AXI 侧与 RIB 侧同频同相。若厂商控制器的 AXI 接口在另一个
//       时钟域, 必须在外部加异步 FIFO, 或把本模块改成双时钟。
//
// 参数: AXI_ADDR_WIDTH 只验证过 32; AXI_DATA_WIDTH 支持 32 与 64。
//
// 错误处理: RIB 没有错误响应通道。AXI 返回非 OKAY 时置位 error_o(粘滞, 只能靠
//       复位清除), 顶层应把它接进某个状态寄存器供软件查询。
module axi_bridge #(
    parameter AXI_ID_WIDTH   = 4,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32
)(

    input wire clk,
    input wire rst_n,

    // ---- RIB 从设备侧 ----
    input wire[31:0] addr_i,
    input wire[31:0] data_i,
    input wire[3:0] sel_i,
    input wire we_i,
    output wire[31:0] data_o,
    input wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input wire rsp_ready_i,

    output wire error_o,

    // ---- AXI 主设备侧: 读地址通道 ----
    output wire[AXI_ID_WIDTH-1:0] m_axi_arid,
    output wire[AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize,
    output wire[1:0] m_axi_arburst,
    output wire m_axi_arvalid,
    input wire m_axi_arready,

    // ---- AXI 主设备侧: 读数据通道 ----
    input wire[AXI_ID_WIDTH-1:0] m_axi_rid,
    input wire[AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,

    // ---- AXI 主设备侧: 写地址通道 ----
    output wire[AXI_ID_WIDTH-1:0] m_axi_awid,
    output wire[AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize,
    output wire[1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,

    // ---- AXI 主设备侧: 写数据通道 ----
    output wire[AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire[AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,

    // ---- AXI 主设备侧: 写响应通道 ----
    input wire[AXI_ID_WIDTH-1:0] m_axi_bid,
    input wire[1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready

    );

    localparam AXI_BYTES = AXI_DATA_WIDTH / 8;

    // 地址向下对齐: 4 字节数据宽度得到 ~3, 8 字节得到 ~7
    localparam [31:0] ADDR_ALIGN = ~(AXI_BYTES - 1);

    // AXI 单拍事务的尺寸编码: 每拍字节数的 log2
    localparam [2:0] AXI_SIZE = (AXI_BYTES == 8) ? 3'd3 : 3'd2;

    localparam [1:0] AXI_INCR = 2'b01;

    // 事务状态机。读走 AR->RD, 写走 AW->B, 之后统一回到 RESP 等 RIB 取走响应。
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_AR   = 3'd1;
    localparam [2:0] S_RD   = 3'd2;
    localparam [2:0] S_AW   = 3'd3;
    localparam [2:0] S_B    = 3'd4;
    localparam [2:0] S_RESP = 3'd5;

    reg [2:0] state;

    // 请求握手时锁存: 之后地址与仲裁变化都不影响本笔事务
    reg [31:0] req_addr;
    reg [31:0] req_wdata;
    reg [3:0]  req_sel;
    reg        req_we;

    reg [31:0] rd_data;

    // 写地址通道与写数据通道的握手可能不在同一拍, 用粘滞位分别记录
    reg aw_done;
    reg w_done;

    reg error_r;


    // *************************** AXI 读出信号 **************************

    assign m_axi_arid    = {AXI_ID_WIDTH{1'b0}};
    assign m_axi_araddr  = req_addr & ADDR_ALIGN;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = AXI_SIZE;
    assign m_axi_arburst = AXI_INCR;
    assign m_axi_arvalid = (state == S_AR);
    assign m_axi_rready  = (state == S_RD);

    assign m_axi_awid    = {AXI_ID_WIDTH{1'b0}};
    assign m_axi_awaddr  = req_addr & ADDR_ALIGN;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = AXI_SIZE;
    assign m_axi_awburst = AXI_INCR;
    assign m_axi_awvalid = (state == S_AW) && (!aw_done);

    assign m_axi_wlast   = 1'b1;                     // 单拍事务, 这一拍就是最后一拍
    assign m_axi_wvalid  = (state == S_AW) && (!w_done);

    assign m_axi_bready  = (state == S_B);

    // 写数据按地址低位放进对应的字节通道, 字节使能随之平移。
    // AXI 数据宽度超过 32 位时, 一次 RIB 事务只占其中一个 4 字节通道。
    generate
        if (AXI_BYTES == 4) begin: g_write_32
            assign m_axi_wdata = req_wdata;
            assign m_axi_wstrb = req_sel;
        end else begin: g_write_64
            assign m_axi_wdata = req_addr[2] ? {req_wdata, 32'h0} : {32'h0, req_wdata};
            assign m_axi_wstrb = req_addr[2] ? {req_sel, 4'h0} : {4'h0, req_sel};
        end
    endgenerate

    // 读回整拍后, 按地址低位挑出 RIB 要的那 4 字节
    wire [31:0] rd_lane;
    generate
        if (AXI_BYTES == 4) begin: g_read_32
            assign rd_lane = m_axi_rdata[31:0];
        end else begin: g_read_64
            assign rd_lane = req_addr[2] ? m_axi_rdata[63:32] : m_axi_rdata[31:0];
        end
    endgenerate


    // *************************** 事务状态机 ****************************

    wire ar_hs = m_axi_arvalid && m_axi_arready;
    wire r_hs  = m_axi_rvalid && m_axi_rready;
    wire aw_hs = m_axi_awvalid && m_axi_awready;
    wire w_hs  = m_axi_wvalid && m_axi_wready;
    wire b_hs  = m_axi_bvalid && m_axi_bready;

    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            req_addr  <= 32'h0;
            req_wdata <= 32'h0;
            req_sel   <= 4'h0;
            req_we    <= 1'b0;
            rd_data   <= 32'h0;
            aw_done   <= 1'b0;
            w_done    <= 1'b0;
            error_r   <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (req_valid_i && req_ready_o) begin
                        req_addr  <= addr_i;
                        req_wdata <= data_i;
                        req_sel   <= sel_i;
                        req_we    <= we_i;
                        aw_done   <= 1'b0;
                        w_done    <= 1'b0;
                        state     <= we_i ? S_AW : S_AR;
                    end
                end

                S_AR: begin
                    if (ar_hs) begin
                        state <= S_RD;
                    end
                end

                S_RD: begin
                    if (r_hs) begin
                        rd_data <= rd_lane;
                        // 单拍事务只应收到一拍, 且必须是 OKAY
                        if ((!m_axi_rlast) || (m_axi_rresp != 2'b00)) begin
                            error_r <= 1'b1;
                        end
                        state <= S_RESP;
                    end
                end

                S_AW: begin
                    if (aw_hs) begin
                        aw_done <= 1'b1;
                    end
                    if (w_hs) begin
                        w_done <= 1'b1;
                    end
                    // 两个通道都完成才进入等响应
                    if ((aw_done | aw_hs) && (w_done | w_hs)) begin
                        state <= S_B;
                    end
                end

                S_B: begin
                    if (b_hs) begin
                        if (m_axi_bresp != 2'b00) begin
                            error_r <= 1'b1;
                        end
                        state <= S_RESP;
                    end
                end

                S_RESP: begin
                    if (rsp_ready_i) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end


    // *************************** RIB 从设备侧 **************************

    // 只在空闲时接受新请求, 因此不会覆盖正在返回的响应
    assign req_ready_o = (state == S_IDLE);
    assign rsp_valid_o = (state == S_RESP);

    // 写事务回读数据(与简单存储器一致); RIB 没有字节选择, 写回原值即可
    assign data_o      = req_we ? req_wdata : rd_data;

    assign error_o     = error_r;

endmodule
