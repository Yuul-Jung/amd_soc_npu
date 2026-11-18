`timescale 1ns/1ps
`default_nettype none
module bram_sync_buffer #(
    parameter integer DATA_WIDTH=16, ADDR_WIDTH=8
) (
    input wire clk, resetn, wr_en, rd_en,
    input wire [ADDR_WIDTH-1:0] wr_addr, rd_addr,
    input wire signed [DATA_WIDTH-1:0] wr_data,
    output reg signed [DATA_WIDTH-1:0] rd_data,
    output reg rd_valid
);
    (* ram_style="block" *) reg signed [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    // 배열에는 Reset 루프를 두지 않는다. Reset 중 쓰기는 억제한다.
    always @(posedge clk) begin
        if (resetn && wr_en) mem[wr_addr] <= wr_data;
        if (!resetn) begin
            rd_data <= 0;
            rd_valid <= 0;
        end else begin
            rd_valid <= rd_en;
            if (rd_en) rd_data <= mem[rd_addr];
        end
    end
endmodule
`default_nettype wire
