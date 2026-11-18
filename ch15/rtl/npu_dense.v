`timescale 1ns/1ps
`default_nettype none
// 15장 Dense 층 N_IN→N_OUT: 모델 저장소 + 연산 코어 + Bias 더하기(1클록).
// 입력 x는 바깥 메모리에서 읽는다 (16장: 은닉 버퍼, 13장: 입력 적재기).
module npu_dense #(
    parameter integer N_IN = 64,
    parameter integer N_OUT = 10,
    parameter integer ACC_WIDTH = 32
) (
    input  wire                        clk,
    input  wire                        resetn,
    input  wire                        model_clear_i,
    input  wire                        w_wr_en_i,
    input  wire                  [3:0] w_neuron_i,
    input  wire                  [5:0] w_addr_i,
    input  wire                  [7:0] w_data_i,
    input  wire                        b_wr_en_i,
    input  wire                  [3:0] b_neuron_i,
    input  wire        [ACC_WIDTH-1:0] b_data_i,
    output wire                 [31:0] model_sum_o,
    output wire                        model_err_o,
    output wire                        x_rd_en_o,
    output wire                  [5:0] x_rd_idx_o,
    input  wire signed           [7:0] x_data_i,
    input  wire                        x_valid_i,
    input  wire                        start_i,
    output wire                        busy_o,
    output reg                         done_o,
    output wire                        error_o,
    output reg  [N_OUT*ACC_WIDTH-1:0]  scores_o
);
    localparam [6:0] LEN = N_IN;          // 이 층은 늘 N_IN개 전체를 쓴다 (17장 타일은 코어 len_i를 직접 바꾼다)
    wire w_rd_en; wire [1:0] w_rd_group; wire [5:0] w_rd_idx;
    wire [31:0] w_data; wire [3:0] w_valid;
    wire [N_OUT*ACC_WIDTH-1:0] bias, dots;
    wire core_busy, core_done;
    reg  add_q;                            // 코어 완료 후 Bias 더하는 1클록
    integer i;

    assign busy_o = core_busy || add_q;

    npu_dense_store #(.N_IN(N_IN), .N_OUT(N_OUT), .ACC_WIDTH(ACC_WIDTH)) store (
        .clk(clk), .resetn(resetn), .clear_i(model_clear_i), .wr_lock_i(busy_o),
        .w_wr_en_i(w_wr_en_i), .w_neuron_i(w_neuron_i), .w_addr_i(w_addr_i), .w_data_i(w_data_i),
        .b_wr_en_i(b_wr_en_i), .b_neuron_i(b_neuron_i), .b_data_i(b_data_i),
        .w_rd_en_i(w_rd_en), .w_rd_group_i(w_rd_group), .w_rd_idx_i(w_rd_idx),
        .w_data_o(w_data), .w_valid_o(w_valid), .bias_o(bias), .sum_o(model_sum_o), .wr_err_o(model_err_o));

    npu_dense_core #(.N_OUT(N_OUT), .ACC_WIDTH(ACC_WIDTH)) core (
        .clk(clk), .resetn(resetn), .start_i(start_i && !busy_o), .len_i(LEN),
        .x_rd_en_o(x_rd_en_o), .x_rd_idx_o(x_rd_idx_o), .x_data_i(x_data_i), .x_valid_i(x_valid_i),
        .w_rd_en_o(w_rd_en), .w_rd_group_o(w_rd_group), .w_rd_idx_o(w_rd_idx), .w_data_i(w_data), .w_valid_i(w_valid),
        .busy_o(core_busy), .done_o(core_done), .error_o(error_o), .dots_o(dots));

    always @(posedge clk) begin
        if (!resetn) begin
            add_q <= 0; done_o <= 0; scores_o <= 0;
        end else begin
            add_q <= core_done; done_o <= add_q;
            if (core_done)
                for (i = 0; i < N_OUT; i = i + 1)
                    scores_o[i*ACC_WIDTH +: ACC_WIDTH] <= $signed(dots[i*ACC_WIDTH +: ACC_WIDTH]) + $signed(bias[i*ACC_WIDTH +: ACC_WIDTH]);
        end
    end
endmodule
`default_nettype wire
