// 1장 보드 Top: UART 계산기. 인스턴스와 배선만 둔다 (기능은 하위 모듈).
//   1-1 에코 → 1-2 MAC 누산 → 1-3 DSP 곱 → 1-4 파이프라인. sw[1:0]으로 1-2·1-3·1-4 코어를 고른다.
//   led[15:0] = 누산값 아래 16비트, 7세그먼트 = 같은 값 16진수 4자리.
`timescale 1ns/1ps
`default_nettype none
module basys3_p01_top #(
    parameter integer CLK_HZ       = 100000000,
    parameter integer BAUD         = 115200,
    parameter integer REFRESH_BITS = 18,
    parameter integer STAGE        = 4      // 끝낸 서브젝트 수: 1 = 1-1 … 4 = 1-4 (서브젝트마다 보드 확인용 빌드)
) (
    input  wire        clk,
    input  wire        btnC,
    input  wire        uart_rxd,
    input  wire [1:0]  sw,
    output wire        uart_txd,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp
);
    wire               resetn;
    wire [7:0]         rx_data, tx_data;
    wire               rx_valid, rx_ready, tx_valid, tx_ready;
    wire               framing_error, overrun;
    wire               mac_clear, mac_valid, acc_valid;
    wire signed [15:0] mac_a, mac_b;
    wire signed [39:0] acc;
    wire [1:0]         sel;

    p01_reset_sync rst (.clk(clk), .btnC(btnC), .resetn(resetn));

    uart_core #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) uart (
        .clk(clk), .resetn(resetn), .uart_rxd_i(uart_rxd), .uart_txd_o(uart_txd),
        .rx_out_data(rx_data), .rx_out_valid(rx_valid), .rx_out_ready(rx_ready),
        .tx_in_data(tx_data), .tx_in_valid(tx_valid), .tx_in_ready(tx_ready),
        .rx_framing_error_o(framing_error), .rx_overrun_o(overrun));

    p01_calc_controller #(.STAGE(STAGE)) ctrl (
        .clk(clk), .resetn(resetn),
        .rx_data_i(rx_data), .rx_valid_i(rx_valid), .rx_ready_o(rx_ready),
        .tx_data_o(tx_data), .tx_valid_o(tx_valid), .tx_ready_i(tx_ready),
        .clear_o(mac_clear), .valid_o(mac_valid), .a_o(mac_a), .b_o(mac_b),
        .acc_i(acc), .acc_valid_i(acc_valid));

    p01_mac_bank #(.STAGE(STAGE)) bank (
        .clk(clk), .resetn(resetn), .clear_i(mac_clear), .valid_i(mac_valid),
        .a_i(mac_a), .b_i(mac_b), .sel_i(sw), .acc_o(acc), .valid_o(acc_valid), .sel_o(sel));

    p01_hex4_display #(.REFRESH_BITS(REFRESH_BITS)) disp (
        .clk(clk), .resetn(resetn), .value_i(acc[15:0]), .seg_o(seg), .an_o(an), .dp_o(dp));

    assign led = acc[15:0];
endmodule
`default_nettype wire
