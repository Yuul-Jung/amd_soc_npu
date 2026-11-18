`timescale 1ns/1ps
// 13장 TB: 64원소 10샘플 적재·임의 순서 읽기, 길이·범위 오류 4종과 복구를 자동 판정한다.
module tb_npu10_input_loader;
    reg clk=0, rn=0, start=0, iv=0, il=0, re=0;
    reg [7:0] id=0; reg [5:0] ra=0;
    wire signed [7:0] rd; wire rv, loading, loaded, len_err, range_err; wire [6:0] count;
    npu10_input_loader dut(.clk(clk), .resetn(rn), .load_start_i(start), .in_valid_i(iv),
        .in_data_i(id), .in_last_i(il), .rd_en_i(re), .rd_addr_i(ra), .rd_data_o(rd),
        .rd_valid_o(rv), .loading_o(loading), .loaded_o(loaded), .len_err_o(len_err),
        .range_err_o(range_err), .count_o(count));
    always #5 clk = ~clk;

    reg [7:0] x [0:63], got [0:63];
    reg [15:0] lfsr = 16'hACE1;
    integer f, o, label, k, n = 0, reads = 0, errs = 0;
    string vp, ap;

    task pulse_start; begin
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        if (!loading || count != 0 || len_err || range_err) $fatal(1, "load_start 후 LOAD·count=0이 아님");
    end endtask

    // 원소 n개를 보낸다. last_at = in_last를 올릴 순번(-1이면 올리지 않음), 사이사이 빈 클록을 넣는다.
    task send(input integer cnt, input integer last_at); integer s; begin
        for (s = 0; s < cnt; s = s + 1) begin
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            if (lfsr[0]) begin @(negedge clk); iv = 0; end
            @(negedge clk); iv = 1; id = x[s]; il = (s == last_at);
            if (s < 64) begin re = 1; ra = s[5:0]; end          // 적재 중 읽기 요청 → 무시돼야 함
        end
        @(negedge clk); iv = 0; il = 0; re = 0;
        if (rv) $fatal(1, "적재 완료 전 읽기가 rd_valid를 냄");
    end endtask

    task read_all; integer a, s; begin
        for (s = 0; s < 64; s = s + 1) begin
            a = (s * 29 + 7) % 64;                                // 주소를 섞어 순차 읽기에 기대지 않는다
            @(negedge clk); re = 1; ra = a;
            @(negedge clk); re = 0;
            if (!rv) $fatal(1, "rd_valid 없음 addr=%0d", a);
            got[a] = rd; reads = reads + 1;
        end
    end endtask

    task expect_error(input string what, input reg want_len, input reg want_range); begin
        @(negedge clk);
        if (len_err !== want_len || range_err !== want_range || loaded)
            $fatal(1, "%s: len_err=%b range_err=%b loaded=%b", what, len_err, range_err, loaded);
        @(negedge clk); re = 1; ra = 0; @(negedge clk); re = 0;
        if (rv) $fatal(1, "%s: 오류 상태에서 읽기가 허용됨", what);
        errs = errs + 1;
    end endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        while ($fscanf(f, "%d", label) == 1) begin
            for (k = 0; k < 64; k = k + 1) if ($fscanf(f, "%h", x[k]) != 1) $fatal(1, "벡터 형식");
            pulse_start; send(64, 63);
            if (!loaded || count != 64 || len_err || range_err) $fatal(1, "label=%0d 적재 실패", label);
            read_all;
            $fwrite(o, "%0d", label);
            for (k = 0; k < 64; k = k + 1) $fwrite(o, " %02h", got[k]);
            $fwrite(o, "\n"); n = n + 1;
        end
        // 오류 4종: 마지막 표시가 이름, 마지막 표시 없음, 완료 뒤 추가 원소, 부호 비트 1
        pulse_start; send(10, 9);  expect_error("EARLY_LAST", 1, 0);
        pulse_start; send(64, -1); expect_error("MISSING_LAST", 1, 0);
        pulse_start; send(64, 63); if (!loaded) $fatal(1, "재적재 실패");
        @(negedge clk); iv = 1; id = 8'h01; @(negedge clk); iv = 0;
        expect_error("EXTRA_AFTER_DONE", 1, 0);
        pulse_start; x[5] = 8'h80; send(6, -1); expect_error("NEGATIVE_VALUE", 0, 1);
        // 적재 도중 리셋 → IDLE, 이후 정상 재적재
        x[5] = 8'h05; pulse_start; send(20, -1);
        @(negedge clk); rn = 0; @(negedge clk); rn = 1; @(negedge clk);
        if (loading || loaded || count != 0) $fatal(1, "리셋 후 IDLE 아님");
        pulse_start; send(64, 63); if (!loaded) $fatal(1, "리셋 후 재적재 실패");
        $display("RTL_SIM_PASS INPUT_LOADER samples=%0d reads=%0d error_cases=%0d", n, reads, errs);
        $fclose(o); $finish;
    end
    initial begin #2000000; $fatal(1, "시간 초과"); end
endmodule
