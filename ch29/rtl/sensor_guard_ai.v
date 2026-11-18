`timescale 1ns/1ps
`default_nettype none
// 29장 센서 감시기: 가상 센서 4채널 × 16샘플(12비트)을 받아 유효성(범위·고착·순서)을 먼저 보고,
// 고장이 없을 때만 15장 Dense 64→4로 상태를 분류한다. 점수 1·2위 차가 MARGIN보다 작으면 UNKNOWN.
// 상태: 0 NORMAL, 1 HOT, 2 VIBRATION, 3 DRIFT, 4 UNKNOWN, 5 FAULT (고장이 AI보다 우선)
module sensor_guard_ai #(
    parameter integer MIN_RAW = 100,
    parameter integer MAX_RAW = 4000,
    parameter integer STUCK_N = 8,           // 같은 채널이 같은 값을 연속 STUCK_N번 → 고착
    parameter integer MARGIN  = 3000
) (
    input  wire         clk,
    input  wire         resetn,
    input  wire         s_valid_i,           // 샘플 하나 (채널 0,1,2,3 순서로 16번 = 창 1개)
    input  wire   [1:0] s_ch_i,
    input  wire  [11:0] s_raw_i,
    input  wire         w_wr_en_i,           // 15장 Dense 모델 쓰기 (클래스 0~3, 원소 0~63)
    input  wire   [3:0] w_neuron_i,
    input  wire   [5:0] w_addr_i,
    input  wire   [7:0] w_data_i,
    input  wire         b_wr_en_i,
    input  wire  [31:0] b_data_i,
    output reg    [2:0] state_o,
    output reg    [2:0] fault_o,             // bit0 범위, bit1 고착, bit2 순서
    output wire [127:0] scores_o,
    output reg          done_o,              // 창 하나 판정 끝 1클록 펄스
    output wire         busy_o
);
    localparam COLLECT=0, CLASSIFY=1, DECIDE=2;
    reg [1:0] st;
    reg dense_started;                       // CLASSIFY에서 Dense를 한 번만 시작
    reg [5:0] idx;
    reg signed [7:0] x_q [0:63];
    reg [11:0] prev [0:3];
    reg [3:0]  run  [0:3];
    integer i;
    assign busy_o = (st == CLASSIFY || st == DECIDE);

    // ── 샘플 하나 판정 (채널은 '와야 할' 채널 idx[1:0] 기준으로 센다 — 순서가 틀려도 위치로 비교)
    wire [1:0] ch = idx[1:0];
    wire bad_order = (s_ch_i != ch);
    wire bad_range = (s_raw_i < MIN_RAW) || (s_raw_i > MAX_RAW);
    wire same = (idx >= 4) && (s_raw_i == prev[ch]);
    wire [3:0] run_n = same ? run[ch] + 4'd1 : 4'd1;
    wire signed [12:0] centered = $signed({1'b0, s_raw_i}) - 13'sd2048;
    wire signed [12:0] shifted = centered >>> 4;
    wire signed [7:0] scaled = (shifted > 127) ? 8'sd127 : (shifted < -128) ? -8'sd128 : shifted[7:0];

    // ── 15장 Dense 64→4 (입력 = 창 버퍼, 1클록 지연)
    wire x_en; wire [5:0] x_idx; reg signed [7:0] x_d; reg x_v;
    wire d_done, d_err;
    npu_dense #(.N_IN(64), .N_OUT(4), .ACC_WIDTH(32)) dense (
        .clk(clk), .resetn(resetn), .model_clear_i(1'b0),
        .w_wr_en_i(w_wr_en_i), .w_neuron_i(w_neuron_i), .w_addr_i(w_addr_i), .w_data_i(w_data_i),
        .b_wr_en_i(b_wr_en_i), .b_neuron_i(w_neuron_i), .b_data_i(b_data_i), .model_sum_o(), .model_err_o(),
        .x_rd_en_o(x_en), .x_rd_idx_o(x_idx), .x_data_i(x_d), .x_valid_i(x_v),
        .start_i(st == CLASSIFY && !dense_started && fault_o == 0), .busy_o(), .done_o(d_done), .error_o(d_err), .scores_o(scores_o));
    always @(posedge clk) begin x_v <= resetn && x_en; if (x_en) x_d <= x_q[x_idx]; end

    // ── 1·2위 찾기 (4개, 같으면 낮은 번호가 위)
    wire signed [31:0] s0 = scores_o[0 +: 32], s1 = scores_o[32 +: 32], s2 = scores_o[64 +: 32], s3 = scores_o[96 +: 32];
    wire [1:0] b01 = (s1 > s0) ? 2'd1 : 2'd0;  wire signed [31:0] v01 = (s1 > s0) ? s1 : s0;  wire signed [31:0] l01 = (s1 > s0) ? s0 : s1;
    wire [1:0] b23 = (s3 > s2) ? 2'd3 : 2'd2;  wire signed [31:0] v23 = (s3 > s2) ? s3 : s2;  wire signed [31:0] l23 = (s3 > s2) ? s2 : s3;
    wire top23 = (v23 > v01);
    wire [1:0] best = top23 ? b23 : b01;
    wire signed [31:0] bestv = top23 ? v23 : v01;
    wire signed [31:0] second = top23 ? ((v01 > l23) ? v01 : l23) : ((v23 > l01) ? v23 : l01);

    always @(posedge clk) begin
        if (!resetn) begin
            st <= COLLECT; idx <= 0; state_o <= 0; fault_o <= 0; done_o <= 0; dense_started <= 0;
            for (i = 0; i < 4; i = i + 1) begin prev[i] <= 0; run[i] <= 0; end
        end else begin
            done_o <= 0;
            case (st)
                COLLECT: if (s_valid_i) begin
                    x_q[idx] <= scaled;
                    prev[ch] <= s_raw_i; run[ch] <= run_n;
                    fault_o <= (idx == 0 ? 3'd0 : fault_o) | {bad_order, run_n >= STUCK_N, bad_range};
                    idx <= idx + 6'd1;
                    if (idx == 63) st <= CLASSIFY;
                end
                CLASSIFY: begin
                    if (fault_o != 0) begin state_o <= 3'd5; done_o <= 1; st <= COLLECT; end   // 고장: 분류하지 않음
                    else begin
                        dense_started <= 1;
                        if (d_err) begin state_o <= 3'd5; fault_o <= 3'd4; done_o <= 1; dense_started <= 0; st <= COLLECT; end
                        else if (d_done) begin dense_started <= 0; st <= DECIDE; end
                    end
                end
                DECIDE: begin
                    state_o <= (bestv - second >= MARGIN) ? {1'b0, best} : 3'd4;
                    done_o <= 1; st <= COLLECT;
                end
                default: st <= COLLECT;
            endcase
        end
    end
endmodule
`default_nettype wire
