`timescale 1ns/1ps
`default_nettype none
// 27장 7세그먼트 표시기: GPIO LED 워드(펌웨어가 씀)에서 클래스를 읽어 오른쪽 자리에 숫자로 보인다.
// LED 워드 약속: [9:0] 클래스 원핫, [13:10] 클래스 번호(0~9), [14] 오류, [15] 결과 있음.
// 오른쪽 자리: 결과 있음 → 0~9, 오류 → E, 결과 없음 → '-'. 나머지 세 자리는 끔. 세그먼트·자리 모두 Active-Low.
module fnd_class_display #(
    parameter integer SCAN_BITS = 18        // 100 MHz / 2^16 ≈ 1.5 kHz로 자리 전환 (시뮬레이션은 작게)
) (
    input  wire        clk,
    input  wire [15:0] led_word_i,
    output reg   [6:0] seg_o,               // {g,f,e,d,c,b,a}
    output reg   [3:0] an_o,
    output wire        dp_o
);
    // 자리 전환 카운터는 리셋이 필요 없다 (FPGA 구성 때 0으로 시작, 값은 표시 순서에만 쓰임).
    reg [SCAN_BITS-1:0] scan = {SCAN_BITS{1'b0}};
    always @(posedge clk) scan <= scan + 1'b1;
    assign dp_o = 1'b1;

    wire [3:0] cls = led_word_i[13:10];
    reg  [6:0] glyph;
    always @(*) begin
        if (led_word_i[14]) glyph = 7'b0000110;                 // E
        else if (!led_word_i[15] || cls > 9) glyph = 7'b0111111; // -
        else case (cls)
            4'd0: glyph = 7'b1000000; 4'd1: glyph = 7'b1111001; 4'd2: glyph = 7'b0100100; 4'd3: glyph = 7'b0110000;
            4'd4: glyph = 7'b0011001; 4'd5: glyph = 7'b0010010; 4'd6: glyph = 7'b0000010; 4'd7: glyph = 7'b1111000;
            4'd8: glyph = 7'b0000000; default: glyph = 7'b0010000;
        endcase
        case (scan[SCAN_BITS-1 -: 2])
            2'd0:    begin an_o = 4'b1110; seg_o = glyph; end
            2'd1:    begin an_o = 4'b1101; seg_o = 7'b1111111; end
            2'd2:    begin an_o = 4'b1011; seg_o = 7'b1111111; end
            default: begin an_o = 4'b0111; seg_o = 7'b1111111; end
        endcase
    end
endmodule
`default_nettype wire
