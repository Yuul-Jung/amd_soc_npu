// 3장 보드 Top: 8×8 MNIST (CPU 없음). 인스턴스와 배선만 둔다 (기능은 하위 모듈).
//   PC가 손글씨 숫자를 8×8 INT8 프레임으로 보내면 보드가 4PE 코어로 0~9를 고른다.
//   3-1 프레임 → 3-2 64→10 코어 → 3-3 64→8·8→10 → 3-4 MLP 64→8→10. STAGE = 끝낸 서브젝트 수 (1~4).
`timescale 1ns/1ps
`default_nettype none
module basys3_p03_top #(
    parameter integer CLK_HZ       = 100000000,
    parameter integer BAUD         = 115200,
    parameter integer REFRESH_BITS = 18,
    parameter integer STAGE        = 4
) (
    input  wire        clk,
    input  wire        btnC,
    input  wire        uart_rxd,
    output wire        uart_txd,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp
);
    wire               resetn, fe, ov;
    wire [7:0]         rx_data, tx_data, s_data;
    wire               rx_valid, rx_ready, tx_valid, tx_ready;
    wire               s_valid, s_last, s_ready, frame_valid, frame_ack, err_short, err_long;
    wire               px_rd, px_valid;
    wire [5:0]         px_addr, addr;
    wire signed [7:0]  px_data, w;
    wire               w_wr, b_wr, run, run_done, run_err;
    wire [1:0]         layer, run_sel;
    wire [3:0]         cls_wr, run_class, cls;
    wire signed [23:0] b;
    wire [4:0]         shift;
    wire [249:0]       run_scores;
    wire [63:0]        run_hidden;
    wire [15:0]        view;
    wire               cls_ok, fshort, flong;

    p01_reset_sync rst (.clk(clk), .btnC(btnC), .resetn(resetn));

    uart_core #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) uart (
        .clk(clk), .resetn(resetn), .uart_rxd_i(uart_rxd), .uart_txd_o(uart_txd),
        .rx_out_data(rx_data), .rx_out_valid(rx_valid), .rx_out_ready(rx_ready),
        .tx_in_data(tx_data), .tx_in_valid(tx_valid), .tx_in_ready(tx_ready),
        .rx_framing_error_o(fe), .rx_overrun_o(ov));

    p03_console #(.STAGE(STAGE)) con (
        .clk(clk), .resetn(resetn),
        .rx_data_i(rx_data), .rx_valid_i(rx_valid), .rx_ready_o(rx_ready),
        .tx_data_o(tx_data), .tx_valid_o(tx_valid), .tx_ready_i(tx_ready),
        .s_data_o(s_data), .s_valid_o(s_valid), .s_last_o(s_last), .s_ready_i(s_ready),
        .frame_valid_i(frame_valid), .frame_ack_o(frame_ack), .err_short_i(err_short), .err_long_i(err_long),
        .px_rd_o(px_rd), .px_addr_o(px_addr), .px_data_i(px_data), .px_valid_i(px_valid),
        .w_wr_o(w_wr), .b_wr_o(b_wr), .layer_o(layer), .class_o(cls_wr), .addr_o(addr), .w_o(w), .b_o(b),
        .shift_o(shift), .run_sel_o(run_sel), .run_o(run), .run_done_i(run_done), .run_err_i(run_err),
        .run_class_i(run_class), .run_scores_i(run_scores), .run_hidden_i(run_hidden),
        .view_o(view), .cls_o(cls), .cls_ok_o(cls_ok), .fshort_o(fshort), .flong_o(flong));

    p03_bank #(.STAGE(STAGE)) bank (
        .clk(clk), .resetn(resetn),
        .s_data_i(s_data), .s_valid_i(s_valid), .s_last_i(s_last), .s_ready_o(s_ready),
        .frame_valid_o(frame_valid), .frame_ack_i(frame_ack), .err_short_o(err_short), .err_long_o(err_long),
        .px_rd_i(px_rd), .px_addr_i(px_addr), .px_data_o(px_data), .px_valid_o(px_valid),
        .w_wr_i(w_wr), .b_wr_i(b_wr), .layer_i(layer), .class_i(cls_wr), .addr_i(addr), .w_i(w), .b_i(b),
        .shift_i(shift), .run_sel_i(run_sel), .run_i(run), .run_done_o(run_done), .run_err_o(run_err),
        .class_o(run_class), .scores_o(run_scores), .hidden_o(run_hidden));

    p03_view #(.REFRESH_BITS(REFRESH_BITS)) view_out (
        .clk(clk), .resetn(resetn), .value_i(view), .class_i(cls), .class_ok_i(cls_ok),
        .frame_valid_i(frame_valid), .fshort_i(fshort), .flong_i(flong),
        .led_o(led), .seg_o(seg), .an_o(an), .dp_o(dp));
endmodule
`default_nettype wire
