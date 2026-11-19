// 2장 NPU 경로 (2-7부터): 11장 명령 해석기 + 엔진 선택.
//   2-7 (STAGE 7): 엔진 = 누적 npu_core (p02_bank 엔진 포트). 점수는 Dense 결과(ReLU·16비트)를 41비트로 늘린 값.
//   2-8 (STAGE 8): 12장 npu_engine4를 더한다. sw[3] = 0 누적 core, 1 = 12장 엔진(원시 점수, ReLU 없음).
//                  두 엔진은 같은 쓰기·시작을 함께 받으므로 스위치를 바꿔도 다시 적재할 필요가 없다.
`timescale 1ns/1ps
`default_nettype none
module p02_npu_path #(
    parameter integer STAGE = 8
) (
    input  wire               clk,
    input  wire               resetn,
    input  wire               sel_engine4_i,     // 보드 sw[3] (비동기)
    // UART (p02_uart_switch의 11장 쪽)
    input  wire [7:0]         rx_data_i,
    input  wire               rx_valid_i,
    output wire               rx_ready_o,
    output wire [7:0]         tx_data_o,
    output wire               tx_valid_o,
    input  wire               tx_ready_i,
    output wire               protocol_error_o,
    // p02_bank 엔진 포트
    output wire               e_start_o,
    output wire [6:0]         e_length_o,
    output wire               e_x_wr_o,
    output wire               e_w_wr_o,
    output wire               e_b_wr_o,
    output wire [5:0]         e_addr_o,
    output wire [1:0]         e_neuron_o,
    output wire signed [15:0] e_data_o,
    output wire signed [39:0] e_bias_o,
    input  wire               e_load_ready_i,
    input  wire               e_busy_i,
    input  wire               e_done_i,
    input  wire               e_error_i,
    input  wire [1:0]         e_class_i,
    input  wire [163:0]       e_scores_i,
    // 표시용 (고른 엔진)
    output wire [1:0]         class_o,
    output wire               busy_o,
    output wire               done_o,
    output wire               error_o
);
    generate if (STAGE >= 7) begin : g_path
        reg [1:0] sync;
        always @(posedge clk) begin
            if (!resetn) sync <= 2'b00;
            else         sync <= {sync[0], sel_engine4_i};
        end
        wire use4 = (STAGE >= 8) && sync[1];

        wire               start, xwe, wwe, bwe, load_ready, busy, done, err;
        wire [6:0]         length;
        wire [5:0]         addr;
        wire [1:0]         neuron, cls;
        wire signed [15:0] data;
        wire signed [39:0] bias;
        wire [163:0]       scores;

        uart_npu_command_controller u_cmd (
            .clk(clk), .resetn(resetn),
            .rx_data_i(rx_data_i), .rx_valid_i(rx_valid_i), .rx_ready_o(rx_ready_o),
            .tx_data_o(tx_data_o), .tx_valid_o(tx_valid_o), .tx_ready_i(tx_ready_i),
            .npu_start_o(start), .npu_length_o(length),
            .x_wr_en_o(xwe), .w_wr_en_o(wwe), .b_wr_en_o(bwe),
            .wr_addr_o(addr), .neuron_o(neuron), .wr_data_o(data), .bias_data_o(bias),
            .npu_load_ready_i(load_ready), .npu_busy_i(busy), .npu_done_i(done), .npu_error_i(err),
            .npu_class_i(cls), .npu_scores_i(scores), .protocol_error_o(protocol_error_o));

        assign e_start_o = start;  assign e_length_o = length;
        assign e_x_wr_o  = xwe;    assign e_w_wr_o   = wwe;    assign e_b_wr_o = bwe;
        assign e_addr_o  = addr;   assign e_neuron_o = neuron;
        assign e_data_o  = data;   assign e_bias_o   = bias;

        wire         r4, b4, d4, x4;
        wire [1:0]   c4;
        wire [163:0] s4;
        if (STAGE >= 8) begin : g_e4
            npu_engine4 u_e4 (
                .clk(clk), .resetn(resetn), .start_i(start), .length_i(length),
                .x_wr_en(xwe), .w_wr_en(wwe), .b_wr_en(bwe), .addr_i(addr), .neuron_i(neuron),
                .data_i(data), .bias_i(bias), .load_ready_o(r4), .busy_o(b4), .done_o(d4),
                .error_o(x4), .class_o(c4), .scores_o(s4));
        end else begin : g_no_e4
            assign r4 = 1'b1; assign b4 = 1'b0; assign d4 = 1'b0; assign x4 = 1'b0;
            assign c4 = 2'd0; assign s4 = 164'd0;
        end

        // 쓰기는 두 엔진이 모두 받을 수 있을 때만 (11장 해석기는 load_ready를 보고 쓴다)
        assign load_ready = e_load_ready_i && r4;
        assign busy   = use4 ? b4 : e_busy_i;
        assign done   = use4 ? d4 : e_done_i;
        assign err    = use4 ? x4 : e_error_i;
        assign cls    = use4 ? c4 : e_class_i;
        assign scores = use4 ? s4 : e_scores_i;

        reg [1:0] cls_q;                          // 표시: 마지막으로 끝난 실행의 클래스
        always @(posedge clk) begin
            if (!resetn)  cls_q <= 2'd0;
            else if (done) cls_q <= cls;
        end
        assign class_o = cls_q;
        assign busy_o  = busy;
        assign done_o  = done;
        assign error_o = err;
    end else begin : g_no_path
        assign rx_ready_o = 1'b0; assign tx_data_o = 8'd0; assign tx_valid_o = 1'b0; assign protocol_error_o = 1'b0;
        assign e_start_o = 1'b0; assign e_length_o = 7'd0; assign e_x_wr_o = 1'b0; assign e_w_wr_o = 1'b0;
        assign e_b_wr_o = 1'b0; assign e_addr_o = 6'd0; assign e_neuron_o = 2'd0; assign e_data_o = 16'sd0;
        assign e_bias_o = 40'sd0; assign class_o = 2'd0; assign busy_o = 1'b0; assign done_o = 1'b0; assign error_o = 1'b0;
    end endgenerate
endmodule
`default_nettype wire
