// (추가) 안 A(2026-11-19) 21장 사용자 Top: 동결 주소맵 SoC(MicroBlaze V + NPU + BTN GPIO + 표준 7세그먼트 IP)의 Wrapper와 보드 핀 연결.
// Top은 배선만 한다(MBV_SOC §4). 7세그먼트 구동은 BD 안 ip06_seg7(ip_seg7), 버튼은 axi_gpio_btn이 받는다.
// 제1부 11장 basys3_soc11_top은 원본 그대로 두고(복제본에서 비활성), 이 파일을 Top으로 쓴다.
module basys3_soc21_top (
    input  wire        clk,    // Basys3 W5: 외부 100 MHz
    input  wire        btnC,   // Basys3 U18: SoC Reset (11장 그대로)
    input  wire [3:0]  btn,    // [3] btnU T18, [2] btnD U17, [1] btnL W19, [0] btnR T17 → axi_gpio_btn
    input  wire [15:0] sw,
    output wire [15:0] led,
    input  wire        RsRx,   // USB-UART PC -> FPGA
    output wire        RsTx,   // USB-UART FPGA -> PC
    output wire [6:0]  seg,    // 7세그먼트 {g..a}, Low 활성 (ip_seg7)
    output wire        dp,
    output wire [3:0]  an      // 자리 선택, Low 활성
);
    soc11_integration_wrapper u_soc11 (
        .clk         (clk),
        .btnC        (btnC),
        .btn_tri_i   (btn),
        .sw_tri_i    (sw),
        .led_tri_o   (led),
        .UART_0_rxd  (RsRx),
        .UART_0_txd  (RsTx),
        .seg         (seg),
        .dp          (dp),
        .an          (an)
    );
endmodule
