// 1장 7세그먼트: 16비트 값을 16진수 4자리로 띄운다 (보드 seg·an·dp는 active-low, seg = {g,f,e,d,c,b,a}).
// 자리 전환은 100 MHz / 2^(REFRESH_BITS-2) 마다 (기본 18 → 약 1.5 kHz, 네 자리 한 바퀴 약 381 Hz).
// 5장 SoC의 표준 SEG7 IP(ip_seg7)와 같은 표시 규칙이다.
`timescale 1ns/1ps
`default_nettype none
module p01_hex4_display #(
    parameter integer REFRESH_BITS = 18
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] value_i,
    output reg  [6:0]  seg_o,
    output reg  [3:0]  an_o,
    output wire        dp_o
);
    reg [REFRESH_BITS-1:0] cnt;
    always @(posedge clk) begin
        if (!resetn) cnt <= {REFRESH_BITS{1'b0}};
        else         cnt <= cnt + 1'b1;
    end

    wire [1:0] digit = cnt[REFRESH_BITS-1 -: 2];
    wire [3:0] nib   = value_i[4*digit +: 4];

    reg [6:0] on;                               // active-high, [0] a … [6] g
    always @(*) begin
        case (nib)
            4'h0: on = 7'b0111111;  4'h1: on = 7'b0000110;
            4'h2: on = 7'b1011011;  4'h3: on = 7'b1001111;
            4'h4: on = 7'b1100110;  4'h5: on = 7'b1101101;
            4'h6: on = 7'b1111101;  4'h7: on = 7'b0000111;
            4'h8: on = 7'b1111111;  4'h9: on = 7'b1101111;
            4'hA: on = 7'b1110111;  4'hB: on = 7'b1111100;
            4'hC: on = 7'b0111001;  4'hD: on = 7'b1011110;
            4'hE: on = 7'b1111001;  default: on = 7'b1110001;
        endcase
        seg_o = ~on;
        an_o  = ~(4'b0001 << digit);
    end
    assign dp_o = 1'b1;                         // 소수점 끔
endmodule
`default_nettype wire
