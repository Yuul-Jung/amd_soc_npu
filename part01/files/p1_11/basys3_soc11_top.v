// 제1부 11장(P1-11) 사용자 Top: soc11_integration_wrapper와 보드 핀 연결
// 전제: 복제 프로젝트의 실제 Wrapper 포트와 이름을 Vivado에서 대조한다.
// Top은 보드 핀, wire 및 인스턴스 연결만 담당한다.
module basys3_soc11_top (
    input  wire        clk,    // Basys3 W5: 외부 100 MHz
    input  wire        btnC,   // Basys3 U18: 기존 SoC Reset
    input  wire [15:0] sw,     // Basys3 슬라이드 스위치
    output wire [15:0] led,    // Basys3 내장 LED 16개
    input  wire        RsRx,   // USB-UART PC -> FPGA
    output wire        RsTx    // USB-UART FPGA -> PC
);

    // (변경) 11장 BD(soc11_integration.bd)의 자동 생성 Wrapper 연결
    // (참고) 10장 BD를 Save Block Design As로 복제 후 새 Wrapper 생성
    // 실제 생성 Wrapper 선언부에서 포트명과 방향을 확인
    soc11_integration_wrapper u_soc11 (
        .clk         (clk),
        .btnC        (btnC),
        .sw_tri_i    (sw),
        .led_tri_o   (led),
        .UART_0_rxd  (RsRx),
        .UART_0_txd  (RsTx)
    );

endmodule
