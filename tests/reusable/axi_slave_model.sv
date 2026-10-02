// AXI4 从设备行为模型: 一块字存储器 + 可配置延迟 + 可注入错误。
//
// 只用于仿真, 不可综合。目的是让 axi_bridge.v 的协议转换逻辑能在 iverilog 里
// 完整回归, 而不需要厂商的 DDR3 IP。
//
// 限制: 只接受单拍事务(arlen/awlen = 0)。收到 burst 会直接 $fatal, 因为这正是
//       我们期望 axi_bridge 永远不会发出的东西 —— 用模型当断言用。
`timescale 1ns/1ps
module axi_slave_model #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter WORDS      = 1024,
    parameter RD_LATENCY = 3,      // AR 握手到 RVALID 之间的时钟数
    parameter WR_LATENCY = 2       // AW/W 握手到 BVALID 之间的时钟数
)(

    input wire clk,
    input wire rst_n,

    // 读地址通道
    input wire[ID_WIDTH-1:0] arid,
    input wire[ADDR_WIDTH-1:0] araddr,
    input wire[7:0] arlen,
    input wire[2:0] arsize,
    input wire[1:0] arburst,
    input wire arvalid,
    output reg arready,

    // 读数据通道
    output reg[ID_WIDTH-1:0] rid,
    output reg[DATA_WIDTH-1:0] rdata,
    output reg[1:0] rresp,
    output reg rlast,
    output reg rvalid,
    input wire rready,

    // 写地址通道
    input wire[ID_WIDTH-1:0] awid,
    input wire[ADDR_WIDTH-1:0] awaddr,
    input wire[7:0] awlen,
    input wire[2:0] awsize,
    input wire[1:0] awburst,
    input wire awvalid,
    output reg awready,

    // 写数据通道
    input wire[DATA_WIDTH-1:0] wdata,
    input wire[DATA_WIDTH/8-1:0] wstrb,
    input wire wlast,
    input wire wvalid,
    output reg wready,

    // 写响应通道
    output reg[ID_WIDTH-1:0] bid,
    output reg[1:0] bresp,
    output reg bvalid,
    input wire bready,

    // 置 1 时所有响应返回 SLVERR, 用来验证桥的错误上报
    input wire inject_error

    );

    localparam BYTES = DATA_WIDTH / 8;
    localparam IDX   = $clog2(BYTES);       // 字内地址位数
    localparam AW    = $clog2(WORDS);       // 字地址位数

    // 存储器本体; 测试台可以直接按层次访问(例如 u_slave.mem[3])
    reg [DATA_WIDTH-1:0] mem [0:WORDS-1];

    integer i;

    // *************************** 读通道 *******************************

    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_WAIT = 2'd1;
    localparam [1:0] RD_DATA = 2'd2;

    reg [1:0] rd_state;
    reg [ADDR_WIDTH-1:0] rd_addr_q;
    integer rd_wait;

    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE;
            arready  <= 1'b1;
            rvalid   <= 1'b0;
            rlast    <= 1'b0;
            rdata    <= {DATA_WIDTH{1'b0}};
            rresp    <= 2'b00;
            rid      <= {ID_WIDTH{1'b0}};
            rd_addr_q<= {ADDR_WIDTH{1'b0}};
            rd_wait  <= 0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    rvalid <= 1'b0;
                    if (arvalid && arready) begin
                        if (arlen !== 8'd0)
                            $fatal(1, "axi_slave_model: burst read not supported");
                        if (arsize !== IDX[2:0])
                            $fatal(1, "axi_slave_model: unexpected arsize=%0d", arsize);
                        if (arburst !== 2'b01)
                            $fatal(1, "axi_slave_model: unexpected arburst=%b", arburst);
                        rd_addr_q <= araddr;
                        rid       <= arid;
                        arready   <= 1'b0;
                        rd_wait   <= RD_LATENCY;
                        rd_state  <= RD_WAIT;
                    end
                end

                RD_WAIT: begin
                    if (rd_wait == 0) begin
                        rdata    <= mem[rd_addr_q[AW+IDX-1:IDX]];
                        rresp    <= inject_error ? 2'b10 : 2'b00;
                        rlast    <= 1'b1;
                        rvalid   <= 1'b1;
                        rd_state <= RD_DATA;
                    end else begin
                        rd_wait <= rd_wait - 1;
                    end
                end

                RD_DATA: begin
                    if (rvalid && rready) begin
                        rvalid   <= 1'b0;
                        arready  <= 1'b1;
                        rd_state <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // *************************** 写通道 *******************************

    localparam [1:0] WR_IDLE = 2'd0;
    localparam [1:0] WR_WAIT = 2'd1;
    localparam [1:0] WR_RESP = 2'd2;

    reg [1:0] wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr_q;
    reg [DATA_WIDTH-1:0] wr_data_q;
    reg [BYTES-1:0]      wr_strb_q;
    reg aw_seen, w_seen;
    integer wr_wait;

    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WR_IDLE;
            awready  <= 1'b1;
            wready   <= 1'b1;
            bvalid   <= 1'b0;
            bresp    <= 2'b00;
            bid      <= {ID_WIDTH{1'b0}};
            aw_seen  <= 1'b0;
            w_seen   <= 1'b0;
            wr_wait  <= 0;
            wr_addr_q<= {ADDR_WIDTH{1'b0}};
            wr_data_q<= {DATA_WIDTH{1'b0}};
            wr_strb_q<= {BYTES{1'b0}};
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (awvalid && awready && !aw_seen) begin
                        if (awlen !== 8'd0)
                            $fatal(1, "axi_slave_model: burst write not supported");
                        if (awsize !== IDX[2:0])
                            $fatal(1, "axi_slave_model: unexpected awsize=%0d", awsize);
                        wr_addr_q <= awaddr;
                        bid       <= awid;
                        aw_seen   <= 1'b1;
                        awready   <= 1'b0;
                    end
                    if (wvalid && wready && !w_seen) begin
                        if (!wlast)
                            $fatal(1, "axi_slave_model: single beat must set wlast");
                        wr_data_q <= wdata;
                        wr_strb_q <= wstrb;
                        w_seen    <= 1'b1;
                        wready    <= 1'b0;
                    end
                    // 两个通道都收到后才开始写; 用 or 把"本拍刚完成"也算进去
                    if ((aw_seen || (awvalid && awready)) &&
                        (w_seen  || (wvalid && wready))) begin
                        aw_seen <= 1'b0;
                        w_seen  <= 1'b0;
                        wr_wait <= WR_LATENCY;
                        wr_state<= WR_WAIT;
                    end
                end

                WR_WAIT: begin
                    if (wr_wait == 0) begin
                        for (i = 0; i < BYTES; i = i + 1) begin
                            if (wr_strb_q[i]) begin
                                mem[wr_addr_q[AW+IDX-1:IDX]][8*i +: 8]
                                    <= wr_data_q[8*i +: 8];
                            end
                        end
                        bresp    <= inject_error ? 2'b10 : 2'b00;
                        bvalid   <= 1'b1;
                        wr_state <= WR_RESP;
                    end else begin
                        wr_wait <= wr_wait - 1;
                    end
                end

                WR_RESP: begin
                    if (bvalid && bready) begin
                        bvalid   <= 1'b0;
                        awready  <= 1'b1;
                        wready   <= 1'b1;
                        wr_state <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

endmodule
