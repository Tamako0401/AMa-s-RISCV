module alu(
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [2:0] op,        // op 决定这个硬件现在在干哪种运算
    output wire [31:0] result
);

always @(*) begin
    case (op)

        // 复习一下: 3代表位宽, b代表进制
        3'b000: result = a + b;      // Addition
        3'b001: result = a - b;      // Subtraction
        3'b010: result = a & b;      // Bitwise AND
        3'b011: result = a | b;      // Bitwise OR
        3'b100: result = a ^ b;      // Bitwise XOR
        default: result = 32'b0;     // Default case
    endcase
end

endmodule