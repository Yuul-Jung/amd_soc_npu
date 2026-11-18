`timescale 1ns/1ps
// 29장 TB: 가상 센서 창 12개(상태별 2개씩, 애매함, 범위 밖, 고착, 순서 틀림)를 샘플 사이 빈 클록을 섞어 넣고 판정을 돌려준다.
module tb_sensor_guard_ai;
    reg clk=0, rn=0, sv=0, wwe=0, bwe=0;
    reg [1:0] sch=0; reg [11:0] sraw=0; reg [3:0] wn=0; reg [5:0] wa=0; reg [7:0] wd=0; reg [31:0] bd=0;
    wire [2:0] state, fault; wire [127:0] scores; wire done, busy;
    sensor_guard_ai dut(.clk(clk), .resetn(rn), .s_valid_i(sv), .s_ch_i(sch), .s_raw_i(sraw), .w_wr_en_i(wwe),
        .w_neuron_i(wn), .w_addr_i(wa), .w_data_i(wd), .b_wr_en_i(bwe), .b_data_i(bd),
        .state_o(state), .fault_o(fault), .scores_o(scores), .done_o(done), .busy_o(busy));
    always #5 clk = ~clk;
    integer f, o, n, k, c, v, r, cases = 0; reg [8*16-1:0] name; string vp, ap;
    initial begin
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        for (c = 0; c < 4; c = c + 1) for (k = 0; k < 64; k = k + 1) begin
            if ($fscanf(f, "%d", v) != 1) $fatal(1, "w"); @(negedge clk); wwe = 1; wn = c; wa = k; wd = v; end
        @(negedge clk); wwe = 0;
        for (c = 0; c < 4; c = c + 1) begin if ($fscanf(f, "%d", v) != 1) $fatal(1, "b"); @(negedge clk); bwe = 1; wn = c; bd = v; end
        @(negedge clk); bwe = 0;
        while ($fscanf(f, "%d %s", n, name) == 2) begin
            for (k = 0; k < 64; k = k + 1) begin
                if ($fscanf(f, "%d %d", c, r) != 2) $fatal(1, "샘플");
                if (k % 5 == 3) begin @(negedge clk); sv = 0; end   // 샘플 사이 빈 클록 (valid 내림)
                @(negedge clk); sv = 1; sch = c; sraw = r;
            end
            @(negedge clk); sv = 0;
            while (!done) @(negedge clk);
            $fwrite(o, "%0d %0d %0d", n, state, fault);
            for (c = 0; c < 4; c = c + 1) $fwrite(o, " %0d", state == 5 ? 0 : $signed(scores[c*32 +: 32]));
            $fwrite(o, "\n"); cases = cases + 1;
        end
        $display("RTL_SIM_PASS SENSOR_GUARD cases=%0d", cases);
        $fclose(o); $finish;
    end
    initial begin #50000000; $fatal(1, "시간 초과"); end
endmodule
