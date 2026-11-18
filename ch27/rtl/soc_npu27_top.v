`timescale 1ns/1ps
`default_nettype none
// 27장 최종 Top: 21장 SoC(soc_npu_wrapper)에 7세그먼트 표시기를 더한다. Top은 연결만 한다.
// LED 출력(GPIO 채널 1)은 보드 LED와 표시기 입력에 함께 간다.
module soc_npu27_top (
    input  wire        clk,
    input  wire        btnC,
    input  wire [15:0] sw,
    output wire [15:0] led,
    input  wire        RsRx,
    output wire        RsTx,
    output wire  [6:0] seg,
    output wire  [3:0] an,
    output wire        dp
);
    soc_npu_wrapper u_soc (
        .clk        (clk),
        .btnC       (btnC),
        .sw_tri_i   (sw),
        .led_tri_o  (led),
        .UART_0_rxd (RsRx),
        .UART_0_txd (RsTx)
    );
    fnd_class_display u_fnd (.clk(clk), .led_word_i(led), .seg_o(seg), .an_o(an), .dp_o(dp));
endmodule
`default_nettype wire
