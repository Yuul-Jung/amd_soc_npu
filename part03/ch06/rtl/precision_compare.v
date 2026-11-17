`timescale 1ns/1ps
module precision_compare #(parameter integer SATURATE=1)(
    input wire clk, resetn, valid_i,
    input wire signed [31:0] x_i,
    output wire signed [7:0] q8_o,
    output wire signed [15:0] q16_o,
    output wire overflow8_o, overflow16_o, valid_o
);
    // 같은 원본을 서로 다른 소수부 정밀도로 변환하되 반올림 규칙은 공유한다.
    fixed_quantizer #(.OUT_WIDTH(8),.SHIFT(8),.ROUND(1),.SATURATE(SATURATE)) q8
      (.clk(clk),.resetn(resetn),.valid_i(valid_i),.x_i(x_i),.q_o(q8_o),.valid_o(valid_o),.overflow_o(overflow8_o));
    fixed_quantizer #(.OUT_WIDTH(16),.SHIFT(4),.ROUND(1),.SATURATE(SATURATE)) q16
      (.clk(clk),.resetn(resetn),.valid_i(valid_i),.x_i(x_i),.q_o(q16_o),.valid_o(),.overflow_o(overflow16_o));
endmodule
