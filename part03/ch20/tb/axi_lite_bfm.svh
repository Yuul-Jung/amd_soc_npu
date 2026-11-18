// (추가) 20장: AXI4-Lite Master BFM 태스크(모듈 안에서 `include). 20장 TB와 22장 C 드라이버 브리지 TB가 함께 쓴다.
// 필요한 모듈 신호: clk, awaddr, awvalid, awready, wdata, wstrb, wvalid, wready, bvalid, bready, bresp,
//   araddr, arvalid, arready, rvalid, rready, rdata, rresp. 모든 구동은 negedge, 핸드셰이크는 posedge.
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

