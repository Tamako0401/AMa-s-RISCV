`timescale 1ns/1ps

module alu_tb;

reg  [31:0] a;
reg  [31:0] b;
reg  [2:0]  op;
wire [31:0] result;

alu dut (
    .a(a),
    .b(b),
    .op(op),
    .result(result)
);

initial begin
    a = 10;
    b = 3;

    op = 3'b000; // add
    #10;

    op = 3'b001; // sub
    #10;

    op = 3'b010; // and
    #10;

    op = 3'b011; // or
    #10;

    $stop;
end

endmodule