// (추가) 26장 p3_conv3x3_8x8 자동 판정 TB. 프레임마다 커널·Bias를 쓰고 64픽셀을 LFSR 버블과 함께 보낸다.
// 출력 36개의 값(행 우선)을 actual에 기록(Python 비교). 상시 검사: 출력 위치 순서·out_last·지연 3클록·처리량.
// 추가: 프레임 붙여 보내기(버블 없음), 짧은·긴 프레임 재동기, 프레임 중 커널 쓰기 거부, 잘못된 커널 주소, 프레임 중 Reset.
`timescale 1ns/1ps
module tb_p3_conv3x3_8x8;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    reg signed [7:0] pix = 0;
    reg pv = 0, plast = 0, kwr = 0, bwr = 0, relu = 0;
    reg [3:0] kaddr = 0;
    reg signed [7:0] kdata = 0;
    reg signed [23:0] bdata = 0;
    wire ready, ov, olast, err;
    wire signed [24:0] od;
    wire [2:0] orow, ocol;
    p3_conv3x3_8x8 dut(.clk(clk), .resetn(resetn), .pix_i(pix), .pix_valid_i(pv), .pix_last_i(plast),
        .k_wr_en_i(kwr), .k_addr_i(kaddr), .k_data_i(kdata), .b_wr_en_i(bwr), .b_data_i(bdata),
        .relu_en_i(relu), .load_ready_o(ready), .out_o(od), .out_valid_o(ov), .out_row_o(orow),
        .out_col_o(ocol), .out_last_o(olast), .error_o(err));

    // 상시 검사·기록
    integer cyc = 0, nout = 0, n_err = 0, rec = 1, af, acc_cyc [0:63], lat = -1;
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge clk) begin
        cyc = cyc + 1;
        if (resetn) begin
            if (pv && !dut.drop_q) acc_cyc[{dut.row_q, dut.col_q}] = cyc;   // 프레임 안 픽셀 번호 = 8r + c
            if (err) n_err = n_err + 1;
            if (ov) begin
                if (orow != nout / 6 || ocol != nout % 6) $fatal(1, "output order (%0d,%0d) at %0d", orow, ocol, nout);
                if (olast != (nout == 35)) $fatal(1, "out_last wrong at %0d", nout);
                // 출력 (r-2, c-2) ← 입력 픽셀 번호 8(r)+c 수락 후 3클록
                if (lat < 0) lat = cyc - acc_cyc[((nout / 6) + 2) * 8 + (nout % 6) + 2];
                else if (cyc - acc_cyc[((nout / 6) + 2) * 8 + (nout % 6) + 2] != lat) $fatal(1, "latency changed");
                if (rec) $fwrite(af, "%0d%s", od, (nout == 35) ? "\n" : " ");
                nout = (nout == 35) ? 0 : nout + 1;
            end
        end
    end

    integer vf, rc, nf, f, i, tmp, err_before;
    integer K [0:8];
    integer IMG [0:63];
    integer B, R;
    reg [8*256-1:0] vpath, apath;
    task automatic load_kernel;
        begin
            while (!ready) @(negedge clk);
            for (i = 0; i < 9; i = i + 1) begin
                @(negedge clk); kwr = 1; kaddr = i; kdata = K[i];
            end
            @(negedge clk); kwr = 0; bwr = 1; bdata = B;
            @(negedge clk); bwr = 0;
        end
    endtask
    // n: 보낼 픽셀 수, last_at: last를 붙일 번호(-1이면 없음), bubbles: LFSR 버블
    task automatic send(input integer n, input integer last_at, input integer bubbles);
        integer j;
        begin
            for (j = 0; j < n; j = j + 1) begin
                @(negedge clk);
                if (bubbles) begin
                    lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                    while (lfsr[1:0] == 2'b00) begin
                        pv = 0;
                        @(negedge clk);
                        lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                    end
                end
                pix = IMG[j % 64]; pv = 1; plast = (j == last_at); relu = R;
            end
            @(negedge clk);
            pv = 0; plast = 0;
        end
    endtask
    task automatic drain;
        begin repeat (8) @(negedge clk); end
    endtask
    task automatic expect_err(input integer k, input [8*32-1:0] what);
        begin
            drain;
            if (n_err != err_before + k) $fatal(1, "error count %0d != %0d: %0s", n_err - err_before, k, what);
            err_before = n_err;
            nout = 0;     // 오류 프레임의 출력(긴 프레임은 64번째 창을 버려 35개)은 검증·기록하지 않는다
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vpath)) $fatal(1, "+VECTORS required");
        if (!$value$plusargs("ACTUAL=%s", apath)) $fatal(1, "+ACTUAL required");
        vf = $fopen(vpath, "r");
        af = $fopen(apath, "w");
        rc = $fscanf(vf, "%d", nf);
        repeat (3) @(negedge clk);
        resetn = 1;
        @(negedge clk);
        err_before = 0;
        for (f = 0; f < nf; f = f + 1) begin
            rc = $fscanf(vf, "%d", R);
            rc = $fscanf(vf, "%d", B);
            for (i = 0; i < 9; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); K[i] = tmp; end
            for (i = 0; i < 64; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); IMG[i] = tmp; end
            load_kernel;
            if (f == 0) begin
                // 오류 시나리오(기록 안 함): 짧은 프레임, 긴 프레임, 잘못된 커널 주소, 프레임 중 커널 쓰기, Reset
                rec = 0;
                send(10, 9, 0);
                expect_err(1, "short frame");
                send(67, 66, 0);               // 64번째 last 없음 → 오류, 66번째 last까지 버림
                expect_err(1, "long frame");
                @(negedge clk); kwr = 1; kaddr = 9; kdata = 1;
                @(negedge clk); kwr = 0;
                expect_err(1, "kernel address 9");
                fork
                    send(64, 63, 1);
                    begin repeat (20) @(negedge clk); kwr = 1; kaddr = 0; kdata = 99; @(negedge clk); kwr = 0; end
                join
                expect_err(1, "kernel write during frame");
                if (dut.kern[0] !== K[0]) $fatal(1, "kernel changed during frame");
                send(30, -1, 0);               // 프레임 중간에 Reset
                resetn = 0; repeat (2) @(negedge clk); resetn = 1; @(negedge clk);
                nout = 0;
                if (!ready) $fatal(1, "not ready after reset");
                err_before = n_err;
                load_kernel;                   // Reset으로 커널·Bias 초기화 → 다시 적재
                rec = 1;
            end
            send(64, 63, (f % 3) != 1);        // f%3==1: 버블 없이(앞 프레임과 붙여) 보냄
            if ((f % 3) != 1) drain;
        end
        drain;
        if (n_err != err_before) $fatal(1, "unexpected error pulse");
        $fclose(af);
        $display("RTL_SIM_PASS CONV3X3 frames=%0d outputs_per_frame=36 latency=%0d errors_checked=4", nf, lat);
        $finish;
    end
    initial begin #5000000; $fatal(1, "TB timeout"); end
endmodule
