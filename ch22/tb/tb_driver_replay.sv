`timescale 1ns/1ps
// 22장 TB: PC에서 C 드라이버가 남긴 레지스터 접근 기록(W·R·P)을 20장 AXI NPU에 그대로 재생한다.
// 쓰기·읽기는 20장과 같은 AXI 마스터 태스크(순서 3가지, 역압력)로 하고, 감시기도 같다.
// R·P의 실제 읽기 값은 파일로 남겨 Python이 점수·클래스를 비교한다.
module tb_driver_replay;
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

    integer f, o, polls, nw = 0, nr = 0, np = 0;
    reg [31:0] r, off, val, mask, lim; reg [7:0] op; string tp, ap;

    initial begin
        modes[0] = 0; modes[1] = 0; modes[2] = 0;
        if (!$value$plusargs("TRACE=%s", tp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "인자");
        f = $fopen(tp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        repeat (3) @(negedge clk); rn = 1;
        while ($fscanf(f, " %c", op) == 1) begin
            case (op)
                "W": begin if ($fscanf(f, "%d %d", off, val) != 2) $fatal(1, "W 형식"); axi_write(off[7:0], val, 4'b1111); nw = nw + 1; end
                "R": begin if ($fscanf(f, "%d", off) != 1) $fatal(1, "R 형식"); axi_read(off[7:0], r); $fwrite(o, "R %0d %0d\n", off, r); nr = nr + 1; end
                "P": begin
                    if ($fscanf(f, "%d %d %d", off, mask, lim) != 3) $fatal(1, "P 형식");
                    polls = 0;
                    do begin axi_read(off[7:0], r); polls = polls + 1; end while ((r & mask) == 0 && polls < lim);
                    if ((r & mask) == 0) $fatal(1, "폴링 상한 %0d번 안에 완료 없음", lim);
                    $fwrite(o, "P %0d %0d\n", off, r); np = np + 1;
                end
                default: $fatal(1, "모르는 기록 %c", op);
            endcase
        end
        if (viol != 0) $fatal(1, "AXI 규칙 위반 %0d", viol);
        $display("RTL_SIM_PASS DRIVER_REPLAY writes=%0d reads=%0d polls=%0d axi_violations=0", nw, nr, np);
        $fclose(o); $finish;
    end
    initial begin #2000000000; $fatal(1, "시간 초과"); end
endmodule
