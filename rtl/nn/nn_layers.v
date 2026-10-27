// 由 model/nn_export.py 生成, 不要手改。层表: 硬件按 idx 取这一层的全部参数。
module nn_layers (
    input wire [3:0] idx,
    output reg mode,  // 0 = 普通卷积, 1 = depthwise
    output reg [2:0] k,  // 核大小 1 / 3 / 5
    output reg stride2,
    output reg [6:0] cin,
    output reg [6:0] cout,
    output reg [7:0] in_w,
    output reg [7:0] in_h,
    output reg [7:0] out_w,
    output reg [7:0] out_h,
    output reg relu,
    output reg src_in,  // 1 = 源是输入图像 RAM, 0 = 特征缓冲
    output reg dst_b,   // 0 = 缓冲 A, 1 = 缓冲 B
    output reg [10:0] w_base,
    output reg [9:0] bm_base,
    output reg [5:0] sh,
    output reg signed [7:0] zout,
    output reg signed [7:0] pad_q
);
    always @(*) begin
        case (idx)
            // 0: conv0 conv k3 s2 3->16 160x120->80x60
            4'd0: begin
                mode = 1'b0; k = 3'd3; stride2 = 1'b1;
                cin = 7'd3; cout = 7'd16;
                in_w = 8'd160; in_h = 8'd120; out_w = 8'd80; out_h = 8'd60;
                relu = 1'b1; src_in = 1'b1; dst_b = 1'b0;
                w_base = 11'd0; bm_base = 10'd0; sh = 6'd38;
                zout = 8'sh80; pad_q = 8'sh00;
            end
            // 1: dw1 dw k3 s2 16->16 80x60->40x30
            4'd1: begin
                mode = 1'b1; k = 3'd3; stride2 = 1'b1;
                cin = 7'd16; cout = 7'd16;
                in_w = 8'd80; in_h = 8'd60; out_w = 8'd40; out_h = 8'd30;
                relu = 1'b1; src_in = 1'b0; dst_b = 1'b1;
                w_base = 11'd27; bm_base = 10'd16; sh = 6'd38;
                zout = 8'sh80; pad_q = 8'sh80;
            end
            // 2: pw1 conv k1 s1 16->32 40x30->40x30
            4'd2: begin
                mode = 1'b0; k = 3'd1; stride2 = 1'b0;
                cin = 7'd16; cout = 7'd32;
                in_w = 8'd40; in_h = 8'd30; out_w = 8'd40; out_h = 8'd30;
                relu = 1'b1; src_in = 1'b0; dst_b = 1'b0;
                w_base = 11'd36; bm_base = 10'd32; sh = 6'd37;
                zout = 8'sh80; pad_q = 8'sh80;
            end
            // 3: dw2 dw k3 s2 32->32 40x30->20x15
            4'd3: begin
                mode = 1'b1; k = 3'd3; stride2 = 1'b1;
                cin = 7'd32; cout = 7'd32;
                in_w = 8'd40; in_h = 8'd30; out_w = 8'd20; out_h = 8'd15;
                relu = 1'b1; src_in = 1'b0; dst_b = 1'b1;
                w_base = 11'd68; bm_base = 10'd64; sh = 6'd37;
                zout = 8'sh80; pad_q = 8'sh80;
            end
            // 4: pw2 conv k1 s1 32->64 20x15->20x15
            4'd4: begin
                mode = 1'b0; k = 3'd1; stride2 = 1'b0;
                cin = 7'd32; cout = 7'd64;
                in_w = 8'd20; in_h = 8'd15; out_w = 8'd20; out_h = 8'd15;
                relu = 1'b1; src_in = 1'b0; dst_b = 1'b0;
                w_base = 11'd86; bm_base = 10'd96; sh = 6'd38;
                zout = 8'sh80; pad_q = 8'sh80;
            end
            // 5: dw3 dw k5 s1 64->64 20x15->20x15
            4'd5: begin
                mode = 1'b1; k = 3'd5; stride2 = 1'b0;
                cin = 7'd64; cout = 7'd64;
                in_w = 8'd20; in_h = 8'd15; out_w = 8'd20; out_h = 8'd15;
                relu = 1'b1; src_in = 1'b0; dst_b = 1'b1;
                w_base = 11'd214; bm_base = 10'd160; sh = 6'd37;
                zout = 8'sh80; pad_q = 8'sh80;
            end
            // 6: pw3 conv k1 s1 64->64 20x15->20x15
            4'd6: begin
                mode = 1'b0; k = 3'd1; stride2 = 1'b0;
                cin = 7'd64; cout = 7'd64;
                in_w = 8'd20; in_h = 8'd15; out_w = 8'd20; out_h = 8'd15;
                relu = 1'b1; src_in = 1'b0; dst_b = 1'b0;
                w_base = 11'd314; bm_base = 10'd224; sh = 6'd38;
                zout = 8'sh80; pad_q = 8'sh80;
            end
            // 7: dw4 dw k5 s1 64->64 20x15->20x15
            4'd7: begin
                mode = 1'b1; k = 3'd5; stride2 = 1'b0;
                cin = 7'd64; cout = 7'd64;
                in_w = 8'd20; in_h = 8'd15; out_w = 8'd20; out_h = 8'd15;
                relu = 1'b1; src_in = 1'b0; dst_b = 1'b1;
                w_base = 11'd570; bm_base = 10'd288; sh = 6'd38;
                zout = 8'sh80; pad_q = 8'sh80;
            end
            // 8: pw4 conv k1 s1 64->64 20x15->20x15
            4'd8: begin
                mode = 1'b0; k = 3'd1; stride2 = 1'b0;
                cin = 7'd64; cout = 7'd64;
                in_w = 8'd20; in_h = 8'd15; out_w = 8'd20; out_h = 8'd15;
                relu = 1'b1; src_in = 1'b0; dst_b = 1'b0;
                w_base = 11'd670; bm_base = 10'd352; sh = 6'd37;
                zout = 8'sh80; pad_q = 8'sh80;
            end
            // 9: head conv k1 s1 64->4 20x15->20x15
            4'd9: begin
                mode = 1'b0; k = 3'd1; stride2 = 1'b0;
                cin = 7'd64; cout = 7'd4;
                in_w = 8'd20; in_h = 8'd15; out_w = 8'd20; out_h = 8'd15;
                relu = 1'b0; src_in = 1'b0; dst_b = 1'b1;
                w_base = 11'd926; bm_base = 10'd416; sh = 6'd38;
                zout = 8'sh06; pad_q = 8'sh80;
            end
            default: begin
                mode = 1'b0; k = 3'd1; stride2 = 1'b0; cin = 7'd1; cout = 7'd16;
                in_w = 8'd1; in_h = 8'd1; out_w = 8'd1; out_h = 8'd1;
                relu = 1'b0; src_in = 1'b1; dst_b = 1'b0;
                w_base = 11'd0; bm_base = 10'd0; sh = 6'd0; zout = 8'sh80; pad_q = 8'sh80;
            end
        endcase
    end
endmodule
