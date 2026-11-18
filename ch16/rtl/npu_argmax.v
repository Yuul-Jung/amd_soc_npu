`timescale 1ns/1ps
`default_nettype none
// 16장 순차 argmax: start 뒤 한 클록에 점수 하나씩 비교한다. 같으면 앞 번호를 유지한다 (Python argmax_lowest).
module npu_argmax #(
    parameter integer N = 10,              // 2~16
    parameter integer W = 32
) (
    input  wire           clk,
    input  wire           resetn,
    input  wire           start_i,
    input  wire [N*W-1:0] scores_i,
    output reg            busy_o,
    output reg            done_o,
    output reg      [3:0] class_o
);
    reg [3:0] k_q;
    wire signed [W-1:0] cand = scores_i[k_q*W +: W];
    wire signed [W-1:0] best = scores_i[class_o*W +: W];
    always @(posedge clk) begin
        if (!resetn) begin
            busy_o <= 0; done_o <= 0; class_o <= 0; k_q <= 0;
        end else begin
            done_o <= 0;
            if (!busy_o) begin
                if (start_i) begin busy_o <= 1; class_o <= 0; k_q <= 1; end
            end else begin
                if (cand > best) class_o <= k_q;
                if (k_q == N - 1) begin busy_o <= 0; done_o <= 1; end
                else k_q <= k_q + 4'd1;
            end
        end
    end
endmodule
`default_nettype wire
