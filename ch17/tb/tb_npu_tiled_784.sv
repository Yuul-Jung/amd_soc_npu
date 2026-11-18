`timescale 1ns/1ps
// 17장 TB: 6사례에서 타일 13개의 순서·길이(64×12, 16)·누계와 최종 점수·클래스를 파일로 돌려준다.
module tb_npu_tiled_784;
    localparam AW = 32;
    reg clk=0, rn=0, xwe=0, wwe=0, bwe=0, start=0;
    reg [9:0] xa=0, wa=0; reg [7:0] xd=0, wd=0; reg [3:0] wn=0, bn=0; reg [AW-1:0] bd=0;
    wire busy, td, done, err; wire [3:0] tile, tdn, cls; wire [6:0] tlen;
    wire [10*AW-1:0] acc, scores;
    npu_tiled_784 #(.ACC_WIDTH(AW)) dut(.clk(clk), .resetn(rn), .x_wr_en_i(xwe), .x_addr_i(xa), .x_data_i(xd),
        .w_wr_en_i(wwe), .w_neuron_i(wn), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe), .b_neuron_i(bn), .b_data_i(bd),
        .start_i(start), .busy_o(busy), .tile_done_o(td), .tile_o(tile), .tile_done_num_o(tdn), .tile_len_o(tlen),
        .acc_o(acc), .scores_o(scores), .done_o(done), .error_o(err), .class_o(cls));
    always #5 clk = ~clk;

    integer f, o, n, k, c, v, cases = 0, tiles_seen, expect_tile, len_sum;
    reg [8*16-1:0] name; string vp, ap;

    // 타일 완료마다 번호·누계 기록, 번호는 0부터 1씩 늘어야 한다
    always @(posedge clk) if (td) begin
        if (tdn != expect_tile) $fatal(1, "타일 순서 %0d, 기대 %0d", tdn, expect_tile);
        #1 $fwrite(o, "%0d T%0d %0d", n, tdn, tdn);
        for (c = 0; c < 10; c = c + 1) $fwrite(o, " %0d", $signed(acc[c*AW +: AW]));
        $fwrite(o, "\n"); expect_tile = expect_tile + 1; tiles_seen = tiles_seen + 1;
    end
    // 코어가 받은 길이 합 = 784 (타일 시작 시점의 tile_len_o 누적)
    always @(posedge clk) if (dut.state == 1) len_sum = len_sum + tlen;

    initial begin
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        while ($fscanf(f, "%d %s", n, name) == 2) begin
            for (k = 0; k < 784; k = k + 1) begin
                if ($fscanf(f, "%d", v) != 1) $fatal(1, "x"); @(negedge clk); xwe = 1; xa = k; xd = v; end
            @(negedge clk); xwe = 0;
            for (c = 0; c < 10; c = c + 1) for (k = 0; k < 784; k = k + 1) begin
                if ($fscanf(f, "%d", v) != 1) $fatal(1, "w"); @(negedge clk); wwe = 1; wn = c; wa = k; wd = v; end
            @(negedge clk); wwe = 0;
            for (c = 0; c < 10; c = c + 1) begin
                if ($fscanf(f, "%d", v) != 1) $fatal(1, "b"); @(negedge clk); bwe = 1; bn = c; bd = v; end
            @(negedge clk); bwe = 0;
            tiles_seen = 0; expect_tile = 0; len_sum = 0;
            @(negedge clk); start = 1; @(negedge clk); start = 0;
            @(negedge clk); xwe = 1; xa = 770; xd = 8'h7f; @(negedge clk); xwe = 0;   // 실행 중 쓰기 → 무시
            while (!done) begin @(negedge clk); if (err) $fatal(1, "%s: error_o", name); end
            if (tiles_seen != 13 || len_sum != 784) $fatal(1, "%s: 타일 %0d개, 길이 합 %0d", name, tiles_seen, len_sum);
            $fwrite(o, "%0d S", n);
            for (c = 0; c < 10; c = c + 1) $fwrite(o, " %0d", $signed(scores[c*AW +: AW]));
            $fwrite(o, " %0d\n", cls);
            cases = cases + 1;
        end
        $display("RTL_SIM_PASS TILED784 cases=%0d tiles=13 len_sum=784", cases);
        $fclose(o); $finish;
    end
    initial begin #200000000; $fatal(1, "시간 초과"); end
endmodule
