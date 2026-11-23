// NPU 추천과 독립된 모터 안전 코어(L298N 계열 IN1/IN2/ENA, 제2부 07장 motor_controller 구조를 확장).
//   CPU(NPU 추천)는 명령 워드만 쓴다. IN1/IN2/ENA는 이 코어만 구동하고, 아래 조건이 하나라도 참이면
//   클록을 기다리지 않고(조합) 모두 0이다: E-Stop, 고장(과전류 등), 과열, 워치독 만료, 트립 래치, 진행 방향 리밋.
//   입력 estop/fault/otemp/lim_*는 Top에서 2단 동기화한 신호다(Top: 비상정지는 NC 접점 + 풀업, 끊기면 정지).
//
// 명령 워드 cmd (AXI GPIO 채널 1):
//   [6:0] duty 0..100 %, [9:8] dir 0 STOP·1 FWD·2 REV(3 = 무효), [12] clear 토글, [15] kick 토글
//   kick 토글(이전 값과 다름) = 새 명령: 유효하면 req ← (dir, duty), 무효(dir 3 또는 duty > 100)면 STOP + cmd_err.
//                               워치독 wd_cnt ← WD_CYC. 이후 매 클록 1씩 감소, 0이면 wd_exp(명령이 오래됨).
//   clear 토글 = 트립 해제 요청: 그 클록에 req_dir = STOP이고 원인이 사라진 래치 비트만 지운다.
//   (같은 클록 kick의 재장전은 다음 클록부터 보이므로 WD 래치는 kick 다음 쓰기에서 지운다.)
// 래치 원인 latched[4:0] = {RESET, WD, OTEMP, FAULT, ESTOP}. Reset 직후 RESET = 1 → 해제 전에는 움직이지 않는다.
// 방향: 정지·반전 때 drive_dir 0으로 두고 DEAD_CYC 동안 IN1=IN2=0. 속도: 올릴 때 RAMP_CYC마다 1 %, 내릴 때 즉시.
// PWM: pwm_cnt 0..PWM_PERIOD-1, ENA = 방향 출력 && pwm_cnt < duty·(PWM_PERIOD/100).
// 상태 워드 status (AXI GPIO 채널 2):
//   [6:0] duty_cur [7] cmd_err [9:8] drive_dir [11:10] req_dir [12] gate [13] dead [14] trip [15] wd_exp
//   [20:16] latched [25:21] 입력 {lim_r, lim_f, otemp, fault, estop} [26] in1 [27] in2 [28] ena
// 이 코어는 교육용이며 인증된 기능안전 로직이 아니다. 실제 모터는 드라이버·외부 전원·전류 보호를 따로 둔다.
`timescale 1ns/1ps
module p3_motor_safety #(
    parameter integer PWM_PERIOD = 5000,       // 100 MHz / 5000 = 20 kHz, 100의 배수
    parameter integer DEAD_CYC   = 10000000,   // 100 ms
    parameter integer WD_CYC     = 50000000,   // 500 ms
    parameter integer RAMP_CYC   = 100000      // 1 ms / 1 %
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] cmd,
    input  wire        estop,
    input  wire        fault,
    input  wire        otemp,
    input  wire        lim_f,
    input  wire        lim_r,
    output wire        in1,
    output wire        in2,
    output wire        ena,
    output wire [31:0] status
);
    localparam [1:0] STOP = 2'd0, FWD = 2'd1, REV = 2'd2;
    localparam integer STEP = PWM_PERIOD / 100;

    // ---------------------------------------------------------------- 명령 승인·워치독
    reg        kick_q, clr_q, cmd_err;
    reg [1:0]  req_dir;
    reg [6:0]  req_duty;
    reg [31:0] wd_cnt;
    wire       kick_ev = cmd[15] ^ kick_q;
    wire       clr_ev  = cmd[12] ^ clr_q;
    wire       cmd_ok  = cmd[9:8] != 2'd3 && cmd[6:0] <= 7'd100;
    wire       wd_exp  = wd_cnt == 32'd0;

    always @(posedge clk) begin
        if (rst) begin
            kick_q <= 1'b0; clr_q <= 1'b0; cmd_err <= 1'b0;
            req_dir <= STOP; req_duty <= 7'd0; wd_cnt <= 32'd0;
        end else begin
            kick_q <= cmd[15];
            clr_q  <= cmd[12];
            if (kick_ev) begin
                wd_cnt  <= WD_CYC;
                cmd_err <= !cmd_ok;
                req_dir <= cmd_ok ? cmd[9:8] : STOP;
                req_duty <= (cmd_ok && cmd[9:8] != STOP) ? cmd[6:0] : 7'd0;
            end else if (!wd_exp) begin
                wd_cnt <= wd_cnt - 32'd1;
            end
        end
    end

    // ---------------------------------------------------------------- 독립 인터록(최우선)
    reg  [4:0] latched;                                    // {RESET, WD, OTEMP, FAULT, ESTOP}
    wire [4:0] cause = {1'b0, wd_exp, otemp, fault, estop};
    wire       trip  = |latched;
    wire       hard  = estop | fault | otemp | wd_exp | trip;
    reg  [1:0] drive_dir;
    wire       lim_block = (drive_dir == FWD && lim_f) || (drive_dir == REV && lim_r);
    wire       gate = !hard && !lim_block;
    wire       req_ok = !hard && !(req_dir == FWD && lim_f) && !(req_dir == REV && lim_r);

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            latched <= 5'b10000;                           // 전원 복귀·Reset 후 자동 재가동 금지
        end else begin
            for (i = 0; i < 5; i = i + 1)
                if (cause[i])
                    latched[i] <= 1'b1;
                else if (clr_ev && req_dir == STOP)
                    latched[i] <= 1'b0;
        end
    end

    // ---------------------------------------------------------------- 방향·데드타임·램프·PWM
    reg [31:0] dead_cnt, ramp_cnt, pwm_cnt;
    reg [6:0]  duty_cur;
    always @(posedge clk) begin
        if (rst) begin
            drive_dir <= STOP; dead_cnt <= 32'd0; ramp_cnt <= 32'd0; pwm_cnt <= 32'd0; duty_cur <= 7'd0;
        end else begin
            pwm_cnt <= (pwm_cnt == PWM_PERIOD - 1) ? 32'd0 : pwm_cnt + 32'd1;
            if (!req_ok || req_dir == STOP || (drive_dir != STOP && drive_dir != req_dir)) begin
                duty_cur <= 7'd0;
                ramp_cnt <= 32'd0;
                if (drive_dir != STOP) begin
                    drive_dir <= STOP;
                    dead_cnt  <= DEAD_CYC;
                end else if (dead_cnt != 32'd0) begin
                    dead_cnt <= dead_cnt - 32'd1;
                end
            end else if (drive_dir == STOP) begin
                ramp_cnt <= 32'd0;
                if (dead_cnt != 32'd0)
                    dead_cnt <= dead_cnt - 32'd1;
                else
                    drive_dir <= req_dir;
            end else if (req_duty < duty_cur) begin
                duty_cur <= req_duty;
                ramp_cnt <= 32'd0;
            end else if (req_duty > duty_cur) begin
                if (ramp_cnt == RAMP_CYC - 1) begin
                    duty_cur <= duty_cur + 7'd1;
                    ramp_cnt <= 32'd0;
                end else begin
                    ramp_cnt <= ramp_cnt + 32'd1;
                end
            end else begin
                ramp_cnt <= 32'd0;
            end
        end
    end

    assign in1 = gate && drive_dir == FWD;
    assign in2 = gate && drive_dir == REV;
    assign ena = (in1 || in2) && pwm_cnt < duty_cur * STEP;
    assign status = {3'd0, ena, in2, in1, lim_r, lim_f, otemp, fault, estop, latched,
                     wd_exp, trip, dead_cnt != 32'd0, gate, req_dir, drive_dir, cmd_err, duty_cur};
endmodule
