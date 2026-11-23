// C 드라이버 PC 시뮬레이션 브리지. PC에서 실행되는 C 드라이버의 레지스터 접근을 FIFO로 받아
// 5-1 AXI4-Lite BFM으로 실제 p3_npu_axi_lite RTL에 수행하고 응답을 돌려준다.
//   명령(+CMD FIFO): "W <addr hex> <data hex>" / "R <addr hex>" / "Q"
//   응답(+RSP FIFO): "B <bresp>" / "D <rdata hex> <rresp>"
// 드라이버가 SLVERR을 일으키면 실패로 끝낸다(드라이버는 버스 규칙을 지켜야 한다).
`timescale 1ns/1ps
module tb_p3_npu_bridge;
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

    `include "axi_lite_bfm.svh"

    reg [8*256-1:0] cpath, rpath;
    reg [8*8-1:0] op;
    reg [31:0] a, d;
    reg [1:0] resp;
    integer cf, rf, rc, n_wr = 0, n_rd = 0, n_irq_edges = 0;
    reg irq_q = 0;
    always @(posedge clk) begin
        if (irq && !irq_q) n_irq_edges = n_irq_edges + 1;
        irq_q <= irq;
    end
    initial begin
        if (!$value$plusargs("CMD=%s", cpath)) $fatal(1, "+CMD required");
        if (!$value$plusargs("RSP=%s", rpath)) $fatal(1, "+RSP required");
        repeat (4) @(negedge clk);
        resetn = 1;
        cf = $fopen(cpath, "r");     // 드라이버가 쓰기용으로 열 때까지 기다린다
        rf = $fopen(rpath, "w");
        forever begin
            rc = $fscanf(cf, "%s", op);
            if (rc != 1) $fatal(1, "command stream closed without Q");
            if (op == "Q") begin
                $display("RTL_SIM_PASS DRIVER_BRIDGE axi_writes=%0d axi_reads=%0d irq_rising=%0d", n_wr, n_rd, n_irq_edges);
                $finish;
            end else if (op == "W") begin
                rc = $fscanf(cf, "%h %h", a, d);
                axi_write(a[5:0], d, 4'hF, 0, 0, 0, resp);
                if (resp != 2'b00) $fatal(1, "driver write 0x%02h=0x%08h got SLVERR", a, d);
                n_wr = n_wr + 1;
                $fwrite(rf, "B %0d\n", resp);
                $fflush(rf);
            end else if (op == "R") begin
                rc = $fscanf(cf, "%h", a);
                axi_read(a[5:0], 0, d, resp);
                if (resp != 2'b00) $fatal(1, "driver read 0x%02h got SLVERR", a);
                n_rd = n_rd + 1;
                $fwrite(rf, "D %h %0d\n", d, resp);
                $fflush(rf);
            end else begin
                $fatal(1, "unknown command %0s", op);
            end
        end
    end
endmodule
