// 2장 UART 주인 선택 (2-7부터): sw[2] = 0 디버그 콘솔, 1 = 명령 해석기.
// STAGE < 7이면 콘솔만 있으므로 그대로 잇는다. 스위치는 명령을 주고받지 않을 때 바꾼다.
`timescale 1ns/1ps
`default_nettype none
module p02_uart_switch #(
    parameter integer STAGE = 8
) (
    input  wire       clk,
    input  wire       resetn,
    input  wire       sw_i,               // 보드 스위치 (비동기)
    output wire       owner_engine_o,     // 1 = 명령 해석기
    // uart_core 쪽
    input  wire [7:0] rx_data_i,
    input  wire       rx_valid_i,
    output wire       rx_ready_o,
    output wire [7:0] tx_data_o,
    output wire       tx_valid_o,
    input  wire       tx_ready_i,
    // 콘솔
    output wire       c_rx_valid_o,
    input  wire       c_rx_ready_i,
    input  wire [7:0] c_tx_data_i,
    input  wire       c_tx_valid_i,
    output wire       c_tx_ready_o,
    // 명령 해석기
    output wire       e_rx_valid_o,
    input  wire       e_rx_ready_i,
    input  wire [7:0] e_tx_data_i,
    input  wire       e_tx_valid_i,
    output wire       e_tx_ready_o
);
    reg [1:0] sync;
    always @(posedge clk) begin
        if (!resetn) sync <= 2'b00;
        else         sync <= {sync[0], sw_i};
    end
    wire eng = (STAGE >= 7) && sync[1];
    assign owner_engine_o = eng;

    assign c_rx_valid_o = rx_valid_i && !eng;
    assign e_rx_valid_o = rx_valid_i && eng;
    assign rx_ready_o   = eng ? e_rx_ready_i : c_rx_ready_i;
    assign tx_data_o    = eng ? e_tx_data_i  : c_tx_data_i;
    assign tx_valid_o   = eng ? e_tx_valid_i : c_tx_valid_i;
    assign c_tx_ready_o = tx_ready_i && !eng;
    assign e_tx_ready_o = tx_ready_i && eng;
endmodule
`default_nettype wire
