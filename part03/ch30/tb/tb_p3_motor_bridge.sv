// (추가) 30장 협동 시뮬레이션 브리지. 22장 tb_p3_npu_bridge와 같은 FIFO 규약에 모터 안전 코어를 더했다.
//   주소 0x00..0x3F → 20장 AXI NPU(BFM), 0x100 쓰기 → 명령 워드(AXI GPIO 2 채널 1과 같은 값), 0x108 읽기 → 상태 워드
//   (채널 2), 0x200 쓰기 → 시험 주입: 입력 {lim_r, lim_f, otemp, fault, estop}, 0x204 쓰기 → N클록 진행.
//   주입 주소는 시험 장치(보드의 버튼·스위치·외부 회로에 해당)이며 펌웨어의 PC 빌드만 쓴다.
//   모든 클록에서 핀(IN1·IN2·ENA)의 안전 불변식을 감시하고 끝에 SAFETY_SUMMARY를 낸다.
//   GPIO 쓰기·읽기에는 각각 GPIO_LAT클록 버스 지연을 둔다(실제 AXI GPIO 지연과 비슷하게, 정확히 같지는 않다).
`timescale 1ns/1ps
module tb_p3_motor_bridge;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    reg [5:0] awaddr = 0, araddr = 0;
    reg awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    wire awready, wready, bvalid, arready, rvalid, irq;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;

    p3_npu_axi_lite npu(
        .s_axi_aclk(clk), .s_axi_aresetn(resetn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .irq_o(irq));

    `include "axi_lite_bfm.svh"

    localparam integer DEAD = 3000, GPIO_LAT = 4;
    reg [31:0] mcmd = 0;
    reg [4:0] inj = 0;                       // {lim_r, lim_f, otemp, fault, estop}
    wire in1, in2, ena;
    wire [31:0] mst;
    p3_motor_safety #(.PWM_PERIOD(200), .DEAD_CYC(DEAD), .WD_CYC(400000), .RAMP_CYC(40)) motor(
        .clk(clk), .rst(!resetn), .cmd(mcmd), .estop(inj[0]), .fault(inj[1]), .otemp(inj[2]),
        .lim_f(inj[3]), .lim_r(inj[4]), .in1(in1), .in2(in2), .ena(ena), .status(mst));

    // ---- 핀 안전 불변식(클록마다)
    integer viol = 0, n_cyc = 0, n_ena = 0, n_in1 = 0, n_in2 = 0, off_run = 1000000000, reversals = 0, min_rev_gap = 1000000000;
    integer last_dir = 0, cur_dir;
    always @(posedge clk) if (resetn) begin
        n_cyc = n_cyc + 1;
        if ((in1 || in2 || ena) && (inj[0] || inj[1] || inj[2] || mst[14] || mst[15])) begin
            viol = viol + 1; if (viol <= 5) $display("SAFETY_VIOLATION t=%0t output during stop condition st=%h", $time, mst);
        end
        if (in1 && in2) begin viol = viol + 1; if (viol <= 5) $display("SAFETY_VIOLATION t=%0t in1&in2", $time); end
        if ((in1 && inj[3]) || (in2 && inj[4])) begin viol = viol + 1; if (viol <= 5) $display("SAFETY_VIOLATION t=%0t limit", $time); end
        if (ena && !(in1 || in2)) begin viol = viol + 1; if (viol <= 5) $display("SAFETY_VIOLATION t=%0t ena alone", $time); end
        cur_dir = in1 ? 1 : in2 ? 2 : 0;
        if (cur_dir != 0) begin
            if (last_dir != 0 && cur_dir != last_dir) begin
                reversals = reversals + 1;
                if (off_run < min_rev_gap) min_rev_gap = off_run;
                if (off_run < DEAD) begin viol = viol + 1; $display("SAFETY_VIOLATION t=%0t reversal gap %0d", $time, off_run); end
            end
            last_dir = cur_dir; off_run = 0;
        end else off_run = off_run + 1;
        if (ena) n_ena = n_ena + 1;
        if (in1) n_in1 = n_in1 + 1;
        if (in2) n_in2 = n_in2 + 1;
    end

    reg [8*256-1:0] cpath, rpath;
    reg [8*8-1:0] op;
    reg [31:0] a, d;
    reg [1:0] resp;
    integer cf, rf, rc, n_wr = 0, n_rd = 0, k;
    initial begin
        if (!$value$plusargs("CMD=%s", cpath)) $fatal(1, "+CMD required");
        if (!$value$plusargs("RSP=%s", rpath)) $fatal(1, "+RSP required");
        repeat (4) @(negedge clk);
        resetn = 1;
        cf = $fopen(cpath, "r");
        rf = $fopen(rpath, "w");
        forever begin
            rc = $fscanf(cf, "%s", op);
            if (rc != 1) $fatal(1, "command stream closed without Q");
            if (op == "Q") begin
                $display("SAFETY_SUMMARY cycles=%0d violations=%0d ena_cycles=%0d in1_cycles=%0d in2_cycles=%0d reversals=%0d min_reversal_gap=%0d dead=%0d",
                         n_cyc, viol, n_ena, n_in1, n_in2, reversals, min_rev_gap, DEAD);
                if (viol == 0 && n_ena > 0 && reversals > 0)
                    $display("RTL_SIM_PASS MOTOR_BRIDGE axi_writes=%0d axi_reads=%0d", n_wr, n_rd);
                else
                    $display("RTL_SIM_FAIL MOTOR_BRIDGE");
                $finish;
            end else if (op == "W") begin
                rc = $fscanf(cf, "%h %h", a, d);
                resp = 2'b00;
                if (a < 32'h100) begin
                    axi_write(a[5:0], d, 4'hF, 0, 0, 0, resp);
                    if (resp != 2'b00) $fatal(1, "driver write 0x%02h=0x%08h got SLVERR", a, d);
                end else if (a == 32'h100) begin
                    @(negedge clk); mcmd = d; repeat (GPIO_LAT) @(posedge clk);
                end else if (a == 32'h200) begin
                    @(negedge clk); inj = d[4:0]; @(posedge clk);
                end else if (a == 32'h204) begin
                    for (k = 0; k < d; k = k + 1) @(posedge clk);
                end else $fatal(1, "bad write address 0x%h", a);
                n_wr = n_wr + 1;
                $fwrite(rf, "B %0d\n", resp);
                $fflush(rf);
            end else if (op == "R") begin
                rc = $fscanf(cf, "%h", a);
                resp = 2'b00;
                if (a < 32'h100) begin
                    axi_read(a[5:0], 0, d, resp);
                    if (resp != 2'b00) $fatal(1, "driver read 0x%02h got SLVERR", a);
                end else if (a == 32'h108) begin
                    repeat (GPIO_LAT) @(posedge clk); @(negedge clk); d = mst;
                end else $fatal(1, "bad read address 0x%h", a);
                n_rd = n_rd + 1;
                $fwrite(rf, "D %h %0d\n", d, resp);
                $fflush(rf);
            end else begin
                $fatal(1, "unknown command %0s", op);
            end
        end
    end
endmodule
