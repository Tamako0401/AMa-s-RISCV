// VGA monitor for a 640x480 OV7670 RGB565 stream.
// 每 4 点取 1 点存成 160x120 的 RGB565 小图, 左上角原尺寸显示, 其余黑屏。
module ov7670_vga #(
    parameter VSYNC_ACTIVE_LEVEL = 1'b1,
    parameter CAM_W = 640,
    parameter CAM_H = 480,
    parameter SAMPLE_DIV = 4,
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 480,
    parameter H_TOTAL = 800,
    parameter V_TOTAL = 525,
    parameter H_SYNC_START = 656,
    parameter H_SYNC_END = 752,
    parameter V_SYNC_START = 490,
    parameter V_SYNC_END = 492
) (
    input wire sys_clk,
    input wire rst_n,
    input wire cam_pclk,
    input wire cam_vsync,
    input wire cam_href,
    input wire [7:0] cam_data,

    output wire cam_xclk,
    output wire hdmi_pclk,
    output reg hdmi_hs,
    output reg hdmi_vs,
    output reg hdmi_de,
    output wire [23:0] hdmi_rgb,
    output wire frame_ready_o
);
    reg xclk_div = 1'b0;
    reg pixel_clk = 1'b0;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            xclk_div <= 1'b0;
            pixel_clk <= 1'b0;
        end else begin
            xclk_div <= ~xclk_div;
            pixel_clk <= ~pixel_clk;
        end
    end

    assign cam_xclk = xclk_div;
    assign hdmi_pclk = ~pixel_clk;

    wire in_valid, in_sof, in_eol;
    wire [23:0] in_rgb;
    reg [1:0] cam_reset_sync;
    reg [1:0] pixel_reset_sync;
    always @(posedge cam_pclk or negedge rst_n) begin
        if (!rst_n) cam_reset_sync <= 2'b00;
        else cam_reset_sync <= {cam_reset_sync[0], 1'b1};
    end
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) pixel_reset_sync <= 2'b00;
        else pixel_reset_sync <= {pixel_reset_sync[0], 1'b1};
    end
    wire cam_rst_n = cam_reset_sync[1];
    wire pixel_rst_n = pixel_reset_sync[1];

    ov7670_rgb565_rx #(
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_rx (
        .clk(cam_pclk),
        .rst_n(cam_rst_n),
        .vsync(cam_vsync),
        .href(cam_href),
        .data(cam_data),
        .out_valid(in_valid),
        .out_sof(in_sof),
        .out_eol(in_eol),
        .out_data(in_rgb)
    );

    localparam FB_W = CAM_W / SAMPLE_DIV;
    localparam FB_H = CAM_H / SAMPLE_DIV;
    localparam FB_AW = $clog2(FB_W * FB_H);

    reg [9:0] cam_x;
    reg [8:0] cam_y;
    wire [9:0] cx = in_sof ? 10'd0 : cam_x;
    wire [8:0] cy = in_sof ? 9'd0 : cam_y;
    wire sample_pixel = in_valid && (cx % SAMPLE_DIV) == 0 && (cy % SAMPLE_DIV) == 0 &&
        cx < CAM_W && cy < CAM_H;
    wire [31:0] fb_waddr_full =
        (({23'b0, cy} / SAMPLE_DIV) * FB_W) + ({22'b0, cx} / SAMPLE_DIV);
    wire [FB_AW-1:0] fb_waddr = fb_waddr_full[FB_AW-1:0];
    wire [15:0] fb_wdata = {in_rgb[23:19], in_rgb[15:10], in_rgb[7:3]};

    reg frame_ready;
    reg [1:0] frame_ready_sync;
    always @(posedge cam_pclk or negedge cam_rst_n) begin
        if (!cam_rst_n) frame_ready <= 1'b0;
        else if (in_valid && in_eol && cy == CAM_H-1)
            frame_ready <= 1'b1;
    end
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) frame_ready_sync <= 2'b00;
        else frame_ready_sync <= {frame_ready_sync[0], frame_ready};
    end

    always @(posedge cam_pclk or negedge cam_rst_n) begin
        if (!cam_rst_n) begin
            cam_x <= 0;
            cam_y <= 0;
        end else if (in_valid) begin
            if (in_eol) begin
                cam_x <= 0;
                cam_y <= cy + 1'b1;
            end else begin
                cam_x <= cx + 1'b1;
                cam_y <= cy;
            end
        end
    end

    reg [10:0] h;
    reg [9:0] v;
    wire active = h < H_ACTIVE && v < V_ACTIVE;
    wire picture_active = h < FB_W && v < FB_H;
    localparam TEST_BAR_WIDTH = (FB_W + 7) / 8;
    wire [10:0] display_h = h - 1'b1;
    wire [2:0] test_bar = display_h / TEST_BAR_WIDTH;
    reg [23:0] test_rgb;
    always @* begin
        case (test_bar)
            3'd0: test_rgb = 24'hFFFFFF;
            3'd1: test_rgb = 24'hFFFF00;
            3'd2: test_rgb = 24'h00FFFF;
            3'd3: test_rgb = 24'h00FF00;
            3'd4: test_rgb = 24'hFF00FF;
            3'd5: test_rgb = 24'hFF0000;
            3'd6: test_rgb = 24'h0000FF;
            default: test_rgb = 24'h000000;
        endcase
    end
    wire [31:0] fb_raddr_full =
        ({22'b0, v} * FB_W) + {21'b0, h};
    // 用 FB_AW 而不是写死 15: 改 CAM_W/CAM_H 时地址宽度跟着变 (160x120 时就是 15)
    wire [FB_AW-1:0] fb_raddr = picture_active ? fb_raddr_full[FB_AW-1:0] : {FB_AW{1'b0}};
    wire [15:0] fb_rdata;

    dpram2c #(
        .DW(16),
        .DP(FB_W * FB_H),
        .AW(FB_AW)
    ) u_framebuffer (
        .wclk(cam_pclk),
        .we(sample_pixel),
        .waddr(fb_waddr),
        .wdata(fb_wdata),
        .rclk(pixel_clk),
        .raddr(fb_raddr),
        .rdata(fb_rdata)
    );

    // RGB565 -> RGB888 (高位补到低位), 再乘 2 并饱和: 这一版 OV7670 出图偏暗
    wire [7:0] r8 = {fb_rdata[15:11], fb_rdata[15:13]};
    wire [7:0] g8 = {fb_rdata[10:5], fb_rdata[10:9]};
    wire [7:0] b8 = {fb_rdata[4:0], fb_rdata[4:2]};

    function [7:0] brighten(input [7:0] v);
        brighten = v[7:6] != 2'b00 ? 8'hFF : {v[5:0], 2'b00};
    endfunction

    wire [23:0] camera_rgb = {brighten(r8), brighten(g8), brighten(b8)};

    reg picture_de;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            h <= 0;
            v <= 0;
            hdmi_hs <= 1'b1;
            hdmi_vs <= 1'b1;
            hdmi_de <= 1'b0;
            picture_de <= 1'b0;
        end else begin
            hdmi_hs <= !(h >= H_SYNC_START && h < H_SYNC_END);
            hdmi_vs <= !(v >= V_SYNC_START && v < V_SYNC_END);
            hdmi_de <= active;
            picture_de <= picture_active;
            if (h == H_TOTAL-1) begin
                h <= 0;
                if (v == V_TOTAL-1) v <= 0;
                else v <= v + 1'b1;
            end else begin
                h <= h + 1'b1;
            end
        end
    end

    assign hdmi_rgb = hdmi_de && picture_de ?
        (frame_ready_sync[1] ? camera_rgb : test_rgb) : 24'b0;
    assign frame_ready_o = frame_ready;
endmodule
