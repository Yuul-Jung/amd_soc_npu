`timescale 1ns/1ps
`default_nettype none
// 30장 모터 인터록: AI가 낸 속도·방향 '제안'과 실제 모터 출력 사이에 AI와 무관한 안전 조건을 둔다.
// 출력 허용 = 비상정지 해제 && 무장(arm) && 사용 스위치 && 센서 상태 정상(29장 state < 4) && AI 명령이 제때 옴(감시 타이머).
// 하나라도 빠지면 그 클록에 en_o·pwm_o를 끄고 속도를 0으로 되돌린다. 비상정지는 걸쇠: 풀어도 arm_i를 다시 눌러야 한다.
// 허용 상태에서도 속도는 TICK마다 STEP 이하로만 바뀌고, 방향은 속도가 0이 된 뒤에만 바뀐다.
module motor_interlock #(
    parameter integer TICK = 1000,         // 속도 갱신 간격 (클록)
    parameter integer STEP = 8,            // 한 번에 바뀌는 속도 상한
    parameter integer WD_LIMIT = 100000    // AI 명령이 이 클록 동안 없으면 정지
) (
    input  wire       clk,
    input  wire       resetn,
    input  wire       estop_n_i,           // 비상정지 (0 = 눌림)
    input  wire       arm_i,               // 무장 요청 (속도 0, 비상정지 해제, 사용 스위치 켬일 때만)
    input  wire       enable_i,            // 사용 스위치
    input  wire [2:0] sensor_state_i,      // 29장 상태 (4 UNKNOWN, 5 FAULT → 정지)
    input  wire       ai_valid_i,          // AI 제안 갱신
    input  wire [7:0] ai_speed_i,
    input  wire       ai_dir_i,
    output wire       en_o,                // 드라이버 사용 (허용일 때만 1)
    output wire       pwm_o,
    output reg        dir_o,
    output reg  [7:0] speed_o,             // 지금 속도 (PWM 듀티 /256)
    output wire [4:0] block_o              // 막힌 이유: {감시 타이머, 센서, 사용 스위치, 무장 안 됨, 비상정지}
);
    reg armed;
    reg [31:0] wd_cnt;
    reg [31:0] tick_cnt;
    reg [7:0] pwm_cnt;
    reg [7:0] req_speed; reg req_dir;

    wire estop = !estop_n_i;
    wire wd_expired = (wd_cnt >= WD_LIMIT);
    wire sensor_bad = (sensor_state_i >= 3'd4);
    assign block_o = {wd_expired, sensor_bad, !enable_i, !armed, estop};
    wire ok = (block_o == 5'd0);
    assign en_o = ok;
    assign pwm_o = ok && (pwm_cnt < speed_o);

    wire tick = (tick_cnt == TICK - 1);
    wire [7:0] target = (req_dir != dir_o) ? 8'd0 : req_speed;      // 방향이 다르면 먼저 0까지 줄인다
    wire [7:0] up = (target - speed_o > STEP) ? speed_o + STEP : target;
    wire [7:0] dn = (speed_o - target > STEP) ? speed_o - STEP : target;

    always @(posedge clk) begin
        if (!resetn) begin
            armed <= 0; wd_cnt <= WD_LIMIT; tick_cnt <= 0; pwm_cnt <= 0;
            req_speed <= 0; req_dir <= 0; dir_o <= 0; speed_o <= 0;
        end else begin
            pwm_cnt <= pwm_cnt + 8'd1;
            tick_cnt <= tick ? 0 : tick_cnt + 1;
            if (ai_valid_i) begin wd_cnt <= 0; req_speed <= ai_speed_i; req_dir <= ai_dir_i; end
            else if (!wd_expired) wd_cnt <= wd_cnt + 1;
            if (estop) armed <= 0;
            else if (arm_i && enable_i && speed_o == 0) armed <= 1;
            if (!ok) speed_o <= 0;                                       // 막히면 즉시 0 (다시 시작하면 0부터)
            else if (tick) begin
                if (speed_o == 0 && req_dir != dir_o) dir_o <= req_dir;   // 멈춘 뒤에만 방향 전환
                else if (target > speed_o) speed_o <= up;
                else speed_o <= dn;
            end
        end
    end
endmodule
`default_nettype wire
