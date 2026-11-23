// 4장 보드 Top: 784 가속기 설계 공간. 인스턴스와 배선만 둔다 (기능은 하위 모듈).
//   4-1 INT8/INT16 양자화 비교 → 4-2 784 INT8 13타일 → 4-3 INT16 → 4-4 1PE·4PE·8PE 클록 비교.
//   PC가 타일마다 가중치 640개와 x 64개를 보내고 T로 실행한다 (가중치 재적재 = 4-4의 적재 병목).
//   STAGE = 끝낸 서브젝트 수 (1~4).
`timescale 1ns/1ps
`default_nettype none
module basys3_p04_top #(
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
    wire               q_valid, q_done, q_ov8, q_ov16;
    wire signed [31:0] q_x;
    wire signed [7:0]  q8;
    wire signed [15:0] q16, x16_data, w;
    wire               s_valid, s_last, s_ready, held8, ack8, x16_we, x16_set, held16;
    wire [5:0]         x16_addr, addr;
    wire               p, start, tile_go, w_wr, b_wr, tile_done, done, err, ovf;
    wire [3:0]         tile_id, cls_wr, cls, g, view_cls;
    wire signed [39:0] b;
    wire [2:0]         err_code;
    wire [419:0]       scores;
    wire               pe_wr, pe_run, pe_done, pe_err;
    wire [15:0]        pe_cycles, view;
    wire [249:0]       pe_scores;
    wire               cls_ok;

    p01_reset_sync rst (.clk(clk), .btnC(btnC), .resetn(resetn));

    uart_core #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) uart (
        .clk(clk), .resetn(resetn), .uart_rxd_i(uart_rxd), .uart_txd_o(uart_txd),
        .rx_out_data(rx_data), .rx_out_valid(rx_valid), .rx_out_ready(rx_ready),
        .tx_in_data(tx_data), .tx_in_valid(tx_valid), .tx_in_ready(tx_ready),
        .rx_framing_error_o(fe), .rx_overrun_o(ov));

    p04_console #(.STAGE(STAGE)) con (
        .clk(clk), .resetn(resetn),
        .rx_data_i(rx_data), .rx_valid_i(rx_valid), .rx_ready_o(rx_ready),
        .tx_data_o(tx_data), .tx_valid_o(tx_valid), .tx_ready_i(tx_ready),
        .q_valid_o(q_valid), .q_x_o(q_x), .q_done_i(q_done), .q8_i(q8), .q16_i(q16), .q_ov8_i(q_ov8), .q_ov16_i(q_ov16),
        .s_data_o(s_data), .s_valid_o(s_valid), .s_last_o(s_last), .s_ready_i(s_ready), .held8_i(held8), .ack8_o(ack8),
        .x16_we_o(x16_we), .x16_addr_o(x16_addr), .x16_data_o(x16_data), .x16_set_o(x16_set), .held16_i(held16),
        .p_o(p), .start_o(start), .tile_go_o(tile_go), .tile_id_o(tile_id), .w_wr_o(w_wr), .b_wr_o(b_wr),
        .class_o(cls_wr), .addr_o(addr), .w_o(w), .b_o(b), .tile_done_i(tile_done), .done_i(done),
        .error_i(err), .err_code_i(err_code), .ovf_i(ovf), .class_i(cls), .scores_i(scores),
        .g_o(g), .pe_wr_o(pe_wr), .pe_run_o(pe_run), .pe_done_i(pe_done), .pe_err_i(pe_err),
        .pe_cycles_i(pe_cycles), .pe_scores_i(pe_scores),
        .view_o(view), .cls_o(view_cls), .cls_ok_o(cls_ok));

    p04_bank #(.STAGE(STAGE)) bank (
        .clk(clk), .resetn(resetn),
        .q_valid_i(q_valid), .q_x_i(q_x), .q_done_o(q_done), .q8_o(q8), .q16_o(q16), .q_ov8_o(q_ov8), .q_ov16_o(q_ov16),
        .s_data_i(s_data), .s_valid_i(s_valid), .s_last_i(s_last), .s_ready_o(s_ready), .held8_o(held8), .ack8_i(ack8),
        .x16_we_i(x16_we), .x16_addr_i(x16_addr), .x16_data_i(x16_data), .x16_set_i(x16_set), .held16_o(held16),
        .p_i(p), .start_i(start), .tile_go_i(tile_go), .tile_id_i(tile_id), .w_wr_i(w_wr), .b_wr_i(b_wr),
        .class_i(cls_wr), .addr_i(addr), .w_i(w), .b_i(b), .tile_done_o(tile_done), .done_o(done),
        .error_o(err), .err_code_o(err_code), .ovf_o(ovf), .class_o(cls), .scores_o(scores),
        .g_i(g), .pe_wr_i(pe_wr), .pe_run_i(pe_run), .pe_done_o(pe_done), .pe_err_o(pe_err),
        .pe_cycles_o(pe_cycles), .pe_scores_o(pe_scores));

    p04_view #(.REFRESH_BITS(REFRESH_BITS)) view_out (
        .clk(clk), .resetn(resetn), .value_i(view), .class_i(view_cls), .class_ok_i(cls_ok),
        .held8_i(held8), .held16_i(held16), .led_o(led), .seg_o(seg), .an_o(an), .dp_o(dp));
endmodule
`default_nettype wire
