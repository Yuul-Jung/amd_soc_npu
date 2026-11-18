`timescale 1ns/1ps
// 18장 TB: DW(8·16)·AW를 바꿔 같은 실제 MNIST 정수 모델과 시험 20장을 돌린다.
// DW=8이면 17장 npu_tiled_784를 같은 데이터로 함께 돌려 점수가 같은지도 본다.
module tb_npu_precision;
    parameter integer DW = 8, AW = 32;
    reg clk=0, rn=0, xwe=0, wwe=0, bwe=0, start=0;
    reg [9:0] xa=0, wa=0; reg [DW-1:0] xd=0, wd=0; reg [3:0] wn=0, bn=0; reg [AW-1:0] bd=0;
    wire busy, done, err; wire [3:0] cls; wire [10*AW-1:0] scores; wire [15:0] cycles;
    npu_tiled_784_p #(.DATA_WIDTH(DW), .ACC_WIDTH(AW)) dut(.clk(clk), .resetn(rn), .x_wr_en_i(xwe), .x_addr_i(xa),
        .x_data_i(xd), .w_wr_en_i(wwe), .w_neuron_i(wn), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe), .b_neuron_i(bn),
        .b_data_i(bd), .start_i(start), .busy_o(busy), .scores_o(scores), .done_o(done), .error_o(err), .class_o(cls),
        .cycles_o(cycles));
    always #5 clk = ~clk;

    // DW=8: 17장 모듈과 교차 확인
    wire [10*AW-1:0] ref_scores; wire ref_done; wire [3:0] ref_cls;
    generate if (DW == 8) begin : cross_ch17
        npu_tiled_784 #(.ACC_WIDTH(AW)) ch17 (.clk(clk), .resetn(rn), .x_wr_en_i(xwe), .x_addr_i(xa), .x_data_i(xd),
            .w_wr_en_i(wwe), .w_neuron_i(wn), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe), .b_neuron_i(bn), .b_data_i(bd),
            .start_i(start), .busy_o(), .tile_done_o(), .tile_o(), .tile_done_num_o(), .tile_len_o(), .acc_o(),
            .scores_o(ref_scores), .done_o(ref_done), .error_o(), .class_o(ref_cls));
    end endgenerate

    integer f, o, k, c, v, n, label, cases = 0, cross_n = 0, cyc = 0;
    string vp, ap;

    initial begin
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        for (c = 0; c < 10; c = c + 1) for (k = 0; k < 784; k = k + 1) begin
            if ($fscanf(f, "%d", v) != 1) $fatal(1, "w"); @(negedge clk); wwe = 1; wn = c; wa = k; wd = v; end
        @(negedge clk); wwe = 0;
        for (c = 0; c < 10; c = c + 1) begin
            if ($fscanf(f, "%d", v) != 1) $fatal(1, "b"); @(negedge clk); bwe = 1; bn = c; bd = v; end
        @(negedge clk); bwe = 0;
        while ($fscanf(f, "%d %d", n, label) == 2) begin
            for (k = 0; k < 784; k = k + 1) begin
                if ($fscanf(f, "%d", v) != 1) $fatal(1, "x"); @(negedge clk); xwe = 1; xa = k; xd = v; end
            @(negedge clk); xwe = 0; start = 1; @(negedge clk); start = 0;
            while (!done) begin @(negedge clk); if (err) $fatal(1, "case %0d: error_o", n); end
            if (DW == 8) begin
                while (!ref_done) @(negedge clk);
                if (ref_scores !== scores || ref_cls !== cls) $fatal(1, "case %0d: 17장과 점수 다름", n);
                cross_n = cross_n + 1;
            end
            $fwrite(o, "%0d", n);
            for (c = 0; c < 10; c = c + 1) $fwrite(o, " %0d", $signed(scores[c*AW +: AW]));
            $fwrite(o, " %0d\n", cls);
            cases = cases + 1; cyc = cycles;
        end
        $display("RTL_SIM_PASS PRECISION int%0d acc=%0d cases=%0d cross_ch17=%0d cycles_per_inference=%0d", DW, AW, cases, cross_n, cyc);
        $fclose(o); $finish;
    end
    initial begin #500000000; $fatal(1, "시간 초과"); end
endmodule
