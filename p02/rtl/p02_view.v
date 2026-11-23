// 2장 LED·7세그먼트.
//   STAGE 1~7: 콘솔 마지막 결과 아래 16비트 → LED 16개 + 7세그먼트 16진수 4자리 (1장 p01_hex4_display)
//   STAGE 8  : npu_display_controller → LED[3:0] 클래스 원-핫, [13] busy, [14] 끝남, [15] 오류, 7세그먼트 클래스
`timescale 1ns/1ps
`default_nettype none
module p02_view #(
    parameter integer STAGE        = 8,
    parameter integer REFRESH_BITS = 18
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] value_i,
    input  wire [1:0]  class_i,
    input  wire        busy_i,
    input  wire        done_i,
    input  wire        error_i,
    input  wire        protocol_error_i,
    input  wire        uart_framing_error_i,
    input  wire        uart_overrun_i,
    output wire [15:0] led_o,
    output wire [6:0]  seg_o,
    output wire [3:0]  an_o,
    output wire        dp_o
);
    generate if (STAGE >= 8) begin : g_class
        npu_display_controller u_disp (
            .clk(clk), .resetn(resetn), .class_i(class_i), .busy_i(busy_i), .done_i(done_i),
            .error_i(error_i), .protocol_error_i(protocol_error_i),
            .uart_framing_error_i(uart_framing_error_i), .uart_overrun_i(uart_overrun_i),
            .led_o(led_o), .seg_o(seg_o), .an_o(an_o), .dp_o(dp_o));
    end else begin : g_hex
        p01_hex4_display #(.REFRESH_BITS(REFRESH_BITS)) u_hex (
            .clk(clk), .resetn(resetn), .value_i(value_i), .seg_o(seg_o), .an_o(an_o), .dp_o(dp_o));
        assign led_o = value_i;
    end endgenerate
endmodule
`default_nettype wire
