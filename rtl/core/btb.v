// 分支目标缓存 (BTB: Branch Target Buffer)
//
// 记住"某条分支上次跳到哪、跳不跳", 让取指阶段在分支执行之前就知道目标地址,
// 省掉"取指到 EX 算出目标再重定向"的那几拍。目标地址是查表读出来的, 不是现算的,
// 取指路径上不新增任何加法器。
//
// 表项: { valid, tag, target, counter[1:0] }
//   - 索引取 PC 低位; tag 取 PC 高位, 用来确认命中同一静态分支;
//   - counter 是 2 bit 饱和计数器, counter[1] 为 1 时预测跳转。
//     比 1 bit 好在循环退出这种一次性反向时只错一次。
//
// 只预测条件分支和 jal。jalr 的目标来自寄存器(每次调用点都不同), 不放进 BTB。
//
// 同一拍读写同一格时做旁路(write-through), 把这一拍的更新结果直接送到查表输出,
// 这样刚训练好的分支紧接着执行也能看到最新结果。
//
// tag/target/counter 不复位, 写成组合读的数组, 综合成分布式 RAM (一个写口, 查表和更新各一个读口);
// 只有 valid 是带复位的寄存器。全用寄存器时 32 项就要约 1900 FF + 850 LUT。
module btb #(
    parameter integer ENTRIES = 32,
    parameter integer IDX_W   = 5
) (
    input wire clk,
    input wire rst_n,

    // 取指查表(组合读)
    input  wire [31:0] lookup_pc,
    output wire        lookup_taken,
    output wire [31:0] lookup_target,

    // EX 解析分支时更新
    input wire        upd_en,
    input wire [31:0] upd_pc,
    input wire [31:0] upd_target,
    input wire        upd_taken
);

    localparam integer TAG_W = 32 - 2 - IDX_W;

    // 强制用 LUT RAM: 不加时 PDS 会把一部分放进 DRM (半块), 而 DRM 要留给显示和 nn
    (* syn_ramstyle = "select_ram" *) reg [TAG_W-1:0] tag[0:ENTRIES-1];
    (* syn_ramstyle = "select_ram" *) reg [31:0] target[0:ENTRIES-1];
    (* syn_ramstyle = "select_ram" *) reg [1:0] counter[0:ENTRIES-1];
    reg [ENTRIES-1:0] valid;

    // PC[1:0] 恒为 0, 不参与索引和 tag
    wire [IDX_W-1:0] lookup_idx = lookup_pc[IDX_W+1:2];
    wire [TAG_W-1:0] lookup_tag = lookup_pc[31:IDX_W+2];
    wire [IDX_W-1:0] upd_idx = upd_pc[IDX_W+1:2];
    wire [TAG_W-1:0] upd_tag = upd_pc[31:IDX_W+2];

    wire upd_hit = valid[upd_idx] && (tag[upd_idx] == upd_tag);

    // 计数器饱和增减; 没有命中且这次要跳时分配新表项, 计数从 2(弱跳)开始
    wire [1:0] cnt_up = (counter[upd_idx] == 2'd3) ? 2'd3 : counter[upd_idx] + 2'd1;
    wire [1:0] cnt_dn = (counter[upd_idx] == 2'd0) ? 2'd0 : counter[upd_idx] - 2'd1;
    wire [1:0] next_cnt = upd_hit ? (upd_taken ? cnt_up : cnt_dn) : 2'd2;

    wire next_valid = upd_hit ? 1'b1 : upd_taken;
    wire [TAG_W-1:0] next_tag = upd_hit ? tag[upd_idx] : upd_tag;
    // 只有跳转时目标地址才有意义; 不跳时保留旧目标, 它仍然是这条分支的目标
    wire [31:0] next_target = upd_taken ? upd_target : target[upd_idx];

    // 同拍读写同一格的旁路
    wire same_idx = upd_en && (upd_idx == lookup_idx);
    wire eff_valid = same_idx ? next_valid : valid[lookup_idx];
    wire [TAG_W-1:0] eff_tag = same_idx ? next_tag : tag[lookup_idx];
    wire [31:0] eff_target = same_idx ? next_target : target[lookup_idx];
    wire [1:0] eff_cnt = same_idx ? next_cnt : counter[lookup_idx];

    wire lookup_hit = eff_valid && (eff_tag == lookup_tag);

    assign lookup_taken = lookup_hit && eff_cnt[1];
    assign lookup_target = eff_target;

    wire upd_wr = upd_en && (upd_taken || upd_hit);

    always @(posedge clk) begin
        // 不跳又没命中时不写: 预测本来就是"不跳", 不需要表项
        if (upd_wr) begin
            tag[upd_idx] <= next_tag;
            target[upd_idx] <= next_target;
            counter[upd_idx] <= next_cnt;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid <= {ENTRIES{1'b0}};
        else if (upd_wr) valid[upd_idx] <= next_valid;
    end

endmodule
