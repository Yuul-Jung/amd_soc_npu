`timescale 1ns/1ps
// (추가) 14장: 4PE를 3그룹(4+4+2)으로 재사용하는 64입력·10분류 정수 Dense 코어.
// class = 4*group + lane. group 2의 lane 2·3은 무효이므로 valid를 막아 누산하지 않고 점수에도 쓰지 않는다.
// x는 13장 p3_frame64_buffer 읽기 포트(1클록 지연)에서 읽는다.
// 가중치는 lane별 bank(bank l = class l, l+4, l+8)에 저장해 매 클록 4개를 병렬로 읽는다.
// score[c] = sum_i x[i]*W[c][i] + bias[c] (signed 25비트, 정수 기준모델 linear_64x10과 동일)
// class_o = 최대 점수 class, 동점이면 낮은 번호(argmax_lowest)
// (변경) 15장 Dense 계층 재사용을 위해 입력 길이·출력 수를 파라미터로 둔다. 기본값 64→10이 14장 동작이다.
// (변경) 18장 정밀도 비교를 위해 데이터·누산·Bias·점수 폭을 파라미터로 둔다.
//   기본값 DATA_W 8 / ACC_W 24 / BIAS_W 24 / SCORE_W 25가 14장 INT8 동작이다.
//   INT16 예: DATA_W 16 / ACC_W 38(64항 최악 2^36) / SCORE_W ≥ max(ACC_W, BIAS_W) + 1.
module p3_group10_core #(
    parameter integer IN_LEN = 64,
    parameter integer OUT_N = 10,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 24,
    parameter integer BIAS_W = 24,
    parameter integer SCORE_W = 25
)(
    input wire clk,
    input wire resetn,
    input wire start_i,
    input wire x_valid_i,
    output wire x_rd_en_o,
    output wire [5:0] x_rd_addr_o,
    input wire signed [DATA_W-1:0] x_rd_data_i,
    input wire w_wr_en_i,
    input wire b_wr_en_i,
    input wire [3:0] wr_class_i,
    input wire [5:0] wr_addr_i,
    input wire signed [DATA_W-1:0] w_data_i,
    input wire signed [BIAS_W-1:0] b_data_i,
    output wire load_ready_o,
    output reg busy_o,
    output reg done_o,
    output reg error_o,
    output reg [3:0] class_o,
    output wire [OUT_N*SCORE_W-1:0] scores_o
);
    localparam [2:0] IDLE=3'd0, CLEAR=3'd1, RUN=3'd2, DRAIN=3'd3, CAPT=3'd4, FINISH=3'd5;
    reg [2:0] state;
    reg [1:0] group_q;
    reg [5:0] idx_q;
    reg drain_q;
    reg issue_q;

    // lane별 가중치 bank: 주소 = group*64 + index
    reg signed [DATA_W-1:0] bank0 [0:191];
    reg signed [DATA_W-1:0] bank1 [0:191];
    reg signed [DATA_W-1:0] bank2 [0:191];
    reg signed [DATA_W-1:0] bank3 [0:191];
    reg signed [DATA_W-1:0] w_q0, w_q1, w_q2, w_q3;
    reg signed [BIAS_W-1:0] bias [0:OUT_N-1];
    reg signed [SCORE_W-1:0] score_q [0:OUT_N-1];
    // (변경) 마지막 그룹 번호: 출력 수를 4개 차선으로 나눈 그룹 수 - 1
    localparam [1:0] LAST_GROUP = (OUT_N - 1) / 4;

    assign load_ready_o = resetn && !busy_o;
    assign x_rd_en_o = (state == RUN);
    assign x_rd_addr_o = idx_q;

    // (변경) class = 4*group + lane < OUT_N 인 차선만 유효(10분류: group 2는 lane 0·1만)
    wire [3:0] lane_en = {({group_q, 2'd3} < OUT_N), ({group_q, 2'd2} < OUT_N),
                          ({group_q, 2'd1} < OUT_N), ({group_q, 2'd0} < OUT_N)};
    wire lane_clear = (state == CLEAR);
    wire signed [ACC_W-1:0] acc0, acc1, acc2, acc3;
    npu_dsp_mac_lane #(.DATA_WIDTH(DATA_W), .ACC_WIDTH(ACC_W)) lane0(.clk(clk), .resetn(resetn),
        .clear_i(lane_clear), .valid_i(issue_q && lane_en[0]),
        .x_i(x_rd_data_i), .w_i(w_q0), .acc_o(acc0));
    npu_dsp_mac_lane #(.DATA_WIDTH(DATA_W), .ACC_WIDTH(ACC_W)) lane1(.clk(clk), .resetn(resetn),
        .clear_i(lane_clear), .valid_i(issue_q && lane_en[1]),
        .x_i(x_rd_data_i), .w_i(w_q1), .acc_o(acc1));
    npu_dsp_mac_lane #(.DATA_WIDTH(DATA_W), .ACC_WIDTH(ACC_W)) lane2(.clk(clk), .resetn(resetn),
        .clear_i(lane_clear), .valid_i(issue_q && lane_en[2]),
        .x_i(x_rd_data_i), .w_i(w_q2), .acc_o(acc2));
    npu_dsp_mac_lane #(.DATA_WIDTH(DATA_W), .ACC_WIDTH(ACC_W)) lane3(.clk(clk), .resetn(resetn),
        .clear_i(lane_clear), .valid_i(issue_q && lane_en[3]),
        .x_i(x_rd_data_i), .w_i(w_q3), .acc_o(acc3));

    // 쓰기 수락: Busy가 아니고 class 0..9일 때만
    wire wr_any = w_wr_en_i || b_wr_en_i;
    wire wr_ok = load_ready_o && (wr_class_i < OUT_N);
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

    // (변경) 19장 타이밍 결함 수정: 10개 점수를 한 클록에 직렬 비교(9단)하던 argmax를 누적형으로 바꾼다.
    //   CAPT에서 lane 쌍(0·1, 2·3)의 승자를 레지스터에 저장하고(1단), 다음 CLEAR에서 두 승자와
    //   누적 최대값(best_s_q)을 비교해 합친다(2단). 마지막 그룹은 FINISH에서 합친다.
    //   class_o·done 시점과 동점 규칙(낮은 번호)은 그대로.
    integer k;
    reg have_best_q;
    reg [3:0] best_c_q;
    reg signed [SCORE_W-1:0] best_s_q;
    reg signed [SCORE_W-1:0] s01, s23;   // 직전 CAPT 그룹의 lane 쌍 승자
    reg [3:0] c01, c23;
    reg v23_q;                           // lane 2 유효(lane 0은 항상 유효)
    // lane 쌍 비교(CAPT): 높은 번호는 엄격히 클 때만 이긴다(동점 = 낮은 번호)
    wire signed [SCORE_W-1:0] ns0 = add_bias(acc0, bias[{group_q, 2'd0}]);
    wire signed [SCORE_W-1:0] ns1 = add_bias(acc1, bias[{group_q, 2'd1}]);
    wire signed [SCORE_W-1:0] ns2 = add_bias(acc2, bias[{group_q, 2'd2}]);
    wire signed [SCORE_W-1:0] ns3 = add_bias(acc3, bias[{group_q, 2'd3}]);
    wire take1 = lane_en[1] && (ns1 > ns0);
    wire take3 = lane_en[3] && (ns3 > ns2);
    wire take23 = v23_q && (s23 > s01);
    wire signed [SCORE_W-1:0] grp_s = take23 ? s23 : s01;
    wire [3:0] grp_c = take23 ? c23 : c01;
    // 누적값은 앞 그룹(낮은 번호)이므로 그룹 최대가 엄격히 클 때만 바꾼다
    wire take_grp = !have_best_q || (grp_s > best_s_q);
    wire [3:0] best_class = take_grp ? grp_c : best_c_q;

    genvar g;
    generate
        for (g = 0; g < OUT_N; g = g + 1) begin : pack
            assign scores_o[g*SCORE_W +: SCORE_W] = score_q[g];
        end
    endgenerate

    // 누산값(ACC_W)과 Bias(BIAS_W)를 SCORE_W로 부호 확장해 더한다(기본 24+24 → 25비트).
    function signed [SCORE_W-1:0] add_bias(input signed [ACC_W-1:0] acc, input signed [BIAS_W-1:0] b);
        add_bias = acc + b;
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
            for (k = 0; k < OUT_N; k = k + 1) begin
                bias[k] <= {BIAS_W{1'b0}};
                score_q[k] <= {SCORE_W{1'b0}};
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
                        have_best_q <= 1'b0;
                        state <= CLEAR;
                    end
                end
                CLEAR: begin
                    // 직전 그룹(group_q - 1) 점수를 누적 최대값에 합친다
                    if (group_q != 2'd0) begin
                        have_best_q <= 1'b1;
                        if (take_grp) begin
                            best_s_q <= grp_s;
                            best_c_q <= grp_c;
                        end
                    end
                    idx_q <= 6'd0;
                    state <= RUN;
                end
                RUN: begin
                    if (idx_q == IN_LEN - 1) begin
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
                    // argmax 1단: lane 쌍 승자. 무효 lane은 lane_en으로 제외되므로 값은 상관없다
                    s01 <= take1 ? ns1 : ns0;
                    c01 <= take1 ? {group_q, 2'd1} : {group_q, 2'd0};
                    s23 <= take3 ? ns3 : ns2;
                    c23 <= take3 ? {group_q, 2'd3} : {group_q, 2'd2};
                    v23_q <= lane_en[2];
                    if (group_q == LAST_GROUP) begin
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
    // synthesis translate_off
    initial begin
        if (IN_LEN < 1 || IN_LEN > 64 || OUT_N < 1 || OUT_N > 12)
            $fatal(1, "Require 1<=IN_LEN<=64 and 1<=OUT_N<=12");
        if (SCORE_W < ((ACC_W > BIAS_W) ? ACC_W : BIAS_W) + 1)
            $fatal(1, "Require SCORE_W >= max(ACC_W, BIAS_W) + 1");
    end
    // synthesis translate_on
endmodule
