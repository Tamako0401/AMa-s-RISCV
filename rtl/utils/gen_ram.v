// Imported and adapted for AMa-s-RISCV, 2026-09-25.
// Changes: Normalize line endings to LF and remove trailing whitespace. Remove dependency on upstream core/defines.v.
//   Add an optional INIT_FILE parameter (guarded $readmemh) so callers such as
//   rtl/perips/ram.v can preload storage contents.
// Provenance: docs/third-party.md and third_party/tinyriscv-manifest.json.
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



module gen_ram #(
    parameter DP = 512,
    parameter DW = 32,
    parameter MW = 4,
    parameter AW = 32,
    parameter INIT_FILE = ""
) (  // 初值 hex 文件名; 为空则不初始化

    input wire clk,
    input wire [AW-1:0] addr_i,
    input wire [DW-1:0] data_i,
    input wire [MW-1:0] sel_i,
    input wire we_i,

    output wire [DW-1:0] data_o

);

    reg [DW-1:0] ram[0:DP-1];
    reg [AW-1:0] addr_r;
    wire [MW-1:0] wen;
    wire ren;

    // 初值: 仿真用 $readmemh 载入(文件名为空则保持未初始化);
    // 能否被综合工具推断成存储初值尚未验证。
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram);
        end
    end

    assign ren = (~we_i);
    assign wen = ({MW{we_i}} & sel_i);

    always @(posedge clk) begin
        if (ren) begin
            addr_r <= addr_i;
        end
    end

    assign data_o = ram[addr_r];

    genvar i;

    generate
        for (i = 0; i < MW; i = i + 1) begin : g_sel_width
            if ((8 * i + 8) > DW) begin : g_i_gt_8
                always @(posedge clk) begin : i_gt_8_ff
                    if (wen[i]) begin : gt_8_wen
                        ram[addr_i][DW-1:8*i] <= data_i[DW-1:8*i];
                    end
                end
            end else begin : g_i_lt_8
                always @(posedge clk) begin : i_lt_8_ff
                    if (wen[i]) begin : lt_8_wen
                        ram[addr_i][8*i+7:8*i] <= data_i[8*i+7:8*i];
                    end
                end
            end
        end
    endgenerate

endmodule
