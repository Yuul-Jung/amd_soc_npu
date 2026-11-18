`timescale 1ns/1ps
// (추가) 17장: 784입력(28×28)·10분류를 64원소 타일 13개(64×12 + 16)로 나눠 계산하는 Tile Controller.
// 14장 p3_group10_core(64→10, 4PE 4+4+2 그룹)를 변경 없이 타일마다 한 번 실행한다.
// 코어는 그룹마다 내부 누산기를 지우므로, 타일 결과(부분합)를 클래스별 외부 누산기 acc[c]에 더한다.
//   score[c] = sum_t part[t][c] + bias[c]
// Bias 중복 방지: 코어 Bias 쓰기 포트를 0으로 고정 → 코어 Bias는 Reset 값 0 유지 → 코어 점수 = 순수 부분합.
//   실제 Bias는 외부 레지스터에 두고 13타일 누산이 끝난 뒤 클래스별 1회만 더한다.
// 마지막 타일(12)은 16원소만 유효. 코어는 IN_LEN=64로 64클록을 돌므로 주소 16~63의 x를 0으로 가려
//   프레임 버퍼 잔여값과 이전 타일 가중치가 누산에 들어가지 않게 한다.
// 순서: start → [W 적재 + x 프레임 + tile_go(t)] × 13 → done.
//   W 쓰기는 IDLE·LOAD에서만 받는다. 다음 타일 프레임은 이전 타일의 4+4+2 그룹 계산과
//   결과 수락(외부 누산, frame_ack)이 끝나야 프레임 버퍼가 비워져 들어올 수 있다.
module p3_tile784_10 #(
    parameter integer ACC_W = 41,   // 외부 누산 폭. INT16 784항 최악 841,813,590,016 → signed 41
    parameter integer BIAS_W = 40,  // 외부 Bias 폭
    parameter integer SCORE_W = 42  // 최종 점수 폭 ≥ max(ACC_W, BIAS_W) + 1
)(
    input wire clk,
    input wire resetn,
    input wire start_i,                 // 784 추론 시작: 외부 누산기 Clear, 타일 0 대기
    input wire abort_i,                 // LOAD 중 취소: 보관 프레임 해제 후 IDLE
    input wire tile_go_i,               // 현재 프레임·가중치로 타일 tile_id_i 실행
    input wire [3:0] tile_id_i,
    input wire x_valid_i,               // 13장 프레임 버퍼 frame_valid
    output wire x_rd_en_o,
    output wire [5:0] x_rd_addr_o,
    input wire signed [7:0] x_rd_data_i,
    output wire frame_ack_o,
    input wire w_wr_en_i,
    input wire b_wr_en_i,
    input wire [3:0] wr_class_i,
    input wire [5:0] wr_addr_i,
    input wire signed [7:0] w_data_i,
    input wire signed [BIAS_W-1:0] b_data_i,
    output wire load_ready_o,           // W 쓰기 가능(IDLE·LOAD)
    output reg busy_o,
    output reg done_o,
    output reg error_o,
    output reg [2:0] err_code_o,        // 마지막 오류 원인
    output reg ovf_o,                   // 외부 누산 overflow(이번 추론 동안 유지)
    output wire [3:0] tile_idx_o,
    output reg tile_done_o,             // 타일 결과 수락 1클록. 이때 part_scores_o = 해당 타일 부분합
    output wire [10*25-1:0] part_scores_o,
    output reg [3:0] class_o,
    output wire [10*SCORE_W-1:0] scores_o
);
    localparam integer N_CLASS = 10;
    localparam integer PART_W = 25;
    localparam [3:0] LAST_TILE = 4'd12;
    localparam [5:0] LAST_LEN = 6'd16;
    localparam integer SUM_W = ((ACC_W > PART_W) ? ACC_W : PART_W) + 1;
    localparam [2:0] IDLE=3'd0, LOAD=3'd1, RUN=3'd2, ACK=3'd3, SCORE=3'd4, FINISH=3'd5, DROP=3'd6;
    localparam [2:0] ERR_STATE=3'd1, ERR_TILE_DUP=3'd2, ERR_TILE_SKIP=3'd3,
                     ERR_NO_FRAME=3'd4, ERR_WRITE=3'd5, ERR_CORE=3'd6;

    reg [2:0] state;
    reg [3:0] tile_q;
    reg core_start_q;
    reg mask_q;
    reg signed [ACC_W-1:0] acc [0:N_CLASS-1];
    reg signed [BIAS_W-1:0] bias [0:N_CLASS-1];
    reg signed [SCORE_W-1:0] score_q [0:N_CLASS-1];

    wire loading = (state == IDLE) || (state == LOAD);
    wire w_ok = loading && (wr_class_i < N_CLASS);
    wire b_ok = (state == IDLE) && (wr_class_i < N_CLASS);
    assign load_ready_o = resetn && loading;
    assign frame_ack_o = (state == ACK) || (state == DROP);
    assign tile_idx_o = tile_q;

    // 마지막 타일 무효 주소의 x 차단: 프레임 버퍼와 같은 1클록 지연으로 정렬
    always @(posedge clk)
        if (x_rd_en_o)
            mask_q <= (tile_q == LAST_TILE) && (x_rd_addr_o >= LAST_LEN);

    wire core_done, core_err;
    p3_group10_core #(.IN_LEN(64), .OUT_N(10)) core(
        .clk(clk), .resetn(resetn), .start_i(core_start_q), .x_valid_i(x_valid_i),
        .x_rd_en_o(x_rd_en_o), .x_rd_addr_o(x_rd_addr_o),
        .x_rd_data_i(mask_q ? 8'sd0 : x_rd_data_i),
        .w_wr_en_i(w_wr_en_i && w_ok), .b_wr_en_i(1'b0), .wr_class_i(wr_class_i),
        .wr_addr_i(wr_addr_i), .w_data_i(w_data_i), .b_data_i(24'sd0), .load_ready_o(),
        .busy_o(), .done_o(core_done), .error_o(core_err), .class_o(), .scores_o(part_scores_o));

    // 클래스별 외부 누산(넘침 검출 폭 SUM_W)과 최종 Bias 합
    wire signed [SUM_W-1:0] sum_w [0:N_CLASS-1];
    wire signed [SCORE_W-1:0] final_w [0:N_CLASS-1];
    wire [N_CLASS-1:0] acc_fit;
    genvar g;
    generate
        for (g = 0; g < N_CLASS; g = g + 1) begin : cls
            assign sum_w[g] = acc[g] + $signed(part_scores_o[g*PART_W +: PART_W]);
            // 상위 비트가 모두 부호와 같으면 ACC_W 안에 들어간다
            assign acc_fit[g] = &sum_w[g][SUM_W-1:ACC_W-1] || ~|sum_w[g][SUM_W-1:ACC_W-1];
            assign final_w[g] = acc[g] + bias[g];
            assign scores_o[g*SCORE_W +: SCORE_W] = score_q[g];
        end
    endgenerate

    // 10개 점수 최대값, 동점은 낮은 번호(14장 코어와 같은 규칙)
    integer k;
    reg [3:0] best_class;
    reg signed [SCORE_W-1:0] best_score;
    always @* begin
        best_class = 4'd0;
        best_score = score_q[0];
        for (k = 1; k < N_CLASS; k = k + 1)
            if (score_q[k] > best_score) begin
                best_score = score_q[k];
                best_class = k[3:0];
            end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            tile_q <= 4'd0;
            core_start_q <= 1'b0;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            err_code_o <= 3'd0;
            ovf_o <= 1'b0;
            tile_done_o <= 1'b0;
            class_o <= 4'd0;
            for (k = 0; k < N_CLASS; k = k + 1) begin
                acc[k] <= {ACC_W{1'b0}};
                bias[k] <= {BIAS_W{1'b0}};
                score_q[k] <= {SCORE_W{1'b0}};
            end
        end else begin
            core_start_q <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            tile_done_o <= 1'b0;
            // Bias는 IDLE에서만 바꿀 수 있다(추론 중 변경 금지)
            if (b_wr_en_i && b_ok)
                bias[wr_class_i] <= b_data_i;
            if ((w_wr_en_i && !w_ok) || (b_wr_en_i && !b_ok)) begin
                error_o <= 1'b1;
                err_code_o <= ERR_WRITE;
            end
            // 허용 상태 밖의 명령: IDLE은 start만, LOAD는 tile_go·abort만
            if ((start_i && state != IDLE) || ((tile_go_i || abort_i) && state != LOAD)) begin
                error_o <= 1'b1;
                err_code_o <= ERR_STATE;
            end
            case (state)
                IDLE: if (start_i) begin
                    busy_o <= 1'b1;
                    tile_q <= 4'd0;
                    ovf_o <= 1'b0;
                    for (k = 0; k < N_CLASS; k = k + 1)
                        acc[k] <= {ACC_W{1'b0}};
                    state <= LOAD;
                end
                LOAD: if (abort_i) begin
                    state <= DROP;
                end else if (tile_go_i) begin
                    // 타일 번호는 0..12 순서대로 한 번씩만: 이미 처리한 번호는 중복, 앞선 번호는 누락
                    if (tile_id_i < tile_q) begin
                        error_o <= 1'b1;
                        err_code_o <= ERR_TILE_DUP;
                    end else if (tile_id_i > tile_q) begin
                        error_o <= 1'b1;
                        err_code_o <= ERR_TILE_SKIP;
                    end else if (!x_valid_i) begin
                        error_o <= 1'b1;
                        err_code_o <= ERR_NO_FRAME;
                    end else begin
                        core_start_q <= 1'b1;
                        state <= RUN;
                    end
                end
                // 코어 done 시 10개 부분합은 고정되어 있다 → 외부 누산기에 한 번에 더한다
                RUN: if (core_done) begin
                    for (k = 0; k < N_CLASS; k = k + 1)
                        acc[k] <= sum_w[k][ACC_W-1:0];
                    if (~&acc_fit)
                        ovf_o <= 1'b1;
                    tile_done_o <= 1'b1;
                    state <= ACK;
                end
                // frame_ack_o = 1: 현재 타일 프레임 해제 → 다음 타일 프레임 수신 가능
                ACK: if (tile_q == LAST_TILE) begin
                    state <= SCORE;
                end else begin
                    tile_q <= tile_q + 4'd1;
                    state <= LOAD;
                end
                SCORE: begin
                    for (k = 0; k < N_CLASS; k = k + 1)
                        score_q[k] <= final_w[k];
                    state <= FINISH;
                end
                FINISH: begin
                    class_o <= best_class;
                    done_o <= 1'b1;
                    busy_o <= 1'b0;
                    state <= IDLE;
                end
                // 취소: frame_ack_o = 1로 보관 프레임 해제
                DROP: begin
                    busy_o <= 1'b0;
                    state <= IDLE;
                end
                default: begin
                    busy_o <= 1'b0;
                    state <= IDLE;
                end
            endcase
            // 컨트롤러가 쓰기·start를 거른 뒤이므로 코어 오류는 발생하면 안 된다(진단용)
            if (core_err) begin
                error_o <= 1'b1;
                err_code_o <= ERR_CORE;
            end
        end
    end
    // synthesis translate_off
    initial begin
        if (ACC_W < 2 || BIAS_W < 2 || SCORE_W < ((ACC_W > BIAS_W) ? ACC_W : BIAS_W) + 1)
            $fatal(1, "Require SCORE_W >= max(ACC_W, BIAS_W) + 1");
    end
    // synthesis translate_on
endmodule
