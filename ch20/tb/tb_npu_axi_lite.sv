`timescale 1ns/1ps
// 20장 TB: AXI4-Lite 마스터 태스크로 레지스터를 읽고 쓴다.
//  · 쓰기 순서 3가지(AW·W 동시, AW 먼저, W 먼저)를 번갈아 쓰고, BREADY·RREADY를 무작위로 늦춘다 (역압력)
//  · 감시기: B·R은 READY 전까지 VALID·데이터 유지, B 응답 수 ≤ AW·W 수
//  · WSTRB 부분 쓰기, ID·LENGTH, 실제 MNIST INT8 모델로 추론 2장 (점수·클래스는 Python 비교)
module tb_npu_axi_lite;
    reg clk=0, rn=0;
    reg [7:0] awaddr=0, araddr=0; reg awvalid=0, wvalid=0, bready=0, arvalid=0, rready=0;
    reg [31:0] wdata=0; reg [3:0] wstrb=0;
    wire awready, wready, bvalid, arready, rvalid, irq; wire [1:0] bresp, rresp; wire [31:0] rdata;
    npu_axi_lite dut(.s_axi_aclk(clk), .s_axi_aresetn(rn), .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid),
        .s_axi_awready(awready), .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready), .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .irq_o(irq));
    always #5 clk = ~clk;

    // ── 감시기
    integer n_aw = 0, n_w = 0, n_b = 0, n_r = 0, viol = 0;
    reg pb = 0, pr = 0; reg [31:0] prd = 0;
    always @(posedge clk) if (rn) begin
        if (awvalid && awready) n_aw = n_aw + 1;
        if (wvalid && wready) n_w = n_w + 1;
        if (bvalid && bready) n_b = n_b + 1;
        if (rvalid && rready) n_r = n_r + 1;
        if (pb && !bvalid) begin viol = viol + 1; $display("VIOLATION BVALID가 BREADY 전에 내려감"); end
        if (pr && (!rvalid || rdata !== prd)) begin viol = viol + 1; $display("VIOLATION R이 RREADY 전에 바뀜"); end
        if (n_b > n_aw || n_b > n_w) begin viol = viol + 1; $display("VIOLATION AW·W 없이 B 응답"); end
        if (bresp !== 2'b00 || rresp !== 2'b00) begin viol = viol + 1; $display("VIOLATION 응답 코드"); end
        pb = bvalid && !bready; pr = rvalid && !rready; prd = rdata;
    end

    reg [15:0] lfsr = 16'h2020;
    function integer rnd(input integer m); begin
        lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]}; rnd = lfsr % m; end endfunction

    integer mode = 0, modes [0:2];
    // AW·W 채널을 각자 독립된 프로세스로 구동: 한쪽을 gap클록 늦게 올리고, 각자 핸드셰이크 즉시 내린다.
    task drive_aw(input [7:0] a, input integer delay); begin
        repeat (delay) @(negedge clk);
        @(negedge clk); awaddr = a; awvalid = 1;
        @(posedge clk); while (!awready) @(posedge clk);
        @(negedge clk); awvalid = 0;
    end endtask
    task drive_w(input [31:0] d, input [3:0] s, input integer delay); begin
        repeat (delay) @(negedge clk);
        @(negedge clk); wdata = d; wstrb = s; wvalid = 1;
        @(posedge clk); while (!wready) @(posedge clk);
        @(negedge clk); wvalid = 0;
    end endtask
    task axi_write(input [7:0] a, input [31:0] d, input [3:0] s); integer gap; begin
        gap = 1 + rnd(3);
        fork
            drive_aw(a, mode == 2 ? gap : 0);      // mode 2: W 먼저
            drive_w(d, s, mode == 1 ? gap : 0);    // mode 1: AW 먼저
        join
        modes[mode] = modes[mode] + 1; mode = (mode + 1) % 3;
        while (!bvalid) @(negedge clk);
        repeat (rnd(3)) @(negedge clk);                    // BREADY 늦추기
        bready = 1; @(negedge clk); bready = 0;
    end endtask

    task axi_read(input [7:0] a, output [31:0] d); begin
        @(negedge clk); araddr = a; arvalid = 1;
        while (!(arvalid && arready)) @(posedge clk);
        @(negedge clk); arvalid = 0;
        while (!rvalid) @(negedge clk);
        repeat (rnd(3)) @(negedge clk);                    // RREADY 늦추기
        d = rdata; rready = 1; @(negedge clk); rready = 0;
    end endtask

    integer f, o, k, c, v, n, label, cases = 0, ncases, polls;
    reg [31:0] r; string vp, ap;

    initial begin
        modes[0] = 0; modes[1] = 0; modes[2] = 0;
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap) || !$value$plusargs("NCASES=%d", ncases))
            $fatal(1, "인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        axi_read(8'h28, r); if (r !== 32'h4E505531) $fatal(1, "ID %h", r);
        axi_read(8'h2C, r); if (r !== 784) $fatal(1, "LENGTH %0d", r);
        // WSTRB: 바이트 0만 → 0x055, 바이트 1만 → 0x355, X_DATA를 WSTRB 0으로 쓰면 무시
        axi_write(8'h10, 32'hFFFF_FF55, 4'b0001); axi_write(8'h10, 32'hFFFF_0300, 4'b0010);
        axi_read(8'h10, r); if (r !== 32'h355) $fatal(1, "WSTRB X_ADDR %h", r);
        axi_write(8'h14, 32'h7, 4'b0000); axi_read(8'h10, r); if (r !== 32'h355) $fatal(1, "WSTRB 0 X_DATA가 주소를 바꿈");
        // 미해결 쓰기 2개: AW1·AW2를 먼저 연달아 보내고 W1·W2를 뒤에 보낸다 → 슬레이브는 B1 전까지 AW2를 받지 않아야 함
        fork
            begin drive_aw(8'h10, 0); drive_aw(8'h20, 0); end
            begin drive_w(32'h12, 4'b1111, 3); drive_w(32'h5, 4'b0001, 0); end
            begin repeat (2) begin while (!bvalid) @(negedge clk); repeat (4) @(negedge clk); bready = 1; @(negedge clk); bready = 0; end end
        join
        axi_read(8'h10, r); if (r !== 32'h12) $fatal(1, "미해결 쓰기 1 X_ADDR %h", r);
        axi_read(8'h20, r); if (r !== 32'h5) $fatal(1, "미해결 쓰기 2 B_SEL %h", r);
        // 모델 적재: 클래스마다 W_ADDR 설정 후 W_DATA 784번, B_SEL=0 후 B_DATA 10번
        for (c = 0; c < 10; c = c + 1) begin
            axi_write(8'h18, c << 16, 4'b1111);
            for (k = 0; k < 784; k = k + 1) begin if ($fscanf(f, "%d", v) != 1) $fatal(1, "w"); axi_write(8'h1C, v, 4'b0001); end
        end
        axi_read(8'h18, r); if (r !== {12'd0, 4'd9, 6'd0, 10'd784}) $fatal(1, "W_ADDR 자동 증가 %h", r);
        axi_write(8'h20, 0, 4'b0001);
        for (c = 0; c < 10; c = c + 1) begin if ($fscanf(f, "%d", v) != 1) $fatal(1, "b"); axi_write(8'h24, v, 4'b1111); end
        while (cases < ncases && $fscanf(f, "%d %d", n, label) == 2) begin
            axi_write(8'h10, 0, 4'b1111);
            for (k = 0; k < 784; k = k + 1) begin if ($fscanf(f, "%d", v) != 1) $fatal(1, "x"); axi_write(8'h14, v, 4'b0001); end
            axi_write(8'h00, 1, 4'b0001);                         // START
            polls = 0;
            do begin axi_read(8'h04, r); polls = polls + 1; end while (!r[1] && !r[2]);
            if (r[2] || !irq) $fatal(1, "case %0d: ERROR 또는 irq 없음", n);
            $fwrite(o, "%0d", n);
            for (c = 0; c < 10; c = c + 1) begin axi_read(8'h40 + 4 * c, r); $fwrite(o, " %0d", $signed(r)); end
            axi_read(8'h08, r); $fwrite(o, " %0d\n", r);
            axi_read(8'h0C, r); if (r !== 7185) $fatal(1, "CYCLES %0d", r);
            axi_write(8'h00, 2, 4'b0001); axi_read(8'h04, r);     // CLR → DONE 0
            if (r[1] || irq) $fatal(1, "CLR 후 DONE 남음");
            cases = cases + 1;
        end
        if (viol != 0) $fatal(1, "AXI 규칙 위반 %0d", viol);
        $display("AXI_PROTOCOL_PASS writes=%0d reads=%0d aw_first=%0d w_first=%0d same=%0d violations=0", n_b, n_r, modes[1], modes[2], modes[0]);
        $display("RTL_SIM_PASS NPU_AXI_LITE cases=%0d wstrb=3 outstanding=2 id=NPU1 cycles=7185", cases);
        $fclose(o); $finish;
    end
    initial begin #900000000; $fatal(1, "시간 초과"); end
endmodule
