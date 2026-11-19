// (추가) 30장: BD 모듈 참조용 모터 안전 코어 래퍼. AXI GPIO 2와 같은 클록·peripheral_aresetn을 쓴다.
//   cmd_i ← GPIO 2 채널 1(명령 워드), status_o → GPIO 2 채널 2(상태 워드). CPU는 이 두 레지스터로만 닿는다.
//   외부 입력은 2단 동기화한다(비동기 버튼·스위치·외부 회로). 비상정지는 두 경로의 OR:
//     estop_ok_i: 외부 NC 비상정지 루프(닫힘 = 1). XDC PULLDOWN → 끊김·미연결이면 0 → 정지(fail-safe)
//     estop_btn_i: 보드 btnU(누르면 1)
//   fault_i(과전류·드라이버 고장), otemp_i(과열), lim_f_i/lim_r_i(리밋)는 이 장에서는 스위치로 흉내 낸다.
//   in1_o/in2_o/ena_o → Pmod JB → 모터 드라이버(외부 전원·보호회로, 사용자와 함께 연결). trip_o는 LED 표시용.
`timescale 1ns/1ps
module p3_motor_safety_bd #(
    parameter integer PWM_PERIOD = 5000,
    parameter integer DEAD_CYC   = 10000000,
    parameter integer WD_CYC     = 50000000,
    parameter integer RAMP_CYC   = 100000
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [31:0] cmd_i,
    output wire [31:0] status_o,
    input  wire        estop_ok_i,
    input  wire        estop_btn_i,
    input  wire        fault_i,
    input  wire        otemp_i,
    input  wire        lim_f_i,
    input  wire        lim_r_i,
    output wire        in1_o,
    output wire        in2_o,
    output wire        ena_o,
    output wire        trip_o
);
    (* ASYNC_REG = "TRUE" *) reg [5:0] s1, s2;
    always @(posedge clk) begin
        s1 <= {lim_r_i, lim_f_i, otemp_i, fault_i, estop_btn_i, ~estop_ok_i};
        s2 <= s1;
    end
    wire estop = s2[0] | s2[1];

    p3_motor_safety #(.PWM_PERIOD(PWM_PERIOD), .DEAD_CYC(DEAD_CYC), .WD_CYC(WD_CYC), .RAMP_CYC(RAMP_CYC)) u_core (
        .clk(clk), .rst(!resetn), .cmd(cmd_i), .estop(estop), .fault(s2[2]), .otemp(s2[3]),
        .lim_f(s2[4]), .lim_r(s2[5]), .in1(in1_o), .in2(in2_o), .ena(ena_o), .status(status_o));
    assign trip_o = status_o[14];
endmodule
