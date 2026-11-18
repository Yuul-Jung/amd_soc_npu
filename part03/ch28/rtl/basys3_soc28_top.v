// (추가) 28장 사용자 Top: 21장 SoC(MicroBlaze V + NPU) 복제본 BD에 FND 출력(seg/dp/an)을 더한 Wrapper와 보드 핀 연결.
// FND 스캔(p3_fnd_scan)은 BD 안의 모듈 참조 셀이라 GPIO와 같은 클록·Reset을 쓴다. Top은 핀 연결만 한다.
// 제1부 11장 basys3_soc11_top은 원본 그대로 두고(복제본에서 비활성), 이 파일을 Top으로 쓴다.
module basys3_soc28_top (
    input  wire        clk,    // Basys3 W5: 외부 100 MHz
    input  wire        btnC,   // Basys3 U18: SoC Reset
    input  wire [15:0] sw,
    output wire [15:0] led,    // LED[9:0] Class one-hot, LED14 오류, LED15 결과 유효
    input  wire        RsRx,   // USB-UART PC -> FPGA (숫자 프레임)
    output wire        RsTx,   // USB-UART FPGA -> PC (결과 줄)
    output wire [6:0]  seg,    // FND 세그먼트 a..g (Low 활성)
    output wire        dp,
    output wire [3:0]  an      // FND 자리 선택 (Low 활성)
);
    soc11_integration_wrapper u_soc11 (
        .clk         (clk),
        .btnC        (btnC),
        .sw_tri_i    (sw),
        .led_tri_o   (led),
        .UART_0_rxd  (RsRx),
        .UART_0_txd  (RsTx),
        .seg         (seg),
        .dp          (dp),
        .an          (an)
    );
endmodule
