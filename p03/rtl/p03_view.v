// 3장 LED·7세그먼트.
//   LED[9:0]  마지막 실행(R·H·G·M)의 클래스 원-핫 (실행 전 꺼짐)
//   LED[13]   마지막 프레임이 길었음 (F:LONG),  LED[14] 짧았음 (F:SHORT),  LED[15] 프레임을 들고 있음
//   7세그먼트 콘솔 마지막 값 16진수 4자리 (실행 = 클래스, p = 화소) — 1장 p01_hex4_display
`timescale 1ns/1ps
`default_nettype none
module p03_view #(
    parameter integer REFRESH_BITS = 18
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] value_i,
    input  wire [3:0]  class_i,
    input  wire        class_ok_i,
    input  wire        frame_valid_i,
    input  wire        fshort_i,
    input  wire        flong_i,
    output wire [15:0] led_o,
    output wire [6:0]  seg_o,
    output wire [3:0]  an_o,
    output wire        dp_o
);
    wire [9:0] onehot = class_ok_i ? (10'd1 << class_i) : 10'd0;
    assign led_o = {frame_valid_i, fshort_i, flong_i, 3'd0, onehot};

    p01_hex4_display #(.REFRESH_BITS(REFRESH_BITS)) u_hex (
        .clk(clk), .resetn(resetn), .value_i(value_i), .seg_o(seg_o), .an_o(an_o), .dp_o(dp_o));
endmodule
`default_nettype wire
