// VGA monitor for a 640x480 OV7670 RGB565 stream.
// One pixel in four is stored in each direction and enlarged 4x on output.
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
    output wire [23:0] hdmi_rgb
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
    localparam SCALE_X = H_ACTIVE / FB_W;
    localparam SCALE_Y = V_ACTIVE / FB_H;
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
    wire [7:0] fb_wdata = {in_rgb[23:21], in_rgb[15:13], in_rgb[7:6]};

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
    wire [31:0] fb_raddr_full =
        (({22'b0, v} / SCALE_Y) * FB_W) + ({21'b0, h} / SCALE_X);
    wire [14:0] fb_raddr = active ? fb_raddr_full[14:0] : 15'd0;
    wire [7:0] fb_rdata;

    dpram2c #(
        .DW(8),
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

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            h <= 0;
            v <= 0;
            hdmi_hs <= 1'b1;
            hdmi_vs <= 1'b1;
            hdmi_de <= 1'b0;
        end else begin
            hdmi_hs <= !(h >= H_SYNC_START && h < H_SYNC_END);
            hdmi_vs <= !(v >= V_SYNC_START && v < V_SYNC_END);
            hdmi_de <= active;
            if (h == H_TOTAL-1) begin
                h <= 0;
                if (v == V_TOTAL-1) v <= 0;
                else v <= v + 1'b1;
            end else begin
                h <= h + 1'b1;
            end
        end
    end

    assign hdmi_rgb = hdmi_de && frame_ready_sync[1] ? {
        {fb_rdata[7:5], fb_rdata[7:5], fb_rdata[7:6]},
        {fb_rdata[4:2], fb_rdata[4:2], fb_rdata[4:3]},
        {fb_rdata[1:0], fb_rdata[1:0], fb_rdata[1:0], fb_rdata[1:0]}
    } : 24'b0;
endmodule
