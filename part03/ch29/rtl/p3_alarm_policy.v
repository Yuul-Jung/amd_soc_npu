// 경보 정책 RTL(펌웨어 policy_cand/policy_ack, Python sensor_reference.Policy와 같은 규칙).
//   상태 코드: NORMAL 0, WARNING 1, FAULT 2, UNKNOWN 3. 심각도: NORMAL < WARNING < UNKNOWN < FAULT
//   rst(동기, High) → UNKNOWN(데이터를 보기 전 안전한 기본값), latch 0
//   cand_valid: 후보 심각도 ≥ 현재 → 즉시 그 상태(cnt 0), FAULT면 latch 1
//               후보 < 현재 → latch면 cnt 0(하향 없음), 아니면 연속 CLEAR_N번째에 그 후보들 중 가장 심각한 상태로
//   ack(cand_valid 없을 때만): latch면 latch 0·cnt 0·ack_ok 1클록. 같은 클록에 후보가 오면 ACK는 무시(보수적)
//   alarm_o = state ≠ NORMAL. 표시·기록용이며 위험 장치 정지에는 독립 보호 로직을 쓴다(6-4).
// 복합 우선순위 판단은 이 모듈에만 두고 Top에는 두지 않는다(6-3 가이드 6절).
`timescale 1ns/1ps
module p3_alarm_policy #(
    parameter integer CLEAR_N = 3          // 2..4
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       cand_valid,
    input  wire [1:0] cand,
    input  wire       ack,
    output reg  [1:0] state,
    output reg        latch,
    output reg  [1:0] cnt,
    output reg        ack_ok,
    output wire       alarm_o,
    output wire [3:0] state_onehot
);
    localparam [1:0] NORMAL = 2'd0, WARNING = 2'd1, FAULT = 2'd2, UNKNOWN = 2'd3;

    function [1:0] sev;                     // 코드 → 심각도
        input [1:0] c;
        case (c)
            NORMAL:  sev = 2'd0;
            WARNING: sev = 2'd1;
            UNKNOWN: sev = 2'd2;
            default: sev = 2'd3;            // FAULT
        endcase
    endfunction

    function [1:0] code_of;                 // 심각도 → 코드
        input [1:0] s;
        case (s)
            2'd0:    code_of = NORMAL;
            2'd1:    code_of = WARNING;
            2'd2:    code_of = UNKNOWN;
            default: code_of = FAULT;
        endcase
    endfunction

    reg  [1:0] hold;                        // 하향 대기 중 후보들의 최대 심각도
    wire [1:0] s_cand = sev(cand);
    wire [1:0] s_cur  = sev(state);
    wire [1:0] hold_n = (cnt == 2'd0 || s_cand > hold) ? s_cand : hold;

    always @(posedge clk) begin
        if (rst) begin
            state  <= UNKNOWN;
            latch  <= 1'b0;
            cnt    <= 2'd0;
            hold   <= 2'd0;
            ack_ok <= 1'b0;
        end else begin
            ack_ok <= 1'b0;
            if (cand_valid) begin
                if (s_cand >= s_cur) begin
                    state <= cand;
                    cnt   <= 2'd0;
                    if (cand == FAULT)
                        latch <= 1'b1;
                end else if (latch) begin
                    cnt <= 2'd0;
                end else begin
                    hold <= hold_n;
                    if (cnt == CLEAR_N - 1) begin
                        state <= code_of(hold_n);
                        cnt   <= 2'd0;
                    end else begin
                        cnt <= cnt + 2'd1;
                    end
                end
            end else if (ack && latch) begin
                latch  <= 1'b0;
                cnt    <= 2'd0;
                ack_ok <= 1'b1;
            end
        end
    end

    assign alarm_o      = state != NORMAL;
    assign state_onehot = 4'b0001 << state;
endmodule
