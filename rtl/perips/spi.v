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


// spi master模块
//
// 适配 AMa-s-RISCV: 本模块原先来自另一个 tinyriscv 系项目, 接口与 rtl/perips/
// 其它外设不一致, 本次只改接口与总线读写路径, SPI 收发逻辑本身未动:
//   - 复位改名 rst -> rst_n。原代码到处判的是 `rst == 1'b0` 才复位, 即实际就是
//     低有效, 只是名字有误导;
//   - 增加 sel_i 字节使能: 写寄存器按 4 个字节分别使能, 与 gpio.v/uart.v 一致;
//   - 增加 req_valid_i/req_ready_o/rsp_valid_o/rsp_ready_i 握手(用 utils/vld_rdy),
//     写使能只在请求真正握手的那一拍有效, 主设备保持 we_i 时不会重复写入;
//   - 读数据改为寄存输出: 原先是组合译码 addr_i, 而 RIB 在请求握手后的下一个
//     周期就会把从设备地址撑掉, 组合译码会在响应周期取到错的寄存器。
module spi(

    input wire clk,
    input wire rst_n,

    input wire[31:0] data_i,
    input wire[31:0] addr_i,
    input wire[3:0] sel_i,
    input wire we_i,
    output wire[31:0] data_o,

    input wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input wire rsp_ready_i,

    output reg spi_mosi,             // spi控制器输出、spi设备输入信号
    input wire spi_miso,             // spi控制器输入、spi设备输出信号
    output wire spi_ss,              // spi设备片选
    output reg spi_clk,              // spi设备时钟，最大频率为输入clk的一半

    output wire lcd_dc,              // LCD命令/数据选择: 0=命令, 1=数据
    output wire lcd_rst_n            // LCD复位, 低有效

    );


    localparam SPI_CTRL   = 4'h0;    // spi_ctrl寄存器地址偏移
    localparam SPI_DATA   = 4'h4;    // spi_data寄存器地址偏移
    localparam SPI_STATUS = 4'h8;    // spi_status寄存器地址偏移
    localparam SPI_DC     = 4'hc;    // spi_dc寄存器地址偏移: [0]=DC, [1]=RST_N

    // spi控制寄存器
    // addr: 0x00
    // [0]: 1: enable, 0: disable
    // [1]: CPOL
    // [2]: CPHA
    // [3]: select slave, 1: select, 0: deselect
    // [15:8]: clk div
    reg[31:0] spi_ctrl;
    // spi数据寄存器
    // addr: 0x04
    // [7:0] cmd or inout data
    reg[31:0] spi_data;
    // spi状态寄存器
    // addr: 0x08
    // [0]: 1: busy, 0: idle
    reg[31:0] spi_status;
    // spi_dc寄存器
    // addr: 0x0c
    // [0]: DC, 0: command, 1: data
    // [1]: RST_N, 0: reset, 1: release
    reg[31:0] spi_dc_reg;

    reg[8:0] clk_cnt;               // 分频计数
    reg en;                         // 使能，开始传输信号，传输期间一直有效
    reg[4:0] spi_clk_edge_cnt;      // spi clk时钟沿的个数
    reg spi_clk_edge_level;         // spi clk沿电平
    reg[7:0] rdata;                 // 从spi设备读回来的数据
    reg done;                       // 传输完成信号
    reg[3:0] bit_index;             // 数据bit索引
    wire[8:0] div_cnt;

    // 总线握手: 写/读只在请求真正被接受的那一拍有效
    wire wen = we_i & req_valid_i & req_ready_o;
    wire ren = (~we_i) & req_valid_i & req_ready_o;
    reg[31:0] data_r;               // 读数据寄存器(在请求那一拍采样地址)


    assign spi_ss = ~spi_ctrl[3];   // SPI设备片选信号

    assign div_cnt = spi_ctrl[15:8];// 0: 2分频，1：4分频，2：8分频，3：16分频，4：32分频，以此类推

    assign lcd_dc    = spi_dc_reg[0];   // LCD命令/数据选择
    assign lcd_rst_n = spi_dc_reg[1];   // LCD复位, 低有效


    // 产生使能信号
    // 传输期间一直有效
    always @ (posedge clk) begin
        if (rst_n == 1'b0) begin
            en <= 1'b0;
        end else begin
            if (spi_ctrl[0] == 1'b1) begin
                en <= 1'b1;
            end else if (done == 1'b1) begin
                en <= 1'b0;
            end else begin
                en <= en;
            end
        end
    end

    // 对输入时钟进行计数
    always @ (posedge clk) begin
        if (rst_n == 1'b0) begin
            clk_cnt <= 9'h0;
        end else if (en == 1'b1) begin
            if (clk_cnt == div_cnt) begin
                clk_cnt <= 9'h0;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end else begin
            clk_cnt <= 9'h0;
        end
    end

    // 对spi clk沿进行计数
    // 每当计数到分频值时产生一个上升沿脉冲
    always @ (posedge clk) begin
        if (rst_n == 1'b0) begin
            spi_clk_edge_cnt <= 5'h0;
            spi_clk_edge_level <= 1'b0;
        end else if (en == 1'b1) begin
            // 计数达到分频值
            if (clk_cnt == div_cnt) begin
                if (spi_clk_edge_cnt == 5'd17) begin
                    spi_clk_edge_cnt <= 5'h0;
                    spi_clk_edge_level <= 1'b0;
                end else begin
                    spi_clk_edge_cnt <= spi_clk_edge_cnt + 1'b1;
                    spi_clk_edge_level <= 1'b1;
                end
            end else begin
                spi_clk_edge_level <= 1'b0;
            end
        end else begin
            spi_clk_edge_cnt <= 5'h0;
            spi_clk_edge_level <= 1'b0;
        end
    end

    // bit序列
    always @ (posedge clk) begin
        if (rst_n == 1'b0) begin
            spi_clk <= 1'b0;
            rdata <= 8'h0;
            spi_mosi <= 1'b0;
            bit_index <= 4'h0;
        end else begin
            if (en) begin
                if (spi_clk_edge_level == 1'b1) begin
                    case (spi_clk_edge_cnt)
                        // 第奇数个时钟沿
                        1, 3, 5, 7, 9, 11, 13, 15: begin
                            spi_clk <= ~spi_clk;
                            if (spi_ctrl[2] == 1'b1) begin
                                spi_mosi <= spi_data[bit_index];   // 送出1bit数据
                                bit_index <= bit_index - 1'b1;
                            end else begin
                                rdata <= {rdata[6:0], spi_miso};   // 读1bit数据
                            end
                        end
                        // 第偶数个时钟沿
                        2, 4, 6, 8, 10, 12, 14, 16: begin
                            spi_clk <= ~spi_clk;
                            if (spi_ctrl[2] == 1'b1) begin
                                rdata <= {rdata[6:0], spi_miso};   // 读1bit数据
                            end else begin
                                spi_mosi <= spi_data[bit_index];   // 送出1bit数据
                                bit_index <= bit_index - 1'b1;
                            end
                        end
                        17: begin
                            spi_clk <= spi_ctrl[1];
                        end
                    endcase
                end
            end else begin
                // 初始状态
                spi_clk <= spi_ctrl[1];
                if (spi_ctrl[2] == 1'b0) begin
                    spi_mosi <= spi_data[7];           // 送出最高位数据
                    bit_index <= 4'h6;
                end else begin
                    bit_index <= 4'h7;
                end
            end
        end
    end

    // 产生结束(完成)信号
    always @ (posedge clk) begin
        if (rst_n == 1'b0) begin
            done <= 1'b0;
        end else begin
            if (en && spi_clk_edge_cnt == 5'd17) begin
                done <= 1'b1;
            end else begin
                done <= 1'b0;
            end
        end
    end

    // write reg
    always @ (posedge clk) begin
        if (rst_n == 1'b0) begin
            spi_ctrl <= 32'h0;
            spi_data <= 32'h0;
            spi_status <= 32'h0;
            spi_dc_reg <= 32'h0000_0002;    // RST_N=1(释放), DC=0(命令)
        end else begin
            spi_status[0] <= en;
            if (wen == 1'b1) begin
                case (addr_i[3:0])
                    SPI_CTRL: begin
                        if (sel_i[0]) spi_ctrl[7:0]   <= data_i[7:0];
                        if (sel_i[1]) spi_ctrl[15:8]  <= data_i[15:8];
                        if (sel_i[2]) spi_ctrl[23:16] <= data_i[23:16];
                        if (sel_i[3]) spi_ctrl[31:24] <= data_i[31:24];
                    end
                    SPI_DATA: begin
                        if (sel_i[0]) spi_data[7:0]   <= data_i[7:0];
                        if (sel_i[1]) spi_data[15:8]  <= data_i[15:8];
                        if (sel_i[2]) spi_data[23:16] <= data_i[23:16];
                        if (sel_i[3]) spi_data[31:24] <= data_i[31:24];
                    end
                    SPI_DC: begin
                        if (sel_i[0]) spi_dc_reg[7:0]   <= data_i[7:0];
                        if (sel_i[1]) spi_dc_reg[15:8]  <= data_i[15:8];
                        if (sel_i[2]) spi_dc_reg[23:16] <= data_i[23:16];
                        if (sel_i[3]) spi_dc_reg[31:24] <= data_i[31:24];
                    end
                    default: begin

                    end
                endcase
            end else begin
                spi_ctrl[0] <= 1'b0;
                // 发送完成后更新数据寄存器
                if (done == 1'b1) begin
                    spi_data <= {24'h0, rdata};
                end
            end
        end
    end

    // read reg
    // 必须在请求那一拍采样地址: RIB 在请求握手后的下一个周期就把从设备地址撑掉了
    always @ (posedge clk) begin
        if (rst_n == 1'b0) begin
            data_r <= 32'h0;
        end else begin
            if (ren) begin
                case (addr_i[3:0])
                    SPI_CTRL:   data_r <= spi_ctrl;
                    SPI_DATA:   data_r <= spi_data;
                    SPI_STATUS: data_r <= spi_status;
                    SPI_DC:     data_r <= spi_dc_reg;
                    default:    data_r <= 32'h0;
                endcase
            end else begin
                data_r <= 32'h0;
            end
        end
    end

    assign data_o = data_r;

    // req/rsp 握手时序: 请求被接受后的下一拍拉高 rsp_valid_o, 与 data_r 对齐
    vld_rdy #(
        .CUT_READY(0)
    ) u_vld_rdy(
        .clk(clk),
        .rst_n(rst_n),
        .vld_i(req_valid_i),
        .rdy_o(req_ready_o),
        .rdy_i(rsp_ready_i),
        .vld_o(rsp_valid_o)
    );

endmodule
