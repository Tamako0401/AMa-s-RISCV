// OV7670 RGB565 byte stream -> RGB888 pixel stream.
// The sensor must be configured for RGB565, MSB byte first, and active-high HREF.
module ov7670_rgb565_rx #(
    parameter VSYNC_ACTIVE_LEVEL = 1'b1
) (
    input wire clk,
    input wire rst_n,
    input wire vsync,
    input wire href,
    input wire [7:0] data,

    output reg out_valid,
    output reg out_sof,
    output reg out_eol,
    output reg [23:0] out_data
);
    reg vsync_q;
    reg href_q;
    reg frame_pending;
    reg byte_phase;
    reg [7:0] byte_hi;
    reg pixel_pending;
    reg [23:0] pixel_data;
    reg pixel_sof;

    wire frame_start = (vsync_q == VSYNC_ACTIVE_LEVEL) && (vsync != VSYNC_ACTIVE_LEVEL);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_q <= VSYNC_ACTIVE_LEVEL;
            href_q <= 1'b0;
            frame_pending <= 1'b1;
            byte_phase <= 1'b0;
            byte_hi <= 8'b0;
            pixel_pending <= 1'b0;
            pixel_data <= 24'b0;
            pixel_sof <= 1'b0;
            out_valid <= 1'b0;
            out_sof <= 1'b0;
            out_eol <= 1'b0;
            out_data <= 24'b0;
        end else begin
            vsync_q <= vsync;
            href_q <= href;
            out_valid <= 1'b0;
            out_sof <= 1'b0;
            out_eol <= 1'b0;

            if (frame_start)
                frame_pending <= 1'b1;

            if (!href) begin
                byte_phase <= 1'b0;
                if (href_q && pixel_pending) begin
                    out_valid <= 1'b1;
                    out_sof <= pixel_sof;
                    out_eol <= 1'b1;
                    out_data <= pixel_data;
                    pixel_pending <= 1'b0;
                end
            end else if (!byte_phase) begin
                byte_hi <= data;
                byte_phase <= 1'b1;
            end else begin
                byte_phase <= 1'b0;
                if (pixel_pending) begin
                    out_valid <= 1'b1;
                    out_sof <= pixel_sof;
                    out_data <= pixel_data;
                end
                pixel_data <= {
                    {byte_hi[7:3], byte_hi[7:5]},
                    {byte_hi[2:0], data[7:5], byte_hi[2:1]},
                    {data[4:0], data[4:2]}
                };
                pixel_sof <= frame_pending || frame_start;
                pixel_pending <= 1'b1;
                if (frame_pending && !frame_start)
                    frame_pending <= 1'b0;
            end
        end
    end
endmodule
