`timescale 1ns/1ps
// Basys3 4자리 FND(7-세그먼트) 시분할 구동. 표시 내용은 MicroBlaze V가 AXI GPIO 1로 쓴 32비트 워드다.
//   word_i[15:0]  자리별 16진 nibble(자리 0 = 가장 오른쪽 an[0])
//   word_i[19:16] 자리 켜짐(0이면 그 자리 꺼짐: an·seg 모두 High)
//   word_i[23:20] 소수점(dp) 켜짐
// 핀은 모두 Low 활성(Basys3 공통 애노드). seg[0]=CA(a) … seg[6]=CG(g).
// 자리마다 2^DIV_W 클록 유지(100 MHz, DIV_W=17 → 자리당 1.31 ms, 4자리 주기 5.2 ms ≈ 190 Hz). 출력은 모두 레지스터.
module p3_fnd_scan #(
    parameter integer DIV_W = 17
)(
    input wire clk,
    input wire resetn,
    input wire [31:0] word_i,
    output reg [6:0] seg_o,
    output reg dp_o,
    output reg [3:0] an_o
);
    reg [DIV_W+1:0] cnt_q;
    wire [1:0] sel = cnt_q[DIV_W+1:DIV_W];
    wire [3:0] nib = word_i[4*sel +: 4];
    wire on = word_i[16 + sel];
    wire dp_on = word_i[20 + sel];

    function [6:0] hex7;                 // gfedcba, High = 켜짐
        input [3:0] v;
        case (v)
            4'h0: hex7 = 7'h3F; 4'h1: hex7 = 7'h06; 4'h2: hex7 = 7'h5B; 4'h3: hex7 = 7'h4F;
            4'h4: hex7 = 7'h66; 4'h5: hex7 = 7'h6D; 4'h6: hex7 = 7'h7D; 4'h7: hex7 = 7'h07;
            4'h8: hex7 = 7'h7F; 4'h9: hex7 = 7'h6F; 4'hA: hex7 = 7'h77; 4'hB: hex7 = 7'h7C;
            4'hC: hex7 = 7'h39; 4'hD: hex7 = 7'h5E; 4'hE: hex7 = 7'h79; default: hex7 = 7'h71;
        endcase
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            cnt_q <= {(DIV_W+2){1'b0}};
            seg_o <= 7'h7F;
            dp_o <= 1'b1;
            an_o <= 4'hF;
        end else begin
            cnt_q <= cnt_q + 1'b1;
            seg_o <= on ? ~hex7(nib) : 7'h7F;
            dp_o <= ~(on && dp_on);
            an_o <= on ? ~(4'b0001 << sel) : 4'hF;
        end
    end
endmodule
