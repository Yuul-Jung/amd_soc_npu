// (추가) 20장 p3_npu_axi_lite 자동 판정 테스트벤치. AXI4-Lite Master BFM으로 레지스터만 사용해 784 추론을 수행한다.
// 프로토콜: AW·W 동시/AW 먼저/W 먼저, BREADY·RREADY 지연 중 응답 유지(상시 검사), WSTRB 병합,
//   읽기 전용·미할당 주소·범위 초과·부분 WSTRB·프레임 잠금 중 X_DATA → SLVERR(효과 없음 확인).
// 동작: LENGTH 오류, IDLE의 TILE_GO, x 미완성·W 미적재 TILE_GO, BUSY 중 START·Bias 쓰기, DONE·ERROR W1C,
//   IRQ, SCORE_LO/HI 스냅샷(LO 읽은 뒤 다음 추론이 끝나도 HI는 같은 결과), 미완료 AXI 쓰기·추론 중 Reset.
// 각 추론의 10개 점수(LO/HI)·CLASS·OVF를 actual에 기록하고 Python이 비트 단위 비교한다.
`timescale 1ns/1ps
module tb_p3_npu_axi_lite;
    localparam [5:0] A_CTRL = 6'h00, A_STATUS = 6'h04, A_LENGTH = 6'h08, A_CLASS = 6'h0C,
                     A_XIDX = 6'h10, A_XDATA = 6'h14, A_WCLASS = 6'h18, A_WIDX = 6'h1C,
                     A_WDATA = 6'h20, A_BLO = 6'h24, A_BHI = 6'h28, A_SSEL = 6'h2C,
                     A_SLO = 6'h30, A_SHI = 6'h34, A_IRQEN = 6'h38, A_BAD = 6'h3C;
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    localparam [31:0] START = 32'h1, GO = 32'h2, ABORT = 32'h4;

    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    reg [5:0] awaddr = 0, araddr = 0;
    reg awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    wire awready, wready, bvalid, arready, rvalid, irq;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;

    p3_npu_axi_lite dut(
        .s_axi_aclk(clk), .s_axi_aresetn(resetn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .irq_o(irq));

    // 상시 검사: 응답 valid는 ready 전까지 내려가지 않고 내용이 바뀌지 않는다
    reg pb = 0, pr = 0;
    reg [1:0] pbresp = 0, prresp = 0;
    reg [31:0] prdata = 0;
    integer n_writes = 0, n_reads = 0, n_slverr = 0;
    always @(posedge clk) begin
        if (resetn) begin
            if (pb && !bvalid) $fatal(1, "BVALID dropped before BREADY");
            if (pb && bvalid && bresp != pbresp) $fatal(1, "BRESP changed while waiting");
            if (pr && !rvalid) $fatal(1, "RVALID dropped before RREADY");
            if (pr && rvalid && (rdata != prdata || rresp != prresp)) $fatal(1, "R payload changed");
            if (dut.npu.core.error_o) $fatal(1, "core error leaked");
            if (bvalid && bready) begin n_writes = n_writes + 1; if (bresp == SLVERR) n_slverr = n_slverr + 1; end
            if (rvalid && rready) begin n_reads = n_reads + 1; if (rresp == SLVERR) n_slverr = n_slverr + 1; end
        end
        pb = resetn && bvalid && !bready; pbresp = bresp;
        pr = resetn && rvalid && !rready; prresp = rresp; prdata = rdata;
    end

    // ---------------- AXI Master BFM ----------------
    task automatic send_aw(input [5:0] a, input integer delay);
        begin
            repeat (delay) @(negedge clk);
            awaddr = a; awvalid = 1;
            while (!awready) @(negedge clk);
            @(posedge clk); @(negedge clk);
            awvalid = 0;
        end
    endtask
    task automatic send_w(input [31:0] d, input [3:0] s, input integer delay);
        begin
            repeat (delay) @(negedge clk);
            wdata = d; wstrb = s; wvalid = 1;
            while (!wready) @(negedge clk);
            @(posedge clk); @(negedge clk);
            wvalid = 0;
        end
    endtask
    task automatic wait_b(input integer bdelay, output [1:0] resp);
        integer k;
        begin
            while (!bvalid) @(negedge clk);
            for (k = 0; k < bdelay; k = k + 1) begin
                @(negedge clk);
                if (!bvalid) $fatal(1, "B lost during BREADY=0");
                if (awready || wready) $fatal(1, "new write accepted while B pending");
            end
            resp = bresp;
            bready = 1;
            @(posedge clk); @(negedge clk);
            bready = 0;
        end
    endtask
    // mode 0: 동시, 1: AW 먼저(W는 dly 뒤), 2: W 먼저(AW는 dly 뒤)
    task automatic axi_write(input [5:0] a, input [31:0] d, input [3:0] s, input integer mode,
                             input integer dly, input integer bdelay, output [1:0] resp);
        begin
            @(negedge clk);
            fork
                send_aw(a, mode == 2 ? dly : 0);
                send_w(d, s, mode == 1 ? dly : 0);
            join
            wait_b(bdelay, resp);
        end
    endtask
    task automatic axi_read(input [5:0] a, input integer rdelay, output [31:0] d, output [1:0] resp);
        integer k;
        begin
            @(negedge clk);
            araddr = a; arvalid = 1;
            while (!arready) @(negedge clk);
            @(posedge clk); @(negedge clk);
            arvalid = 0;
            while (!rvalid) @(negedge clk);
            for (k = 0; k < rdelay; k = k + 1) begin
                @(negedge clk);
                if (!rvalid) $fatal(1, "R lost during RREADY=0");
            end
            d = rdata; resp = rresp;
            rready = 1;
            @(posedge clk); @(negedge clk);
            rready = 0;
        end
    endtask

    reg [1:0] resp;
    reg [31:0] rd;
    task automatic wr(input [5:0] a, input [31:0] d);
        begin
            axi_write(a, d, 4'hF, 0, 0, 0, resp);
            if (resp != OKAY) $fatal(1, "write 0x%02h=0x%08h got SLVERR", a, d);
        end
    endtask
    task automatic wr_expect(input [5:0] a, input [31:0] d, input [3:0] s, input [1:0] exp);
        begin
            axi_write(a, d, s, 0, 0, 0, resp);
            if (resp != exp) $fatal(1, "write 0x%02h strb %b resp %0d != %0d", a, s, resp, exp);
        end
    endtask
    task automatic rd_reg(input [5:0] a, output [31:0] d);
        begin
            axi_read(a, 0, d, resp);
            if (resp != OKAY) $fatal(1, "read 0x%02h got SLVERR", a);
        end
    endtask
    task automatic expect_reg(input [5:0] a, input [31:0] exp);
        begin
            rd_reg(a, rd);
            if (rd != exp) $fatal(1, "reg 0x%02h = 0x%08h, expected 0x%08h", a, rd, exp);
        end
    endtask
    // STATUS: bit0 BUSY, 1 DONE, 2 ERROR, 3 OVF, 4 LOAD_READY, 5 X_HELD, [11:8] TILE, [15:12] ERR_CODE
    task automatic expect_error(input [3:0] code, input [8*40-1:0] what);
        begin
            rd_reg(A_STATUS, rd);
            if (!rd[2] || rd[15:12] != code)
                $fatal(1, "missing error %0d (STATUS 0x%08h): %0s", code, rd, what);
            wr(A_STATUS, 32'h4);              // ERROR W1C
            rd_reg(A_STATUS, rd);
            if (rd[2]) $fatal(1, "ERROR not cleared by W1C");
        end
    endtask
    task automatic do_reset;
        begin
            @(negedge clk);
            resetn = 0; awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
            repeat (3) @(negedge clk);
            resetn = 1;
            @(negedge clk);
            if (bvalid || rvalid || irq || dut.npu.busy_o || dut.aw_q || dut.w_q)
                $fatal(1, "reset did not clear AXI/NPU state");
        end
    endtask

    // ---------------- 추론 ----------------
    integer X [0:783];
    integer PAD [0:47];
    integer W [0:9][0:783];
    reg signed [63:0] B [0:9];
    reg signed [63:0] S [0:9];
    reg signed [63:0] tmp64, v64;
    integer tmp, vf, af, rc, ncase, cidx, i, c, t, len, guard;
    reg [8*256-1:0] vpath, apath;

    task automatic poll_until(input integer bit_idx, input integer value);
        begin
            guard = 0;
            rd_reg(A_STATUS, rd);
            while (rd[bit_idx] != value) begin
                rd_reg(A_STATUS, rd);
                guard = guard + 1;
                if (guard > 2000) $fatal(1, "STATUS bit %0d timeout (0x%08h)", bit_idx, rd);
            end
        end
    endtask
    task automatic load_bias;
        begin
            for (c = 0; c < 10; c = c + 1) begin
                wr(A_WCLASS, c);
                v64 = B[c];
                wr(A_BLO, v64[31:0]);
                wr(A_BHI, {{24{v64[39]}}, v64[39:32]});
            end
        end
    endtask
    task automatic load_w(input integer tile, input integer n);
        begin
            for (c = 0; c < 10; c = c + 1) begin
                wr(A_WCLASS, c);
                wr(A_WIDX, 0);
                for (i = 0; i < n; i = i + 1) wr(A_WDATA, W[c][64*tile + i]);
            end
        end
    endtask
    task automatic load_x(input integer tile, input integer n);
        begin
            wr(A_XIDX, 0);
            for (i = 0; i < 64; i = i + 1) wr(A_XDATA, (i < n) ? X[64*tile + i] : PAD[i - n]);
        end
    endtask
    task automatic read_scores(input integer record);
        begin
            for (c = 0; c < 10; c = c + 1) begin
                wr(A_SSEL, c);
                rd_reg(A_SLO, rd);
                v64[31:0] = rd;
                rd_reg(A_SHI, rd);
                v64[63:32] = rd;
                S[c] = v64;
                if (v64 < -(64'sd1 <<< 41) || v64 >= (64'sd1 <<< 41)) $fatal(1, "score HI not sign-extended");
            end
            rd_reg(A_CLASS, rd);
            if (record) begin
                $fwrite(af, "S");
                for (c = 0; c < 10; c = c + 1) $fwrite(af, " %0d", S[c]);
                rd_reg(A_STATUS, tmp64[31:0]);
                $fwrite(af, " C%0d O%0d\n", rd, tmp64[3]);
            end
        end
    endtask
    // mode 0: 정상, 1: 오류 주입, 2: 타일 5 계산 중 Reset
    task automatic run_inference(input integer mode);
        reg cut;
        begin
            cut = 0;
            load_bias;
            wr(A_CTRL, START);
            rd_reg(A_STATUS, rd);
            if (!rd[0] || rd[1]) $fatal(1, "START: BUSY not set or DONE not cleared (0x%08h)", rd);
            if (irq) $fatal(1, "IRQ after START");
            if (mode == 1) begin
                wr(A_CTRL, START);
                expect_error(4'd1, "START while BUSY");
                wr(A_WCLASS, 0); wr(A_BLO, 1); wr(A_BHI, 0);
                expect_error(4'd5, "Bias write during inference");
            end
            for (t = 0; t < 13 && !cut; t = t + 1) begin
                len = (t == 12) ? 16 : 64;
                if (mode == 1 && t == 0) begin
                    wr(A_XIDX, 0);
                    for (i = 0; i < 10; i = i + 1) wr(A_XDATA, X[i]);
                    wr(A_CTRL, GO);
                    expect_error(4'd4, "TILE_GO with incomplete x");
                    load_x(t, len);
                    wr(A_CTRL, GO);
                    expect_error(4'd9, "TILE_GO without weights");
                    load_w(t, len);
                end else begin
                    load_w(t, len);
                    load_x(t, len);
                end
                wr(A_CTRL, GO | (t << 8));
                if (mode == 1 && t == 1) begin
                    // 계산 중: 프레임 잠금 → X_DATA SLVERR
                    wr_expect(A_XDATA, 1, 4'hF, SLVERR);
                end
                if (mode == 2 && t == 5) begin
                    repeat (40) @(negedge clk);
                    if (!dut.npu.core.busy_o) $fatal(1, "core not computing before reset");
                    do_reset;
                    cut = 1;
                end else if (t < 12) begin
                    poll_until(5, 0);           // X_HELD 해제 = 결과 수락
                    poll_until(4, 1);           // 다음 타일 LOAD
                end
            end
            if (!cut) begin
                poll_until(1, 1);               // DONE
                rd_reg(A_STATUS, rd);
                if (rd[0]) $fatal(1, "BUSY with DONE");
                if (mode == 0 && rd[2]) $fatal(1, "unexpected ERROR 0x%08h", rd);
            end
        end
    endtask

    reg [31:0] snap_hi, snap_lo;
    initial begin
        if (!$value$plusargs("VECTORS=%s", vpath)) $fatal(1, "+VECTORS required");
        if (!$value$plusargs("ACTUAL=%s", apath)) $fatal(1, "+ACTUAL required");
        vf = $fopen(vpath, "r");
        af = $fopen(apath, "w");
        rc = $fscanf(vf, "%d", ncase);
        repeat (4) @(negedge clk);
        resetn = 1;
        @(negedge clk);

        // ---- 프로토콜: 도착 순서·역압력·WSTRB ----
        expect_reg(A_LENGTH, 784);
        axi_write(A_SSEL, 3, 4'hF, 0, 0, 4, resp); if (resp != OKAY) $fatal(1, "sim write");
        expect_reg(A_SSEL, 3);
        axi_write(A_SSEL, 5, 4'hF, 1, 6, 0, resp); if (resp != OKAY) $fatal(1, "AW-first write");
        expect_reg(A_SSEL, 5);
        axi_write(A_SSEL, 7, 4'hF, 2, 6, 7, resp); if (resp != OKAY) $fatal(1, "W-first write");
        axi_read(A_SSEL, 5, rd, resp);
        if (rd != 7 || resp != OKAY) $fatal(1, "RREADY delay read");
        wr_expect(A_SSEL, 32'h0000_0500, 4'b0010, SLVERR);      // 병합값 0x507 > 9
        expect_reg(A_SSEL, 7);
        wr_expect(A_SSEL, 32'h0000_0003, 4'b0010, OKAY);        // byte1만(0) → 7 유지
        expect_reg(A_SSEL, 7);
        wr_expect(A_SSEL, 32'hFFFF_FF02, 4'b0001, OKAY);        // 하위 바이트만 → 2
        expect_reg(A_SSEL, 2);
        wr_expect(A_LENGTH, 32'h0000_0200, 4'b0010, OKAY);      // 0x310 → 0x210
        expect_reg(A_LENGTH, 32'h210);
        wr(A_CTRL, START);
        expect_error(4'd8, "START with LENGTH 528");
        if (dut.npu.busy_o) $fatal(1, "started with bad LENGTH");
        wr(A_LENGTH, 784);
        // ---- SLVERR 검사(효과 없음) ----
        wr_expect(A_CLASS, 3, 4'hF, SLVERR);
        wr_expect(A_SLO, 3, 4'hF, SLVERR);
        wr_expect(A_SHI, 3, 4'hF, SLVERR);
        expect_reg(A_CLASS, 0);
        wr_expect(A_BAD, 1, 4'hF, SLVERR);
        axi_read(A_BAD, 0, rd, resp); if (resp != SLVERR) $fatal(1, "read 0x3C not SLVERR");
        wr_expect(A_XIDX, 64, 4'hF, SLVERR);
        wr_expect(A_WCLASS, 10, 4'hF, SLVERR);
        wr_expect(A_WIDX, 64, 4'hF, SLVERR);
        wr_expect(A_XDATA, 200, 4'hF, SLVERR);                  // INT8 범위 밖
        wr_expect(A_XDATA, 5, 4'b0001, SLVERR);                 // 동작 레지스터 부분 WSTRB
        wr_expect(A_WDATA, -129, 4'hF, SLVERR);
        wr_expect(A_BHI, 32'h0000_0100, 4'hF, SLVERR);          // 상위가 bit39 부호 확장이 아님
        wr_expect(A_CTRL, START | GO, 4'hF, SLVERR);            // 명령 2개 동시
        wr_expect(A_IRQEN, 2, 4'hF, SLVERR);
        expect_reg(A_XIDX, 0);
        expect_reg(A_WCLASS, 0);
        rd_reg(A_STATUS, rd);
        if (rd[2] || rd[0]) $fatal(1, "SLVERR changed NPU state 0x%08h", rd);
        // ---- 동작 오류: IDLE의 TILE_GO ----
        wr(A_CTRL, GO);
        expect_error(4'd1, "TILE_GO in IDLE");
        // ---- 미완료 쓰기 중 Reset: AW만 받은 상태 ----
        @(negedge clk);
        send_aw(A_SSEL, 0);
        if (!dut.aw_q) $fatal(1, "AW not held");
        do_reset;
        // W만 보내면 쓰기가 실행되지 않아야 한다(AW 보관이 Reset으로 지워짐)
        @(negedge clk);
        send_w(9, 4'hF, 0);
        repeat (10) @(negedge clk);
        if (bvalid) $fatal(1, "write executed without AW after reset");
        send_aw(A_SSEL, 0);
        wait_b(0, resp);
        if (resp != OKAY) $fatal(1, "late AW write");
        expect_reg(A_SSEL, 9);

        wr(A_IRQEN, 1);
        for (cidx = 0; cidx < ncase; cidx = cidx + 1) begin
            for (i = 0; i < 784; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); X[i] = tmp; end
            for (i = 0; i < 48; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); PAD[i] = tmp; end
            for (c = 0; c < 10; c = c + 1)
                for (i = 0; i < 784; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); W[c][i] = tmp; end
            for (c = 0; c < 10; c = c + 1) begin rc = $fscanf(vf, "%d", tmp64); B[c] = tmp64; end
            if (cidx == 2) begin
                run_inference(2);               // 계산 중 Reset → 처음부터 다시
                wr(A_IRQEN, 1);
            end
            if (irq && cidx != 4) $fatal(1, "IRQ before DONE");
            run_inference(cidx == 0 ? 1 : 0);
            if (!irq) $fatal(1, "IRQ not raised at DONE");
            if (cidx == 1) begin
                // 앞 추론에서 LO를 읽어 둔 스냅샷: 이번 추론이 끝난 뒤에도 HI는 앞 결과여야 한다
                rd_reg(A_SHI, rd);
                if (rd != snap_hi) $fatal(1, "SCORE_HI snapshot broken (0x%08h vs 0x%08h)", rd, snap_hi);
            end
            read_scores(1);
            if (cidx == 0) begin
                // 스냅샷: class 0 LO를 읽어 둔 뒤 다음 추론이 끝나도 HI는 이번 결과
                v64 = S[0];
                wr(A_SSEL, 0);
                rd_reg(A_SLO, snap_lo);
                snap_hi = v64[63:32];
            end
            if (cidx == 1 && S[0][63:32] == snap_hi)
                $fatal(1, "snapshot test needs different HI values");
            wr(A_IRQEN, 0);                     // DONE 유지 중 IRQ_EN=0이면 IRQ 없음
            if (irq) $fatal(1, "IRQ ignores IRQ_EN");
            wr(A_IRQEN, 1);
            if (!irq) $fatal(1, "IRQ not restored by IRQ_EN");
            if (cidx != 3) begin               // cidx 3은 DONE을 남겨 다음 START가 지우는지 확인
                wr(A_STATUS, 32'h2);            // DONE W1C → IRQ 해제
                if (irq) $fatal(1, "IRQ not cleared by DONE W1C");
            end
        end
        $fclose(af);
        $display("RTL_SIM_PASS AXI_NPU inferences=%0d axi_writes=%0d axi_reads=%0d slverr=%0d",
            ncase, n_writes, n_reads, n_slverr);
        $finish;
    end
    initial begin #2000000000; $fatal(1, "TB timeout"); end
endmodule
