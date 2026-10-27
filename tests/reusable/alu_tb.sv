`timescale 1ns / 1ps
module alu_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg req_alu_i = 0;
    reg [31:0] alu_op1_i = 0;
    reg [31:0] alu_op2_i = 0;
    reg alu_op_add_i = 0;
    reg alu_op_sub_i = 0;
    reg alu_op_sll_i = 0;
    reg alu_op_slt_i = 0;
    reg alu_op_sltu_i = 0;
    reg alu_op_xor_i = 0;
    reg alu_op_srl_i = 0;
    reg alu_op_sra_i = 0;
    reg alu_op_or_i = 0;
    reg alu_op_and_i = 0;
    reg req_bjp_i = 0;
    reg bjp_op_jump_i = 0;
    reg [31:0] bjp_jump_op1_i = 0;
    reg [31:0] bjp_jump_op2_i = 0;
    reg req_csr_i = 0;
    reg [31:0] csr_op1_i = 0;
    reg [31:0] csr_op2_i = 0;
    reg csr_csrrw_i = 0;
    reg csr_csrrs_i = 0;
    reg csr_csrrc_i = 0;
    wire [31:0] alu_res_o;
    wire [31:0] bjp_res_o;
    exu_alu_datapath dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_alu_i(req_alu_i),
        .alu_op1_i(alu_op1_i),
        .alu_op2_i(alu_op2_i),
        .alu_op_add_i(alu_op_add_i),
        .alu_op_sub_i(alu_op_sub_i),
        .alu_op_sll_i(alu_op_sll_i),
        .alu_op_slt_i(alu_op_slt_i),
        .alu_op_sltu_i(alu_op_sltu_i),
        .alu_op_xor_i(alu_op_xor_i),
        .alu_op_srl_i(alu_op_srl_i),
        .alu_op_sra_i(alu_op_sra_i),
        .alu_op_or_i(alu_op_or_i),
        .alu_op_and_i(alu_op_and_i),
        .req_bjp_i(req_bjp_i),
        .bjp_op_jump_i(bjp_op_jump_i),
        .bjp_jump_op1_i(bjp_jump_op1_i),
        .bjp_jump_op2_i(bjp_jump_op2_i),
        .req_csr_i(req_csr_i),
        .csr_op1_i(csr_op1_i),
        .csr_op2_i(csr_op2_i),
        .csr_csrrw_i(csr_csrrw_i),
        .csr_csrrs_i(csr_csrrs_i),
        .csr_csrrc_i(csr_csrrc_i),
        .alu_res_o(alu_res_o),
        .bjp_res_o(bjp_res_o)
    );
    task static clear_ops;
        begin
            alu_op_add_i  = 0;
            alu_op_sub_i  = 0;
            alu_op_sll_i  = 0;
            alu_op_slt_i  = 0;
            alu_op_sltu_i = 0;
            alu_op_xor_i  = 0;
            alu_op_srl_i  = 0;
            alu_op_sra_i  = 0;
            alu_op_or_i   = 0;
            alu_op_and_i  = 0;
        end
    endtask
    integer n, op;
    reg [31:0] expected;
    initial begin
        req_alu_i = 1;
        for (n = 0; n < 256; n = n + 1) begin
            alu_op1_i = $random;
            alu_op2_i = $random;
            if (n == 0) begin
                alu_op1_i = 32'h80000000;
                alu_op2_i = 31;
            end
            if (n == 1) begin
                alu_op1_i = 32'hffffffff;
                alu_op2_i = 1;
            end
            for (op = 0; op < 10; op = op + 1) begin
                clear_ops();
                case (op)
                    0: begin
                        alu_op_add_i = 1;
                        expected = alu_op1_i + alu_op2_i;
                    end
                    1: begin
                        alu_op_sub_i = 1;
                        expected = alu_op1_i - alu_op2_i;
                    end
                    2: begin
                        alu_op_sll_i = 1;
                        expected = alu_op1_i << alu_op2_i[4:0];
                    end
                    3: begin
                        alu_op_slt_i = 1;
                        expected = $signed(alu_op1_i) < $signed(alu_op2_i);
                    end
                    4: begin
                        alu_op_sltu_i = 1;
                        expected = alu_op1_i < alu_op2_i;
                    end
                    5: begin
                        alu_op_xor_i = 1;
                        expected = alu_op1_i ^ alu_op2_i;
                    end
                    6: begin
                        alu_op_srl_i = 1;
                        expected = alu_op1_i >> alu_op2_i[4:0];
                    end
                    7: begin
                        alu_op_sra_i = 1;
                        expected = $signed(alu_op1_i) >>> alu_op2_i[4:0];
                    end
                    8: begin
                        alu_op_or_i = 1;
                        expected = alu_op1_i | alu_op2_i;
                    end
                    9: begin
                        alu_op_and_i = 1;
                        expected = alu_op1_i & alu_op2_i;
                    end
                    default: begin
                    end
                endcase
                #1;
                if (alu_res_o !== expected) $fatal(1, "ALU op %0d vector %0d", op, n);
            end
        end
        clear_ops();
        req_alu_i = 0;
        req_bjp_i = 1;
        bjp_jump_op1_i = 32'h80000000;
        bjp_jump_op2_i = 16;
        #1;
        if (bjp_res_o !== 32'h80000010) $fatal(1, "branch target");
        req_bjp_i = 0;
        req_csr_i   = 1;
        csr_op1_i   = 8'ha5;
        csr_op2_i   = 8'h50;
        csr_csrrs_i = 1;
        #1;
        if (alu_res_o !== 8'hf5) $fatal(1, "CSR set datapath");
        csr_csrrs_i = 0;
        csr_csrrc_i = 1;
        csr_op2_i   = ~32'h5;
        #1;
        if (alu_res_o !== 8'ha0) $fatal(1, "CSR clear pre-inverted mask contract");
        $display("PASS ALU: 2560 arithmetic vectors, branch target and CSR datapaths");
        $finish;
    end
endmodule
