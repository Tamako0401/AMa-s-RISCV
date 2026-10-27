// 返回地址栈 (RAS: Return Address Stack)
//
// BTB 记不住 ret 的目标 (每次从不同的调用点返回), 用栈来预测: 调用时压入返回地址, 返回时弹出。
//
// 两份栈:
//   - 投机栈: 取指时按 BTB 标出的调用/返回更新, 返回的预测目标就是它的栈顶;
//   - 提交栈: EX 执行调用/返回时更新, 只反映已经执行的指令。
// 冲刷时错误路径上的压栈/弹栈全部作废: 投机栈整份换成提交栈 (含 EX 这一拍的更新)。
// 栈是环形的, 溢出时覆盖最老的一项, 只会让很深的递归返回预测错, 不影响正确性 (EX 会检查目标)。
module ras #(
    parameter integer DEPTH = 4,
    parameter integer AW    = 2
) (
    input wire clk,
    input wire rst_n,

    input wire flush_i,

    // 取指: 投机更新, 栈顶给出返回的预测目标
    input  wire        spec_push_i,
    input  wire        spec_pop_i,
    input  wire [31:0] spec_addr_i,
    output wire [31:0] top_o,

    // EX: 执行到调用/返回时更新
    input wire        cmt_push_i,
    input wire        cmt_pop_i,
    input wire [31:0] cmt_addr_i
);

    // ptr 指向栈顶那一项
    reg [31:0] s_mem[0:DEPTH-1];
    reg [31:0] c_mem[0:DEPTH-1];
    reg [AW-1:0] s_ptr, c_ptr;

    wire [AW-1:0] c_ptr_up = c_ptr + 1'b1;
    wire [AW-1:0] c_ptr_next = cmt_push_i ? c_ptr_up : cmt_pop_i ? c_ptr - 1'b1 : c_ptr;
    wire [AW-1:0] s_ptr_up = s_ptr + 1'b1;

    assign top_o = s_mem[s_ptr];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_ptr <= {AW{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) c_mem[i] <= 32'h0;
        end else begin
            if (cmt_push_i) c_mem[c_ptr_up] <= cmt_addr_i;
            c_ptr <= c_ptr_next;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_ptr <= {AW{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) s_mem[i] <= 32'h0;
        end else if (flush_i) begin
            for (i = 0; i < DEPTH; i = i + 1)
                s_mem[i] <= (cmt_push_i && c_ptr_up == i[AW-1:0]) ? cmt_addr_i : c_mem[i];
            s_ptr <= c_ptr_next;
        end else if (spec_push_i) begin
            s_mem[s_ptr_up] <= spec_addr_i;
            s_ptr <= s_ptr_up;
        end else if (spec_pop_i) begin
            s_ptr <= s_ptr - 1'b1;
        end
    end

endmodule
