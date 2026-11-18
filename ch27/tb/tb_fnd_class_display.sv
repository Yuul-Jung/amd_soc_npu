`timescale 1ns/1ps
// 27장 TB: LED 워드 13가지(클래스 0~9, 오류, 결과 없음, 범위 밖 번호)에서 네 자리의 세그먼트를 모두 확인한다.
module tb_fnd_class_display;
    reg clk = 0; reg [15:0] w = 0;
    wire [6:0] seg; wire [3:0] an; wire dp;
    fnd_class_display #(.SCAN_BITS(4)) dut(.clk(clk), .led_word_i(w), .seg_o(seg), .an_o(an), .dp_o(dp));
    always #5 clk = ~clk;
    reg [6:0] want [0:12];
    integer k, s, seen, checks = 0;
    task check_word(input [15:0] word, input [6:0] g); begin
        w = word; seen = 0;
        for (s = 0; s < 16; s = s + 1) begin
            @(negedge clk);
            case (an)
                4'b1110: begin if (seg !== g) $fatal(1, "word %h: 오른쪽 자리 %b, 기대 %b", word, seg, g); seen = seen | 1; end
                4'b1101, 4'b1011, 4'b0111: begin if (seg !== 7'b1111111) $fatal(1, "word %h: 다른 자리가 켜짐", word); seen = seen | 2; end
                default: $fatal(1, "an=%b (한 자리만 0이어야 함)", an);
            endcase
            if (dp !== 1'b1) $fatal(1, "dp가 켜짐");
        end
        if (seen != 3) $fatal(1, "자리 전환 없음");
        checks = checks + 1;
    end endtask
    initial begin
        want[0]=7'b1000000; want[1]=7'b1111001; want[2]=7'b0100100; want[3]=7'b0110000; want[4]=7'b0011001;
        want[5]=7'b0010010; want[6]=7'b0000010; want[7]=7'b1111000; want[8]=7'b0000000; want[9]=7'b0010000;
        for (k = 0; k < 10; k = k + 1) check_word(16'h8000 | (k << 10) | (1 << k), want[k]);
        check_word(16'hC000, 7'b0000110);      // 오류 → E
        check_word(16'h0000, 7'b0111111);      // 결과 없음 → -
        check_word(16'h8000 | (12 << 10), 7'b0111111);   // 범위 밖 번호 → -
        $display("RTL_SIM_PASS FND_CLASS_DISPLAY words=%0d", checks);
        $finish;
    end
endmodule
