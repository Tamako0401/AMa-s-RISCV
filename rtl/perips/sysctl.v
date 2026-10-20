module sysctl #(
    parameter [31:0] HW_ID = 0
) (
    input wire clk,
    input wire rst_n,
    input wire [31:0] addr_i,
    input wire [31:0] data_i,
    input wire [3:0] sel_i,
    input wire we_i,
    output wire [31:0] data_o,
    input wire req_valid_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    input wire rsp_ready_i,
    output reg rom_we
);
    reg response_valid;
    reg [31:0] data_r;
    wire wen = we_i & req_valid_i & req_ready_o;
    wire ren = (~we_i) & req_valid_i & req_ready_o;
    assign req_ready_o = rst_n && (!response_valid || rsp_ready_i);
    assign rsp_valid_o = response_valid;
    assign data_o = data_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_we <= 0;
            response_valid <= 0;
            data_r <= 0;
        end else begin
            if (wen && addr_i[11:2] == 1 && sel_i[0]) rom_we <= data_i[0];
            if (response_valid && rsp_ready_i) response_valid <= 0;
            if (req_valid_i && req_ready_o) begin
                response_valid <= 1;
                data_r <= 0;
            end
            if (ren)
                case (addr_i[11:2])
                    0: data_r <= HW_ID;
                    1: data_r <= {31'b0, rom_we};
                    default: data_r <= 0;
                endcase
        end
    end
endmodule
