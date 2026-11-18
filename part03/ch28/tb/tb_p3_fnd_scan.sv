// (추가) 28장: FND 스캔 시험. Python(digit_reference.fnd_segments)이 만든 (워드, 자리) → (an, seg, dp) 기대값과
// 핀 값을 비교한다. 각 자리 구간 한가운데에서 표본을 잡고, 자리 순서 0→1→2→3 반복과 Reset 출력(모두 꺼짐)도 확인한다.
`timescale 1ns/1ps
module tb_p3_fnd_scan;
    localparam integer DIV_W = 3;          // 자리당 8클록
    reg clk = 0, resetn = 0;
    reg [31:0] word = 0;
    wire [6:0] seg;
    wire dp;
    wire [3:0] an;
    always #5 clk = ~clk;
    p3_fnd_scan #(.DIV_W(DIV_W)) dut(.clk(clk), .resetn(resetn), .word_i(word), .seg_o(seg), .dp_o(dp), .an_o(an));

    reg [8*256-1:0] path;
    integer fd, rc, n = 0, bad = 0, d, k, dig, cyc;
    reg [31:0] w;
    reg [3:0] e_an;
    reg [7:0] e_seg;
    reg e_dp;
    initial begin
        if (!$value$plusargs("VEC=%s", path)) $fatal(1, "+VEC required");
        repeat (3) @(negedge clk);
        if (seg !== 7'h7F || an !== 4'hF || dp !== 1'b1) $fatal(1, "reset outputs not blank");
        resetn = 1;
        fd = $fopen(path, "r");
        rc = $fscanf(fd, "%h %d %h %h %d\n", w, d, e_an, e_seg, e_dp);
        while (rc == 5) begin
            word = w;
            // 카운터가 자리 d의 구간 가운데(등록 출력 1클록 지연 포함)에 올 때까지 기다린다
            cyc = 0;
            while (!(dut.cnt_q[DIV_W+1:DIV_W] == d[1:0] && dut.cnt_q[DIV_W-1:0] == 4)) begin
                @(negedge clk);
                cyc = cyc + 1;
                if (cyc > 64) $fatal(1, "scan counter stuck");
            end
            @(negedge clk);
            if (an !== e_an || seg !== e_seg[6:0] || dp !== e_dp) begin
                bad = bad + 1;
                $display("MISMATCH word=%h digit=%0d an=%b/%b seg=%h/%h dp=%b/%b", w, d, an, e_an, seg, e_seg, dp, e_dp);
            end
            n = n + 1;
            rc = $fscanf(fd, "%h %d %h %h %d\n", w, d, e_an, e_seg, e_dp);
        end
        // 자리 순서: 한 주기 동안 켜진 an이 0→1→2→3 순서로 바뀌는지
        word = 32'h000F_0000;
        @(negedge clk);
        dig = -1; k = 0;
        repeat (4 * (1 << DIV_W) * 2) begin
            @(negedge clk);
            if (an != 4'hF) begin
                for (d = 0; d < 4; d = d + 1)
                    if (an == ~(4'b0001 << d) && d != dig) begin
                        if (dig >= 0 && d != (dig + 1) % 4) bad = bad + 1;
                        dig = d; k = k + 1;
                    end
            end
        end
        if (k < 7) bad = bad + 1;
        if (bad) $fatal(1, "FND scan failed bad=%0d", bad);
        $display("RTL_SIM_PASS FND_SCAN vectors=%0d digit_changes=%0d", n, k);
        $finish;
    end
endmodule
