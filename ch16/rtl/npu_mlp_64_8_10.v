`timescale 1ns/1ps
`default_nettype none
// 16장 2층 신경망 64→8→10: 15장 Dense 두 개 + ReLU·정수 양자화(05장) + 은닉 버퍼 + argmax.
// 단계: L1(64→8) → QUANT(은닉 8개를 하나씩 ReLU·반올림 시프트·INT8 포화) → L2(8→10) → ARGMAX.
// 각 단계는 앞 단계의 done 펄스로 시작하고, 은닉값·점수는 단계 완료 펄스와 함께 밖에서 볼 수 있다.
module npu_mlp_64_8_10 #(
    parameter integer ACC_WIDTH = 32,
    parameter integer SHIFT = 10           // 은닉 = sat_int8(round(ReLU(점수) / 2^SHIFT))
) (
    input  wire                     clk,
    input  wire                     resetn,
    input  wire                     model_clear_i,
    input  wire                     w_layer_i,          // 0: 은닉층 64→8, 1: 출력층 8→10
    input  wire                     w_wr_en_i,
    input  wire               [3:0] w_neuron_i,
    input  wire               [5:0] w_addr_i,
    input  wire               [7:0] w_data_i,
    input  wire                     b_wr_en_i,
    input  wire               [3:0] b_neuron_i,
    input  wire     [ACC_WIDTH-1:0] b_data_i,
    output wire              [31:0] model_sum_o,        // 두 층 검증합의 합
    output wire                     model_err_o,
    output wire                     x_rd_en_o,
    output wire               [5:0] x_rd_idx_o,
    input  wire signed        [7:0] x_data_i,
    input  wire                     x_valid_i,
    input  wire                     start_i,
    output wire                     busy_o,
    output reg                      hidden_valid_o,     // 은닉 8개 확정 1클록 펄스
    output wire              [63:0] hidden_o,           // 은닉 h = [h*8 +: 8], INT8
    output reg                      hidden_sat_o,       // 이번 실행에서 은닉 포화가 있었음
    output wire [10*ACC_WIDTH-1:0]  scores_o,
    output reg                      done_o,
    output reg                      error_o,
    output wire               [3:0] class_o
);
    localparam IDLE=0, L1=1, QUANT=2, L2=3, ARGMAX=4;
    reg [2:0] state;
    reg [3:0] h_q;                                       // 양자화에 넣을 은닉 번호
    reg signed [7:0] hid_q [0:7];
    integer i;

    wire [31:0] sum1, sum2; wire err1, err2;
    assign model_sum_o = sum1 + sum2;
    assign model_err_o = err1 | err2;
    assign busy_o = (state != IDLE);

    // ── 은닉층 64→8
    wire l1_busy, l1_done, l1_err;
    wire [8*ACC_WIDTH-1:0] l1_scores;
    npu_dense #(.N_IN(64), .N_OUT(8), .ACC_WIDTH(ACC_WIDTH)) layer1 (
        .clk(clk), .resetn(resetn), .model_clear_i(model_clear_i),
        .w_wr_en_i(w_wr_en_i && !w_layer_i && !busy_o), .w_neuron_i(w_neuron_i), .w_addr_i(w_addr_i), .w_data_i(w_data_i),
        .b_wr_en_i(b_wr_en_i && !w_layer_i && !busy_o), .b_neuron_i(b_neuron_i), .b_data_i(b_data_i),
        .model_sum_o(sum1), .model_err_o(err1),
        .x_rd_en_o(x_rd_en_o), .x_rd_idx_o(x_rd_idx_o), .x_data_i(x_data_i), .x_valid_i(x_valid_i),
        .start_i(state == IDLE && start_i), .busy_o(l1_busy), .done_o(l1_done), .error_o(l1_err), .scores_o(l1_scores));

    // ── ReLU → 05장 양자화기 (반올림 0에서 먼 쪽, INT8 포화)
    wire signed [ACC_WIDTH-1:0] pick = l1_scores[h_q[2:0]*ACC_WIDTH +: ACC_WIDTH];
    wire signed [ACC_WIDTH-1:0] relu = pick[ACC_WIDTH-1] ? {ACC_WIDTH{1'b0}} : pick;
    wire signed [7:0] q; wire q_valid, q_ov;
    fixed_quantizer #(.IN_WIDTH(ACC_WIDTH), .OUT_WIDTH(8), .SHIFT(SHIFT), .ROUND(1), .SATURATE(1)) quant (
        .clk(clk), .resetn(resetn), .valid_i(state == QUANT && h_q < 8), .x_i(relu),
        .q_o(q), .valid_o(q_valid), .overflow_o(q_ov));
    reg [2:0] q_idx;                                     // 양자화기 출력(1클록 뒤)이 들어갈 칸

    // ── 출력층 8→10 (입력 = 은닉 버퍼, 1클록 지연 읽기)
    wire l2_x_en; wire [5:0] l2_x_idx; reg signed [7:0] l2_x; reg l2_xv;
    wire l2_busy, l2_done, l2_err;
    npu_dense #(.N_IN(8), .N_OUT(10), .ACC_WIDTH(ACC_WIDTH)) layer2 (
        .clk(clk), .resetn(resetn), .model_clear_i(model_clear_i),
        .w_wr_en_i(w_wr_en_i && w_layer_i && !busy_o), .w_neuron_i(w_neuron_i), .w_addr_i(w_addr_i), .w_data_i(w_data_i),
        .b_wr_en_i(b_wr_en_i && w_layer_i && !busy_o), .b_neuron_i(b_neuron_i), .b_data_i(b_data_i),
        .model_sum_o(sum2), .model_err_o(err2),
        .x_rd_en_o(l2_x_en), .x_rd_idx_o(l2_x_idx), .x_data_i(l2_x), .x_valid_i(l2_xv),
        .start_i(state == QUANT && h_q == 9), .busy_o(l2_busy), .done_o(l2_done), .error_o(l2_err), .scores_o(scores_o));
    always @(posedge clk) begin
        l2_xv <= resetn && l2_x_en;
        if (l2_x_en) l2_x <= hid_q[l2_x_idx[2:0]];
    end

    wire am_busy, am_done;
    npu_argmax #(.N(10), .W(ACC_WIDTH)) argmax (
        .clk(clk), .resetn(resetn), .start_i(l2_done), .scores_i(scores_o),
        .busy_o(am_busy), .done_o(am_done), .class_o(class_o));

    genvar g;
    generate for (g = 0; g < 8; g = g + 1) begin : h
        assign hidden_o[g*8 +: 8] = hid_q[g];
    end endgenerate

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE; h_q <= 0; q_idx <= 0; hidden_valid_o <= 0; hidden_sat_o <= 0; done_o <= 0; error_o <= 0;
            for (i = 0; i < 8; i = i + 1) hid_q[i] <= 0;
        end else begin
            hidden_valid_o <= 0; done_o <= 0; error_o <= 0;
            if (q_valid) begin
                hid_q[q_idx] <= q;
                if (q_ov) hidden_sat_o <= 1;
            end
            case (state)
                IDLE: if (start_i) begin state <= L1; hidden_sat_o <= 0; end
                L1: if (l1_err) begin state <= IDLE; error_o <= 1; end
                    else if (l1_done) begin state <= QUANT; h_q <= 0; end
                QUANT: begin                                  // h_q 0~7: 양자화기 입력, 8: 마지막 출력 저장, 9: L2 시작
                    q_idx <= h_q[2:0];
                    if (h_q == 8) hidden_valid_o <= 1;
                    if (h_q == 9) state <= L2;
                    else h_q <= h_q + 4'd1;
                end
                L2: if (l2_err) begin state <= IDLE; error_o <= 1; end
                    else if (l2_done) state <= ARGMAX;
                ARGMAX: if (am_done) begin state <= IDLE; done_o <= 1; end
                default: begin state <= IDLE; error_o <= 1; end
            endcase
        end
    end
endmodule
`default_nettype wire
