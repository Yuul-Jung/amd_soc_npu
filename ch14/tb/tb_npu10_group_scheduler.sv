`timescale 1ns/1ps
// 14장 TB: 24개 사례(형판 0~9, 무작위 10, 동점·음수·9번 차선)를 적재·실행하고 점수·클래스를 파일로 돌려준다.
module tb_npu10_group_scheduler;
    localparam AW = 32;
    reg clk=0, rn=0, ls=0, iv=0, il=0, wwe=0, bwe=0, start=0;
    reg [7:0] id=0, wd=0; reg [3:0] wc=0, bc=0; reg [5:0] wa=0; reg [AW-1:0] bd=0;
    wire xl, xle, xre, busy, done, err; wire [3:0] cls; wire [10*AW-1:0] scores; wire [15:0] cycles;
    npu10_group_scheduler #(.ACC_WIDTH(AW)) dut(.clk(clk), .resetn(rn), .load_start_i(ls), .in_valid_i(iv),
        .in_data_i(id), .in_last_i(il), .x_loaded_o(xl), .x_len_err_o(xle), .x_range_err_o(xre),
        .w_wr_en_i(wwe), .w_class_i(wc), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe), .b_class_i(bc),
        .b_data_i(bd), .start_i(start), .busy_o(busy), .done_o(done), .error_o(err), .class_o(cls),
        .scores_o(scores), .cycles_o(cycles));
    always #5 clk = ~clk;

    integer f, o, n, expc, k, c, v, cases = 0, guards = 0;
    integer x [0:63]; integer w [0:9][0:63]; integer b [0:9];
    reg [8*24-1:0] name; string vp, ap;

    task load_x; integer s; begin
        @(negedge clk); ls = 1; @(negedge clk); ls = 0;
        for (s = 0; s < 64; s = s + 1) begin @(negedge clk); iv = 1; id = x[s]; il = (s == 63); end
        @(negedge clk); iv = 0; il = 0;
        if (!xl) $fatal(1, "입력 적재 실패");
    end endtask

    task load_model; integer cc, s; begin
        for (cc = 0; cc < 10; cc = cc + 1) begin
            for (s = 0; s < 64; s = s + 1) begin @(negedge clk); wwe = 1; wc = cc; wa = s; wd = w[cc][s]; end
            @(negedge clk); wwe = 0; bwe = 1; bc = cc; bd = b[cc];
        end
        @(negedge clk); bwe = 0;
        // 클래스 10·11 쓰기는 무시돼야 한다 (그룹 2 차선 2·3 주소)
        @(negedge clk); wwe = 1; wc = 10; wa = 0; wd = 8'h7f; @(negedge clk); wc = 11; @(negedge clk); wwe = 0;
    end endtask

    task run(output integer got_cycles); begin
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        if (!busy) $fatal(1, "start 후 busy 아님");
        // 실행 중 가중치·Bias 쓰기는 무시돼야 한다
        @(negedge clk); wwe = 1; wc = 8; wa = 5; wd = 8'h55; bwe = 1; bc = 9; bd = 32'h1234; @(negedge clk); wwe = 0; bwe = 0;
        while (!done) begin @(negedge clk); if (err) $fatal(1, "실행 중 error_o"); end
        if (busy) $fatal(1, "done 후 busy");
        got_cycles = cycles;
    end endtask

    initial begin
        integer cyc;
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        // 입력 적재 전 start → error_o, busy 아님
        @(negedge clk); start = 1; #1; @(posedge clk); #1;
        if (!err || busy) $fatal(1, "입력 없이 시작함"); guards = guards + 1;
        @(negedge clk); start = 0;
        while ($fscanf(f, "%d %d %s", n, expc, name) == 3) begin
            for (k = 0; k < 64; k = k + 1) if ($fscanf(f, "%d", x[k]) != 1) $fatal(1, "x 형식");
            for (c = 0; c < 10; c = c + 1) for (k = 0; k < 64; k = k + 1) begin if ($fscanf(f, "%d", v) != 1) $fatal(1, "w 형식"); w[c][k] = v; end
            for (c = 0; c < 10; c = c + 1) if ($fscanf(f, "%d", b[c]) != 1) $fatal(1, "b 형식");
            load_x; load_model; run(cyc);
            if (cls != expc) $fatal(1, "%s: class=%0d 기대 %0d", name, cls, expc);
            $fwrite(o, "%0d %0d", n, cls);
            for (c = 0; c < 10; c = c + 1) $fwrite(o, " %0d", $signed(scores[c*AW +: AW]));
            $fwrite(o, " %0d\n", cyc);
            cases = cases + 1;
        end
        // 실행 도중 새 입력 적재 시작 → 입력을 읽을 수 없으므로 error_o 후 IDLE
        load_x; @(negedge clk); start = 1; @(negedge clk); start = 0;
        repeat (40) @(negedge clk); ls = 1; @(negedge clk); ls = 0;
        k = 0; while (!err && k < 20) begin @(negedge clk); k = k + 1; end
        repeat (2) @(negedge clk);
        if (k >= 20 || busy) $fatal(1, "실행 중 적재 시작이 오류로 끝나지 않음"); guards = guards + 1;
        $display("RTL_SIM_PASS GROUP10 cases=%0d scores=%0d guards=%0d cycles_per_inference=%0d", cases, 10 * cases, guards, cyc);
        $fclose(o); $finish;
    end
    initial begin #50000000; $fatal(1, "시간 초과"); end
endmodule
