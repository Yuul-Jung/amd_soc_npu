`timescale 1ns/1ps
// 15장 TB: N_IN·N_OUT을 바꿔 (64→10, 64→8, 8→10) 같은 Dense 층을 시험한다.
// 입력 x는 TB 메모리(1클록 지연)가 공급하고, 점수와 적재 검증합을 파일로 돌려준다.
module tb_npu_dense;
    parameter integer N_IN = 64, N_OUT = 10;
    localparam AW = 32;
    reg clk=0, rn=0, mc=0, wwe=0, bwe=0, start=0, drop=0;
    reg [3:0] wn=0, bn=0; reg [5:0] wa=0; reg [7:0] wd=0; reg [AW-1:0] bd=0;
    reg signed [7:0] xd=0; reg xv=0;
    wire xre, busy, done, err, merr; wire [5:0] xi; wire [31:0] msum; wire [N_OUT*AW-1:0] scores;
    npu_dense #(.N_IN(N_IN), .N_OUT(N_OUT), .ACC_WIDTH(AW)) dut(.clk(clk), .resetn(rn), .model_clear_i(mc),
        .w_wr_en_i(wwe), .w_neuron_i(wn), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe), .b_neuron_i(bn), .b_data_i(bd),
        .model_sum_o(msum), .model_err_o(merr), .x_rd_en_o(xre), .x_rd_idx_o(xi), .x_data_i(xd), .x_valid_i(xv),
        .start_i(start), .busy_o(busy), .done_o(done), .error_o(err), .scores_o(scores));
    always #5 clk = ~clk;

    integer x [0:63]; integer w [0:15][0:63]; integer b [0:15];
    integer f, o, n, k, c, v, cases = 0, guards = 0;
    reg [8*16-1:0] name; string vp, ap;

    // 입력 메모리: 읽기 요청 다음 클록에 데이터 (drop=1이면 한 번 응답하지 않음)
    always @(posedge clk) begin
        xv <= xre && !drop; if (xre) xd <= x[xi];
    end

    task load_model; integer cc, s; begin
        @(negedge clk); mc = 1; @(negedge clk); mc = 0;
        for (cc = 0; cc < N_OUT; cc = cc + 1) begin
            for (s = 0; s < N_IN; s = s + 1) begin @(negedge clk); bwe = 0; wwe = 1; wn = cc; wa = s; wd = w[cc][s]; end
            @(negedge clk); wwe = 0; bwe = 1; bn = cc; bd = b[cc];
        end
        @(negedge clk); bwe = 0;
        if (merr) $fatal(1, "정상 적재에서 model_err");
    end endtask

    task run; begin
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        if (!busy) $fatal(1, "start 후 busy 아님");
        @(negedge clk); wwe = 1; wn = N_OUT - 1; wa = N_IN - 1; wd = 8'h55; bwe = 1; bn = 0; bd = 32'h777; start = 1;
        @(negedge clk); wwe = 0; bwe = 0; start = 0;              // 실행 중 쓰기·재시작은 무시돼야 함
        while (!done) begin @(negedge clk); if (err) $fatal(1, "실행 중 error_o"); end
    end endtask

    initial begin
        reg [31:0] sum0;
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        while ($fscanf(f, "%d %s", n, name) == 2) begin
            for (k = 0; k < N_IN; k = k + 1) begin if ($fscanf(f, "%d", v) != 1) $fatal(1, "x"); x[k] = v; end
            for (c = 0; c < N_OUT; c = c + 1) for (k = 0; k < N_IN; k = k + 1) begin
                if ($fscanf(f, "%d", v) != 1) $fatal(1, "w"); w[c][k] = v; end
            for (c = 0; c < N_OUT; c = c + 1) begin if ($fscanf(f, "%d", v) != 1) $fatal(1, "b"); b[c] = v; end
            load_model;
            sum0 = msum; run;
            if (msum !== sum0) $fatal(1, "실행 중 쓰기가 검증합을 바꿈");
            $fwrite(o, "%0d", n);
            for (c = 0; c < N_OUT; c = c + 1) $fwrite(o, " %0d", $signed(scores[c*AW +: AW]));
            $fwrite(o, " %0d\n", msum);
            cases = cases + 1;
        end
        // 범위 밖 쓰기: 뉴런 N_OUT → 무시 + model_err, 검증합 그대로
        sum0 = msum;
        @(negedge clk); wwe = 1; wn = N_OUT; wa = 0; wd = 8'h11; @(negedge clk); wwe = 0; @(negedge clk);
        if (!merr || msum !== sum0) $fatal(1, "범위 밖 쓰기 검출 실패"); guards = guards + 1;
        // 입력 응답 없음 → error_o, busy 해제
        drop = 1; @(negedge clk); start = 1; @(negedge clk); start = 0;
        k = 0; while (!err && k < 10) begin @(negedge clk); k = k + 1; end
        drop = 0; @(negedge clk);
        if (k >= 10 || busy) $fatal(1, "입력 응답 없음 검출 실패"); guards = guards + 1;
        $display("RTL_SIM_PASS DENSE cfg=%0dx%0d cases=%0d guards=%0d", N_IN, N_OUT, cases, guards);
        $fclose(o); $finish;
    end
    initial begin #20000000; $fatal(1, "시간 초과"); end
endmodule
