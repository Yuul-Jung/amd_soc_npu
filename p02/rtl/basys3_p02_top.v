// 2장 보드 Top: 4뉴런 NPU 보드. 인스턴스와 배선만 둔다 (기능은 하위 모듈).
//   2-1~2-6: 디버그 콘솔로 BRAM → 양자화 → 내적 → 4PE → Dense → Core를 UART 명령 하나씩 확인
//   2-7: sw[2] = 1이면 명령 해석기가 UART를 맡고 누적 npu_core로 추론 ("Ck:…")
//   2-8: sw[3] = 1이면 npu_engine4로 추론, LED·7세그먼트에 클래스 표시
// STAGE = 끝낸 서브젝트 수 (1~8). 서브젝트마다 그 단계 비트스트림으로 보드에서 확인한다.
`timescale 1ns/1ps
`default_nettype none
module basys3_p02_top #(
    parameter integer CLK_HZ       = 100000000,
    parameter integer BAUD         = 115200,
    parameter integer REFRESH_BITS = 18,
    parameter integer STAGE        = 8
) (
    input  wire        clk,
    input  wire        btnC,
    input  wire        uart_rxd,
    input  wire [3:2]  sw,
    output wire        uart_txd,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp
);
    wire               resetn, fe, ov, owner_engine, proto_err;
    wire [7:0]         rx_data, tx_data, c_tx_data, e_tx_data;
    wire               rx_valid, rx_ready, tx_valid, tx_ready;
    wire               c_rx_valid, c_rx_ready, c_tx_valid, c_tx_ready;
    wire               e_rx_valid, e_rx_ready, e_tx_valid, e_tx_ready;
    wire [3:0]         op, flags;
    wire               op_valid, op_done, op_error;
    wire [5:0]         addr, e_addr;
    wire [1:0]         neuron, e_neuron, e_class, cls;
    wire signed [15:0] data, e_data;
    wire signed [39:0] bias, e_bias;
    wire signed [31:0] qin;
    wire [6:0]         len, e_length;
    wire [159:0]       res;
    wire [15:0]        view;
    wire               e_start, e_xwr, e_wwr, e_bwr, e_load_ready, e_busy, e_done, e_error;
    wire [163:0]       e_scores;
    wire               n_busy, n_done, n_error;

    p01_reset_sync rst (.clk(clk), .btnC(btnC), .resetn(resetn));

    uart_core #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) uart (
        .clk(clk), .resetn(resetn), .uart_rxd_i(uart_rxd), .uart_txd_o(uart_txd),
        .rx_out_data(rx_data), .rx_out_valid(rx_valid), .rx_out_ready(rx_ready),
        .tx_in_data(tx_data), .tx_in_valid(tx_valid), .tx_in_ready(tx_ready),
        .rx_framing_error_o(fe), .rx_overrun_o(ov));

    p02_uart_switch #(.STAGE(STAGE)) usw (
        .clk(clk), .resetn(resetn), .sw_i(sw[2]), .owner_engine_o(owner_engine),
        .rx_data_i(rx_data), .rx_valid_i(rx_valid), .rx_ready_o(rx_ready),
        .tx_data_o(tx_data), .tx_valid_o(tx_valid), .tx_ready_i(tx_ready),
        .c_rx_valid_o(c_rx_valid), .c_rx_ready_i(c_rx_ready), .c_tx_data_i(c_tx_data),
        .c_tx_valid_i(c_tx_valid), .c_tx_ready_o(c_tx_ready),
        .e_rx_valid_o(e_rx_valid), .e_rx_ready_i(e_rx_ready), .e_tx_data_i(e_tx_data),
        .e_tx_valid_i(e_tx_valid), .e_tx_ready_o(e_tx_ready));

    p02_console #(.STAGE(STAGE)) con (
        .clk(clk), .resetn(resetn),
        .rx_data_i(rx_data), .rx_valid_i(c_rx_valid), .rx_ready_o(c_rx_ready),
        .tx_data_o(c_tx_data), .tx_valid_o(c_tx_valid), .tx_ready_i(c_tx_ready),
        .op_o(op), .op_valid_o(op_valid), .addr_o(addr), .neuron_o(neuron), .data_o(data),
        .bias_o(bias), .qin_o(qin), .len_o(len), .op_done_i(op_done), .op_error_i(op_error),
        .res_i(res), .flags_i(flags), .view_o(view));

    p02_bank #(.STAGE(STAGE)) bank (
        .clk(clk), .resetn(resetn),
        .op_i(op), .op_valid_i(op_valid), .addr_i(addr), .neuron_i(neuron), .data_i(data),
        .bias_i(bias), .qin_i(qin), .len_i(len), .op_done_o(op_done), .op_error_o(op_error),
        .res_o(res), .flags_o(flags),
        .owner_engine_i(owner_engine), .e_start_i(e_start), .e_length_i(e_length),
        .e_x_wr_i(e_xwr), .e_w_wr_i(e_wwr), .e_b_wr_i(e_bwr), .e_addr_i(e_addr), .e_neuron_i(e_neuron),
        .e_data_i(e_data), .e_bias_i(e_bias), .e_load_ready_o(e_load_ready), .e_busy_o(e_busy),
        .e_done_o(e_done), .e_error_o(e_error), .e_class_o(e_class), .e_scores_o(e_scores));

    p02_npu_path #(.STAGE(STAGE)) npu (
        .clk(clk), .resetn(resetn), .sel_engine4_i(sw[3]),
        .rx_data_i(rx_data), .rx_valid_i(e_rx_valid), .rx_ready_o(e_rx_ready),
        .tx_data_o(e_tx_data), .tx_valid_o(e_tx_valid), .tx_ready_i(e_tx_ready),
        .protocol_error_o(proto_err),
        .e_start_o(e_start), .e_length_o(e_length), .e_x_wr_o(e_xwr), .e_w_wr_o(e_wwr), .e_b_wr_o(e_bwr),
        .e_addr_o(e_addr), .e_neuron_o(e_neuron), .e_data_o(e_data), .e_bias_o(e_bias),
        .e_load_ready_i(e_load_ready), .e_busy_i(e_busy), .e_done_i(e_done), .e_error_i(e_error),
        .e_class_i(e_class), .e_scores_i(e_scores),
        .class_o(cls), .busy_o(n_busy), .done_o(n_done), .error_o(n_error));

    p02_view #(.STAGE(STAGE), .REFRESH_BITS(REFRESH_BITS)) view_out (
        .clk(clk), .resetn(resetn), .value_i(view), .class_i(cls), .busy_i(n_busy), .done_i(n_done),
        .error_i(n_error), .protocol_error_i(proto_err), .uart_framing_error_i(fe), .uart_overrun_i(ov),
        .led_o(led), .seg_o(seg), .an_o(an), .dp_o(dp));
endmodule
`default_nettype wire
