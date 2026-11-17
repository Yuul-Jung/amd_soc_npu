`timescale 1ns/1ps
// (추가) 14장: 4PE를 3그룹(4+4+2)으로 재사용하는 64입력·10분류 정수 Dense 코어.
// class = 4*group + lane. group 2의 lane 2·3은 무효이므로 valid를 막아 누산하지 않고 점수에도 쓰지 않는다.
// x는 13장 p3_frame64_buffer 읽기 포트(1클록 지연)에서 읽는다.
// 가중치는 lane별 bank(bank l = class l, l+4, l+8)에 저장해 매 클록 4개를 병렬로 읽는다.
// score[c] = sum_i x[i]*W[c][i] + bias[c] (signed 25비트, 정수 기준모델 linear_64x10과 동일)
// class_o = 최대 점수 class, 동점이면 낮은 번호(argmax_lowest)
module p3_group10_core(
    input wire clk,
    input wire resetn,
    input wire start_i,
    input wire x_valid_i,
    output wire x_rd_en_o,
    output wire [5:0] x_rd_addr_o,
    input wire signed [7:0] x_rd_data_i,
    input wire w_wr_en_i,
    input wire b_wr_en_i,
    input wire [3:0] wr_class_i,
    input wire [5:0] wr_addr_i,
    input wire signed [7:0] w_data_i,
    input wire signed [23:0] b_data_i,
    output wire load_ready_o,
    output reg busy_o,
    output reg done_o,
    output reg error_o,
    output reg [3:0] class_o,
    output wire [249:0] scores_o
);
    localparam [2:0] IDLE=3'd0, CLEAR=3'd1, RUN=3'd2, DRAIN=3'd3, CAPT=3'd4, FINISH=3'd5;
    reg [2:0] state;
    reg [1:0] group_q;
    reg [5:0] idx_q;
    reg drain_q;
    reg issue_q;

    // lane별 가중치 bank: 주소 = group*64 + index
    reg signed [7:0] bank0 [0:191];
    reg signed [7:0] bank1 [0:191];
    reg signed [7:0] bank2 [0:191];
    reg signed [7:0] bank3 [0:191];
    reg signed [7:0] w_q0, w_q1, w_q2, w_q3;
    reg signed [23:0] bias [0:9];
    reg signed [24:0] score_q [0:9];

    assign load_ready_o = resetn && !busy_o;
    assign x_rd_en_o = (state == RUN);
    assign x_rd_addr_o = idx_q;

    // group 2(class 8,9)에서는 lane 0·1만 유효
    wire [3:0] lane_en = (group_q == 2'd2) ? 4'b0011 : 4'b1111;
    wire lane_clear = (state == CLEAR);
    wire signed [23:0] acc0, acc1, acc2, acc3;
    npu_dsp_mac_lane #(.DATA_WIDTH(8), .ACC_WIDTH(24)) lane0(.clk(clk), .resetn(resetn),
        .clear_i(lane_clear), .valid_i(issue_q && lane_en[0]),
        .x_i(x_rd_data_i), .w_i(w_q0), .acc_o(acc0));
    npu_dsp_mac_lane #(.DATA_WIDTH(8), .ACC_WIDTH(24)) lane1(.clk(clk), .resetn(resetn),
        .clear_i(lane_clear), .valid_i(issue_q && lane_en[1]),
        .x_i(x_rd_data_i), .w_i(w_q1), .acc_o(acc1));
    npu_dsp_mac_lane #(.DATA_WIDTH(8), .ACC_WIDTH(24)) lane2(.clk(clk), .resetn(resetn),
        .clear_i(lane_clear), .valid_i(issue_q && lane_en[2]),
        .x_i(x_rd_data_i), .w_i(w_q2), .acc_o(acc2));
    npu_dsp_mac_lane #(.DATA_WIDTH(8), .ACC_WIDTH(24)) lane3(.clk(clk), .resetn(resetn),
        .clear_i(lane_clear), .valid_i(issue_q && lane_en[3]),
        .x_i(x_rd_data_i), .w_i(w_q3), .acc_o(acc3));

    // 쓰기 수락: Busy가 아니고 class 0..9일 때만
    wire wr_any = w_wr_en_i || b_wr_en_i;
    wire wr_ok = load_ready_o && (wr_class_i < 4'd10);
    wire [7:0] wr_bank_addr = {wr_class_i[3:2], wr_addr_i};
    wire [7:0] rd_bank_addr = {group_q, idx_q};

    // 가중치 bank: Reset 없는 동기 쓰기·동기 읽기(BRAM 추론 후보, 실제 매핑은 합성으로 확인)
    always @(posedge clk) begin
        if (w_wr_en_i && wr_ok) begin
            case (wr_class_i[1:0])
                2'd0: bank0[wr_bank_addr] <= w_data_i;
                2'd1: bank1[wr_bank_addr] <= w_data_i;
                2'd2: bank2[wr_bank_addr] <= w_data_i;
                2'd3: bank3[wr_bank_addr] <= w_data_i;
            endcase
        end
        if (state == RUN) begin
            w_q0 <= bank0[rd_bank_addr];
            w_q1 <= bank1[rd_bank_addr];
            w_q2 <= bank2[rd_bank_addr];
            w_q3 <= bank3[rd_bank_addr];
        end
    end

    // 10개 점수 중 최대값, 동점은 낮은 번호 유지(엄격한 > 비교)
    integer k;
    reg [3:0] best_class;
    reg signed [24:0] best_score;
    always @* begin
        best_class = 4'd0;
        best_score = score_q[0];
        for (k = 1; k < 10; k = k + 1)
            if (score_q[k] > best_score) begin
                best_score = score_q[k];
                best_class = k[3:0];
            end
    end

    genvar g;
    generate
        for (g = 0; g < 10; g = g + 1) begin : pack
            assign scores_o[g*25 +: 25] = score_q[g];
        end
    endgenerate

    // 누산값(24비트)과 Bias(24비트)를 25비트로 부호 확장해 더한다.
    function signed [24:0] add_bias(input signed [23:0] acc, input signed [23:0] b);
        add_bias = $signed({acc[23], acc}) + $signed({b[23], b});
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            group_q <= 2'd0;
            idx_q <= 6'd0;
            drain_q <= 1'b0;
            issue_q <= 1'b0;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            class_o <= 4'd0;
            for (k = 0; k < 10; k = k + 1) begin
                bias[k] <= 24'sd0;
                score_q[k] <= 25'sd0;
            end
        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;
            issue_q <= (state == RUN);
            // Busy 중 쓰기, 범위 밖 class 쓰기는 무시하고 오류 펄스
            if (wr_any && !wr_ok)
                error_o <= 1'b1;
            if (b_wr_en_i && wr_ok)
                bias[wr_class_i] <= b_data_i;
            case (state)
                IDLE: if (start_i) begin
                    if (!x_valid_i || wr_any) begin
                        error_o <= 1'b1;
                    end else begin
                        busy_o <= 1'b1;
                        group_q <= 2'd0;
                        state <= CLEAR;
                    end
                end
                CLEAR: begin
                    idx_q <= 6'd0;
                    state <= RUN;
                end
                RUN: begin
                    if (idx_q == 6'd63) begin
                        drain_q <= 1'b0;
                        state <= DRAIN;
                    end
                    idx_q <= idx_q + 6'd1;
                end
                // 마지막 곱: issue_q 다음 에지에서 DSP 등록, 그다음 에지에서 누산 완료
                DRAIN: begin
                    drain_q <= 1'b1;
                    if (drain_q)
                        state <= CAPT;
                end
                CAPT: begin
                    if (lane_en[0]) score_q[{group_q, 2'd0}] <= add_bias(acc0, bias[{group_q, 2'd0}]);
                    if (lane_en[1]) score_q[{group_q, 2'd1}] <= add_bias(acc1, bias[{group_q, 2'd1}]);
                    if (lane_en[2]) score_q[{group_q, 2'd2}] <= add_bias(acc2, bias[{group_q, 2'd2}]);
                    if (lane_en[3]) score_q[{group_q, 2'd3}] <= add_bias(acc3, bias[{group_q, 2'd3}]);
                    if (group_q == 2'd2) begin
                        state <= FINISH;
                    end else begin
                        group_q <= group_q + 2'd1;
                        state <= CLEAR;
                    end
                end
                FINISH: begin
                    class_o <= best_class;
                    done_o <= 1'b1;
                    busy_o <= 1'b0;
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                    busy_o <= 1'b0;
                end
            endcase
            // Busy 중 start는 무시하고 오류 표시
            if (start_i && state != IDLE)
                error_o <= 1'b1;
        end
    end
endmodule
