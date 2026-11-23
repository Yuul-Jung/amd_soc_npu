`timescale 1ns/1ps
// 8×8 단일채널 signed INT8 영상의 3×3 합성곱(Cross-Correlation, stride 1, padding 0) + Bias + ReLU.
// 출력 6×6 = 36픽셀, 픽셀당 9 MAC. 1-3 dsp_multiplier 9개로 등록 곱을 만들고, 덧셈 트리를 두 단으로 나눠 합한다
// (3개씩 부분합 → 부분합 3개 + Bias). 한 클록 9항 합은 100 MHz를 넘지 못해(OOC 배선 WNS −8.1 ns) 나눴다.
// 입력은 행 우선 픽셀 스트림(valid/last). 64번째 픽셀에만 last가 있어야 한다.
//   짧은 프레임(이른 last): 오류 펄스, 다음 픽셀부터 새 프레임. 긴 프레임(64번째에 last 없음): 오류 펄스,
//   다음 last까지 버린 뒤 새 프레임(3-1 프레임 버퍼와 같은 재동기 규칙). 이미 나간 출력은 취소하지 않는다.
// 창 생성: 라인 버퍼 2줄(행 r-1, r-2)과 3×3 창 레지스터. (r, c) 픽셀이 들어오면 창 = 행 r-2..r, 열 c-2..c,
//   r ≥ 2 && c ≥ 2일 때 유효하며 출력 위치는 (r-2, c-2). valid가 없는 클록(버블)에는 창이 움직이지 않는다.
// 지연: 픽셀 수락 → out_valid 5클록(창, 곱, 부분합, 합+Bias, ReLU·출력 레지스터). 처리량 1픽셀/클록.
// out = relu_en ? max(0, s) : s,  s = Σ w[i][j]·x[r-2+i][c-2+j] + bias (signed 25비트)
module p3_conv3x3_8x8(
    input wire clk,
    input wire resetn,
    input wire signed [7:0] pix_i,
    input wire pix_valid_i,
    input wire pix_last_i,
    input wire k_wr_en_i,              // 커널 쓰기: k_addr_i = 3*i + j
    input wire [3:0] k_addr_i,
    input wire signed [7:0] k_data_i,
    input wire b_wr_en_i,
    input wire signed [23:0] b_data_i,
    input wire relu_en_i,
    output wire load_ready_o,          // 프레임 시작 전이고 파이프라인이 비었을 때 커널·Bias 쓰기 가능
    output reg signed [24:0] out_o,
    output reg out_valid_o,
    output reg [2:0] out_row_o,
    output reg [2:0] out_col_o,
    output reg out_last_o,             // 36번째 출력
    output reg error_o                 // 길이 오류 프레임 또는 허용되지 않은 커널 쓰기
);
    reg [2:0] row_q, col_q;
    reg signed [7:0] lb1 [0:7];        // 행 r-1
    reg signed [7:0] lb2 [0:7];        // 행 r-2
    reg signed [7:0] win [0:8];        // win[3*i+j]: 창 행 i, 열 j
    reg signed [7:0] kern [0:8];
    reg signed [23:0] bias_q;
    reg wv_q, wlast_q, relu_q;
    reg [2:0] wrow_q, wcol_q;
    reg [2:0] prow_q, pcol_q, row2_q, col2_q, row3_q, col3_q;
    reg plast_q, prelu_q, v2_q, last2_q, relu2_q, v3_q, last3_q, relu3_q;
    // 덧셈은 LUT 캐리 체인으로: DSP 캐스케이드로 묶이면 OOC 배치에서 PCOUT 48핀 배선 실패(실제 확인)
    (* use_dsp = "no" *) reg signed [17:0] ps0_q, ps1_q, ps2_q;   // 3항 부분합: |3·128·128| < 2^17
    (* use_dsp = "no" *) reg signed [24:0] tot_q;
    integer k;

    reg drop_q;                        // 긴 프레임: 다음 last까지 버림
    // 9개 등록 곱(1-3 dsp_multiplier 재사용): 창 레지스터 → 곱(1클록)
    wire signed [15:0] prod [0:8];
    wire [8:0] pvalid;
    wire pv = pvalid[0];
    wire frame_idle = (row_q == 3'd0) && (col_q == 3'd0) && !drop_q;
    wire pipe_empty = !wv_q && !pv && !v2_q && !v3_q;
    assign load_ready_o = resetn && frame_idle && pipe_empty && !pix_valid_i;
    wire pix_acc = pix_valid_i && !drop_q;
    wire last_pos = (row_q == 3'd7) && (col_q == 3'd7);
    genvar g;
    generate
        for (g = 0; g < 9; g = g + 1) begin : mul
            dsp_multiplier #(.A_WIDTH(8), .B_WIDTH(8)) m(
                .clk(clk), .resetn(resetn), .clear_i(1'b0), .valid_i(wv_q),
                .a_i(win[g]), .b_i(kern[g]), .product_o(prod[g]), .valid_o(pvalid[g]));
        end
    endgenerate

    // 라인 버퍼·창: Reset 없이 데이터만 이동(제어 신호만 Reset)
    always @(posedge clk) begin
        if (pix_acc) begin
            lb2[col_q] <= lb1[col_q];
            lb1[col_q] <= pix_i;
            // 창을 왼쪽으로 한 열 밀고 오른쪽 열에 (r-2, r-1, r) 픽셀을 넣는다
            win[0] <= win[1]; win[1] <= win[2]; win[2] <= lb2[col_q];
            win[3] <= win[4]; win[4] <= win[5]; win[5] <= lb1[col_q];
            win[6] <= win[7]; win[7] <= win[8]; win[8] <= pix_i;
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            row_q <= 3'd0; col_q <= 3'd0; drop_q <= 1'b0;
            wv_q <= 1'b0; wlast_q <= 1'b0; relu_q <= 1'b0; wrow_q <= 3'd0; wcol_q <= 3'd0;
            prow_q <= 3'd0; pcol_q <= 3'd0; plast_q <= 1'b0; prelu_q <= 1'b0;
            v2_q <= 1'b0; v3_q <= 1'b0; last2_q <= 1'b0; last3_q <= 1'b0;
            out_o <= 25'sd0; out_valid_o <= 1'b0; out_row_o <= 3'd0; out_col_o <= 3'd0;
            out_last_o <= 1'b0; error_o <= 1'b0; bias_q <= 24'sd0;
            for (k = 0; k < 9; k = k + 1) kern[k] <= 8'sd0;
        end else begin
            error_o <= 1'b0;
            // 커널·Bias: 프레임 사이에만
            if ((k_wr_en_i || b_wr_en_i) && !load_ready_o)
                error_o <= 1'b1;
            if (k_wr_en_i && load_ready_o && k_addr_i < 4'd9)
                kern[k_addr_i] <= k_data_i;
            if (k_wr_en_i && load_ready_o && k_addr_i >= 4'd9)
                error_o <= 1'b1;
            if (b_wr_en_i && load_ready_o)
                bias_q <= b_data_i;
            // 픽셀 위치·프레임 길이
            wv_q <= 1'b0;
            wlast_q <= 1'b0;
            if (drop_q && pix_valid_i && pix_last_i)
                drop_q <= 1'b0;
            if (pix_acc) begin
                wv_q <= (row_q >= 3'd2) && (col_q >= 3'd2);
                wlast_q <= last_pos;
                wrow_q <= row_q - 3'd2;
                wcol_q <= col_q - 3'd2;
                relu_q <= relu_en_i;
                if (pix_last_i != last_pos) begin
                    error_o <= 1'b1;
                    row_q <= 3'd0;
                    col_q <= 3'd0;
                    wv_q <= 1'b0;
                    drop_q <= last_pos;        // 64번째인데 last 없음 → 긴 프레임
                end else begin
                    col_q <= col_q + 3'd1;
                    if (col_q == 3'd7)
                        row_q <= row_q + 3'd1;
                end
            end
            // 곱 단계 태그
            prow_q <= wrow_q; pcol_q <= wcol_q; plast_q <= wlast_q && wv_q; prelu_q <= relu_q;
            // 부분합 단계(3항씩)
            v2_q <= pv;
            if (pv) begin
                ps0_q <= prod[0] + prod[1] + prod[2];
                ps1_q <= prod[3] + prod[4] + prod[5];
                ps2_q <= prod[6] + prod[7] + prod[8];
                row2_q <= prow_q; col2_q <= pcol_q; last2_q <= plast_q; relu2_q <= prelu_q;
            end
            // 합 + Bias 단계
            v3_q <= v2_q;
            if (v2_q) begin
                tot_q <= ps0_q + ps1_q + ps2_q + bias_q;
                row3_q <= row2_q; col3_q <= col2_q; last3_q <= last2_q; relu3_q <= relu2_q;
            end
            // ReLU·출력 단계
            out_valid_o <= v3_q;
            if (v3_q) begin
                out_o <= (relu3_q && tot_q < 0) ? 25'sd0 : tot_q;
                out_row_o <= row3_q;
                out_col_o <= col3_q;
                out_last_o <= last3_q;
            end else begin
                out_last_o <= 1'b0;
            end
        end
    end
endmodule
