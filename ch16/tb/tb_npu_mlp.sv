`timescale 1ns/1ps
// 16장 TB: 11사례(숫자 8개, 포화, ReLU 전부 0, 반올림 0.5)로 은닉 8개·점수 10개·클래스·포화 표시를 돌려준다.
module tb_npu_mlp;
    localparam AW = 32;
    reg clk=0, rn=0, mc=0, wl=0, wwe=0, bwe=0, start=0, drop=0;
    reg [3:0] wn=0, bn=0; reg [5:0] wa=0; reg [7:0] wd=0; reg [AW-1:0] bd=0;
    reg signed [7:0] xd=0; reg xv=0;
    wire xre, busy, hv, hsat, done, err, merr; wire [5:0] xi; wire [31:0] msum;
    wire [63:0] hid; wire [10*AW-1:0] scores; wire [3:0] cls;
    npu_mlp_64_8_10 #(.ACC_WIDTH(AW), .SHIFT(10)) dut(.clk(clk), .resetn(rn), .model_clear_i(mc), .w_layer_i(wl),
        .w_wr_en_i(wwe), .w_neuron_i(wn), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe), .b_neuron_i(bn), .b_data_i(bd),
        .model_sum_o(msum), .model_err_o(merr), .x_rd_en_o(xre), .x_rd_idx_o(xi), .x_data_i(xd), .x_valid_i(xv),
        .start_i(start), .busy_o(busy), .hidden_valid_o(hv), .hidden_o(hid), .hidden_sat_o(hsat),
        .scores_o(scores), .done_o(done), .error_o(err), .class_o(cls));
    always #5 clk = ~clk;

    integer x [0:63]; integer w1 [0:7][0:63]; integer b1 [0:7]; integer w2 [0:9][0:7]; integer b2 [0:9];
    integer f, o, n, k, c, v, cases = 0, guards = 0, hv_count;
    reg [8*16-1:0] name; string vp, ap;
    reg [63:0] hid_at_valid;

    always @(posedge clk) begin xv <= xre && !drop; if (xre) xd <= x[xi]; end
    always @(posedge clk) if (hv) begin hv_count = hv_count + 1; hid_at_valid = hid; end

    task rdv(output integer r); begin if ($fscanf(f, "%d", r) != 1) $fatal(1, "벡터 형식"); end endtask

    task wr_w(input l, input [3:0] nn, input [5:0] aa, input integer vv); begin
        @(negedge clk); bwe = 0; wl = l; wwe = 1; wn = nn; wa = aa; wd = vv; end endtask
    task wr_b(input l, input [3:0] nn, input integer vv); begin
        @(negedge clk); wwe = 0; wl = l; bwe = 1; bn = nn; bd = vv; end endtask

    task load_model; integer cc, s; begin
        @(negedge clk); mc = 1; @(negedge clk); mc = 0;
        for (cc = 0; cc < 8; cc = cc + 1) begin for (s = 0; s < 64; s = s + 1) wr_w(0, cc, s, w1[cc][s]); wr_b(0, cc, b1[cc]); end
        for (cc = 0; cc < 10; cc = cc + 1) begin for (s = 0; s < 8; s = s + 1) wr_w(1, cc, s, w2[cc][s]); wr_b(1, cc, b2[cc]); end
        @(negedge clk); wwe = 0; bwe = 0;
        if (merr) $fatal(1, "정상 적재에서 model_err");
    end endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        while ($fscanf(f, "%d %s", n, name) == 2) begin
            for (k = 0; k < 64; k = k + 1) rdv(x[k]);
            for (c = 0; c < 8; c = c + 1) for (k = 0; k < 64; k = k + 1) begin rdv(v); w1[c][k] = v; end
            for (c = 0; c < 8; c = c + 1) rdv(b1[c]);
            for (c = 0; c < 10; c = c + 1) for (k = 0; k < 8; k = k + 1) begin rdv(v); w2[c][k] = v; end
            for (c = 0; c < 10; c = c + 1) rdv(b2[c]);
            load_model;
            hv_count = 0;
            @(negedge clk); start = 1; @(negedge clk); start = 0;
            if (!busy) $fatal(1, "start 후 busy 아님");
            wr_w(1, 0, 0, 99); @(negedge clk); wwe = 0;                 // 실행 중 쓰기 → 무시
            while (!done) begin @(negedge clk); if (err) $fatal(1, "%s: error_o", name); end
            if (hv_count != 1 || hid_at_valid !== hid) $fatal(1, "%s: hidden_valid 펄스 %0d회", name, hv_count);
            $fwrite(o, "%0d", n);
            for (c = 0; c < 8; c = c + 1) $fwrite(o, " %0d", $signed(hid[c*8 +: 8]));
            for (c = 0; c < 10; c = c + 1) $fwrite(o, " %0d", $signed(scores[c*AW +: AW]));
            $fwrite(o, " %0d %0d %0d\n", cls, hsat, msum);
            cases = cases + 1;
        end
        // 입력 응답 없음 → 1층 오류가 error_o로 올라오고 IDLE
        drop = 1; @(negedge clk); start = 1; @(negedge clk); start = 0;
        k = 0; while (!err && k < 10) begin @(negedge clk); k = k + 1; end
        drop = 0; @(negedge clk);
        if (k >= 10 || busy) $fatal(1, "1층 오류 전달 실패"); guards = guards + 1;
        $display("RTL_SIM_PASS MLP_64_8_10 cases=%0d guards=%0d", cases, guards);
        $fclose(o); $finish;
    end
    initial begin #50000000; $fatal(1, "시간 초과"); end
endmodule
