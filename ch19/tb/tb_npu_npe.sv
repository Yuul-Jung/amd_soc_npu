`timescale 1ns/1ps
// 19장 TB: NPE(1·2·4·8)를 바꿔 18장 INT8 실제 MNIST 모델·시험 5장을 돌리고 점수·클래스·사이클을 돌려준다.
// NPE=4이면 18장 npu_tiled_784_p(DW=8)를 함께 돌려 점수가 같은지 보고, 18장 사이클도 함께 출력한다.
module tb_npu_npe;
    parameter integer NPE = 4;
    localparam AW = 32;
    reg clk=0, rn=0, xwe=0, wwe=0, bwe=0, start=0;
    reg [9:0] xa=0, wa=0; reg [7:0] xd=0, wd=0; reg [3:0] wn=0, bn=0; reg [AW-1:0] bd=0;
    wire busy, done, err; wire [3:0] cls; wire [10*AW-1:0] scores; wire [15:0] cycles;
    npu_tiled_784_npe #(.NPE(NPE), .ACC_WIDTH(AW)) dut(.clk(clk), .resetn(rn), .x_wr_en_i(xwe), .x_addr_i(xa),
        .x_data_i(xd), .w_wr_en_i(wwe), .w_neuron_i(wn), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe), .b_neuron_i(bn),
        .b_data_i(bd), .start_i(start), .busy_o(busy), .scores_o(scores), .done_o(done), .error_o(err), .class_o(cls),
        .cycles_o(cycles));
    always #5 clk = ~clk;

    wire [10*AW-1:0] ref_scores; wire ref_done; wire [15:0] ref_cycles;
    generate if (NPE == 4) begin : same_as_ch18
        npu_tiled_784_p #(.DATA_WIDTH(8), .ACC_WIDTH(AW)) ch18 (.clk(clk), .resetn(rn), .x_wr_en_i(xwe), .x_addr_i(xa),
            .x_data_i(xd), .w_wr_en_i(wwe), .w_neuron_i(wn), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe),
            .b_neuron_i(bn), .b_data_i(bd), .start_i(start), .busy_o(), .scores_o(ref_scores), .done_o(ref_done),
            .error_o(), .class_o(), .cycles_o(ref_cycles));
    end endgenerate

    integer f, o, k, c, v, n, label, cases = 0, same = 0, cyc = 0, ref_cyc = 0;
    reg ref_seen = 0;
    always @(posedge clk) if (start) ref_seen <= 0; else if (ref_done) ref_seen <= 1;
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
            if (NPE == 4) begin
                while (!ref_seen) @(negedge clk);
                if (ref_scores !== scores) $fatal(1, "case %0d: 18장과 점수 다름", n);
                same = same + 1; ref_cyc = ref_cycles;
            end
            $fwrite(o, "%0d", n);
            for (c = 0; c < 10; c = c + 1) $fwrite(o, " %0d", $signed(scores[c*AW +: AW]));
            $fwrite(o, " %0d\n", cls);
            cases = cases + 1; cyc = cycles;
        end
        if (NPE == 4) $display("CH18_DW8_CYCLES %0d (pe_array4의 완료 레지스터 때문에 그룹마다 2클록 더 걸림)", ref_cyc);
        $display("RTL_SIM_PASS NPE=%0d cases=%0d same_as_ch18=%0d cycles=%0d", NPE, cases, same, cyc);
        $fclose(o); $finish;
    end
    initial begin #900000000; $fatal(1, "시간 초과"); end
endmodule
