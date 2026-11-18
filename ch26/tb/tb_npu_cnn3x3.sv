`timescale 1ns/1ps
// 26장 TB: 12사례(경계 필터 숫자 5개, 무작위 필터 5개, ReLU 전부 0, 포화)의 풀링 36개·점수 10개·클래스를 돌려준다.
module tb_npu_cnn3x3;
    reg clk=0, rn=0, xwe=0, kwe=0, kbwe=0, dwe=0, dbwe=0, start=0;
    reg [5:0] xa=0, da=0; reg [7:0] xd=0, kd=0, dd=0; reg [1:0] kf=0, kbf=0; reg [3:0] ka=0, dn=0;
    reg [31:0] kbd=0, dbd=0;
    wire busy, done, err; wire [287:0] pooled; wire [319:0] scores; wire [3:0] cls;
    npu_cnn3x3 #(.SHIFT(6)) dut(.clk(clk), .resetn(rn), .x_wr_en_i(xwe), .x_addr_i(xa), .x_data_i(xd),
        .k_wr_en_i(kwe), .k_filter_i(kf), .k_addr_i(ka), .k_data_i(kd), .kb_wr_en_i(kbwe), .kb_filter_i(kbf), .kb_data_i(kbd),
        .d_w_wr_en_i(dwe), .d_neuron_i(dn), .d_addr_i(da), .d_data_i(dd), .d_b_wr_en_i(dbwe), .d_b_data_i(dbd),
        .start_i(start), .busy_o(busy), .pooled_o(pooled), .scores_o(scores), .done_o(done), .error_o(err), .class_o(cls));
    always #5 clk = ~clk;

    integer f, o, n, k, c, v, cases = 0, cyc;
    reg [8*16-1:0] name; string vp, ap;
    task rdv(output integer r); begin if ($fscanf(f, "%d", r) != 1) $fatal(1, "벡터 형식"); end endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        while ($fscanf(f, "%d %s", n, name) == 2) begin
            for (k = 0; k < 64; k = k + 1) begin rdv(v); @(negedge clk); xwe = 1; xa = k; xd = v; end
            @(negedge clk); xwe = 0;
            for (c = 0; c < 4; c = c + 1) for (k = 0; k < 9; k = k + 1) begin rdv(v); @(negedge clk); kwe = 1; kf = c; ka = k; kd = v; end
            @(negedge clk); kwe = 0;
            for (c = 0; c < 4; c = c + 1) begin rdv(v); @(negedge clk); kbwe = 1; kbf = c; kbd = v; end
            @(negedge clk); kbwe = 0;
            for (c = 0; c < 10; c = c + 1) for (k = 0; k < 64; k = k + 1) begin rdv(v); @(negedge clk); dwe = 1; dn = c; da = k; dd = v; end
            @(negedge clk); dwe = 0;
            for (c = 0; c < 10; c = c + 1) begin rdv(v); @(negedge clk); dbwe = 1; dn = c; dbd = v; end
            @(negedge clk); dbwe = 0;
            @(negedge clk); start = 1; @(negedge clk); start = 0; cyc = 1;
            @(negedge clk); xwe = 1; xa = 0; xd = 8'h55; @(negedge clk); xwe = 0;   // 실행 중 쓰기 → 무시
            while (!done) begin @(negedge clk); cyc = cyc + 1; if (err) $fatal(1, "%s: error_o", name); end
            $fwrite(o, "%0d", n);
            for (c = 0; c < 36; c = c + 1) $fwrite(o, " %0d", $signed(pooled[c*8 +: 8]));
            for (c = 0; c < 10; c = c + 1) $fwrite(o, " %0d", $signed(scores[c*32 +: 32]));
            $fwrite(o, " %0d\n", cls);
            cases = cases + 1;
        end
        $display("RTL_SIM_PASS CNN3X3 cases=%0d cycles_per_inference=%0d", cases, cyc);
        $fclose(o); $finish;
    end
    initial begin #100000000; $fatal(1, "시간 초과"); end
endmodule
