`timescale 1ns/1ps
// 은닉층 출력 재양자화 = sat_int8(round_shift_away(max(0, score), shift)).
// ReLU 이후 값은 0 이상이므로 절반 반올림은 (v + 2^(shift-1)) >> shift 와 같다(shift=0이면 그대로).
// 조합 회로. 입력 signed 25비트 점수, 출력 signed INT8(0..127).
module p3_relu_requant(
    input wire signed [24:0] score_i,
    input wire [4:0] shift_i,
    output wire signed [7:0] q_o
);
    // ReLU: 음수는 0
    wire [24:0] relu = score_i[24] ? 25'd0 : score_i;
    // 반올림 가산값: shift=0이면 0
    wire [32:0] half = (shift_i == 5'd0) ? 33'd0 : (33'd1 << (shift_i - 5'd1));
    wire [32:0] rounded = ({8'd0, relu} + half) >> shift_i;
    // INT8 상한 포화(ReLU 이후이므로 하한 -128은 발생하지 않음)
    assign q_o = (rounded > 33'd127) ? 8'sd127 : $signed(rounded[7:0]);
endmodule
