`timescale 1ns/1ps
`default_nettype none
// 21장 사용자 Top: 제1부 11장 SoC를 복제한 블록 설계 soc_npu의 Wrapper를 보드 핀에 연결한다.
// Top은 핀·wire·인스턴스 연결만 한다 (연산·선택 논리 없음). NPU는 블록 설계 안에 모듈 참조 npu_0으로 들어 있다.
// Wrapper 포트 이름은 제1부 11장(soc11_integration_wrapper)과 같다 — Vivado가 만든 Wrapper 선언과 대조한다.
module soc_npu_top (
    input  wire        clk,     // W5: 100 MHz
    input  wire        btnC,    // U18: 리셋 (블록 설계 Processor System Reset, Active-High)
    input  wire [15:0] sw,
    output wire [15:0] led,
    input  wire        RsRx,    // USB-UART PC → FPGA
    output wire        RsTx     // USB-UART FPGA → PC
);
    soc_npu_wrapper u_soc (
        .clk        (clk),
        .btnC       (btnC),
        .sw_tri_i   (sw),
        .led_tri_o  (led),
        .UART_0_rxd (RsRx),
        .UART_0_txd (RsTx)
    );
endmodule
`default_nettype wire
