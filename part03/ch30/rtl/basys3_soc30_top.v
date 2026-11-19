// (추가) 30장 사용자 Top: 28장 SoC 복제본 BD(MicroBlaze V + NPU + FND + AXI GPIO 2 + 모터 안전 코어)와 보드 핀 연결.
// 판단 로직은 두지 않는다(핀 연결과 고정 비트 배치만). LED9..12는 코어 출력을 직접 보여 준다(CPU와 무관):
//   LED12 ENA(PWM 밝기), LED11 IN1(FWD), LED10 IN2(REV), LED9 트립. 나머지 LED는 CPU(AXI GPIO 0).
// Pmod JB: JB1 A14 → IN1, JB2 A16 → IN2, JB3 B15 → ENA(제2부 07장과 같은 핀), JB4 B16 ← 비상정지 루프(PULLDOWN).
// 스위치(시험 주입용, CPU도 읽음): sw[14] 정방향 리밋, sw[13] 역방향 리밋, sw[12] 고장, sw[11] 과열. btnU = 비상정지 버튼.
module basys3_soc30_top (
    input  wire        clk,
    input  wire        btnC,
    input  wire        btnU,
    input  wire [15:0] sw,
    output wire [15:0] led,
    input  wire        RsRx,
    output wire        RsTx,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,
    output wire [2:0]  JB,       // JB[0] IN1, JB[1] IN2, JB[2] ENA
    input  wire        JB4       // 비상정지 루프(닫힘 = High)
);
    wire [15:0] led_cpu;
    wire in1, in2, ena, trip;
    soc11_integration_wrapper u_soc11 (
        .clk         (clk),
        .btnC        (btnC),
        .sw_tri_i    (sw),
        .led_tri_o   (led_cpu),
        .UART_0_rxd  (RsRx),
        .UART_0_txd  (RsTx),
        .seg         (seg),
        .dp          (dp),
        .an          (an),
        .estop_ok    (JB4),
        .estop_btn   (btnU),
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
