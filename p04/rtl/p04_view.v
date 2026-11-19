// 4장 LED·7세그먼트.
//   LED[9:0]  마지막 784 추론 클래스 원-핫 (추론 전 꺼짐)
//   LED[14]   INT16 x 타일 보관 중,  LED[15] INT8 x 타일 보관 중
//   7세그먼트 콘솔 마지막 값 16진수 4자리 (Q = INT16 값, T = 타일 번호, C = 클래스, K = 클록 수) — 1장 p01_hex4_display
`timescale 1ns/1ps
`default_nettype none
module p04_view #(
    parameter integer REFRESH_BITS = 18
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] value_i,
    input  wire [3:0]  class_i,
    input  wire        class_ok_i,
    input  wire        held8_i,
    input  wire        held16_i,
    output wire [15:0] led_o,
    output wire [6:0]  seg_o,
    output wire [3:0]  an_o,
    output wire        dp_o
);
    wire [9:0] onehot = class_ok_i ? (10'd1 << class_i) : 10'd0;
    assign led_o = {held8_i, held16_i, 4'd0, onehot};

    p01_hex4_display #(.REFRESH_BITS(REFRESH_BITS)) u_hex (
        .clk(clk), .resetn(resetn), .value_i(value_i), .seg_o(seg_o), .an_o(an_o), .dp_o(dp_o));
endmodule
`default_nettype wire
