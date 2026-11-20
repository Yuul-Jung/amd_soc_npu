// (추가) 30장 사용자 Top: 보드 핀 연결만 한다(판단 로직 없음, MBV_SOC §4).
// (변경) 안 A(2026-11-20): 21장 동결 주소맵 SoC 복제본 BD(MicroBlaze V + NPU + BTN GPIO + 표준 7세그먼트 IP)에
//   모터 GPIO(axi_gpio_motor, 0x4007_0000) + 모터 안전 코어를 더한 Wrapper. 7세그먼트는 BD 안 ip06_seg7이 구동한다.
// LED9..12는 코어 출력을 직접 보여 준다(CPU와 무관): LED12 ENA(PWM 밝기), LED11 IN1(FWD), LED10 IN2(REV), LED9 트립.
//   나머지 LED는 CPU(AXI GPIO 0).
// Pmod JB: JB1 A14 → IN1, JB2 A16 → IN2, JB3 B15 → ENA(제2부 07장과 같은 핀), JB4 B16 ← 비상정지 루프(PULLDOWN).
// 버튼: btn[3] = btnU는 21장처럼 axi_gpio_btn으로 가고, 같은 핀을 비상정지 버튼(estop_btn)에도 연결한다.
// 스위치(시험 주입용, CPU도 읽음): sw[14] 정방향 리밋, sw[13] 역방향 리밋, sw[12] 고장, sw[11] 과열.
module basys3_soc30_top (
    input  wire        clk,    // Basys3 W5: 외부 100 MHz
    input  wire        btnC,   // Basys3 U18: SoC Reset
    input  wire [3:0]  btn,    // [3] btnU T18(비상정지 겸용), [2] btnD U17, [1] btnL W19, [0] btnR T17
    input  wire [15:0] sw,
    output wire [15:0] led,
    input  wire        RsRx,
    output wire        RsTx,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,
    output wire [2:0]  JB,     // JB[0] IN1, JB[1] IN2, JB[2] ENA
    input  wire        JB4     // 비상정지 루프(닫힘 = High)
);
    wire [15:0] led_cpu;
    wire in1, in2, ena, trip;
    soc11_integration_wrapper u_soc11 (
        .clk         (clk),
        .btnC        (btnC),
        .btn_tri_i   (btn),
        .sw_tri_i    (sw),
        .led_tri_o   (led_cpu),
        .UART_0_rxd  (RsRx),
        .UART_0_txd  (RsTx),
        .seg         (seg),
        .dp          (dp),
        .an          (an),
        .estop_ok    (JB4),
        .estop_btn   (btn[3]),
        .fault       (sw[12]),
        .otemp       (sw[11]),
        .lim_f       (sw[14]),
        .lim_r       (sw[13]),
        .in1         (in1),
        .in2         (in2),
        .ena         (ena),
        .trip        (trip)
    );
    assign JB  = {ena, in2, in1};
    assign led = {led_cpu[15:13], ena, in1, in2, trip, led_cpu[8:0]};
endmodule
