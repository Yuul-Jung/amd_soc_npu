// 2단계: 표준 7세그먼트 IP(ip_seg7) 레지스터 시험.
// 확인: ID 0xFFF0 = "SEG7", VER, VALUE·MODE·RAW·DP 쓰기/읽기, 바이트 쓰기(wstrb), 없는 주소 0, 핀 구동(16진수·RAW·끔).
`timescale 1ns/1ps
module tb_ip_seg7;
  reg clk = 0, rstn = 0;
  always #5 clk = ~clk;
  reg [15:0] awaddr = 0, araddr = 0; reg awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
  reg [31:0] wdata = 0; reg [3:0] wstrb = 4'hF;
  wire awready, wready, bvalid, arready, rvalid; wire [1:0] bresp, rresp; wire [31:0] rdata;
  wire [6:0] seg; wire dp; wire [3:0] an;
  integer errors = 0, checks = 0;

  ip_seg7 dut (.seg(seg), .dp(dp), .an(an), .s_axi_aclk(clk), .s_axi_aresetn(rstn),
    .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready));

  task axw(input [15:0] a, input [31:0] d, input [3:0] s);
    begin
      @(negedge clk); awaddr = a; wdata = d; wstrb = s; awvalid = 1; wvalid = 1;
      @(posedge clk); while (!awready) @(posedge clk);
      @(negedge clk); awvalid = 0; wvalid = 0;
      while (!bvalid) @(posedge clk);
      if (bresp !== 2'b00) begin errors = errors + 1; $display("FAIL bresp a=%h", a); end
      @(posedge clk);
    end
  endtask
  task axr(input [15:0] a, output [31:0] d);
    begin
      @(negedge clk); araddr = a; arvalid = 1;
      @(posedge clk); while (!arready) @(posedge clk);
      @(negedge clk); arvalid = 0;
      while (!rvalid) @(posedge clk);
      d = rdata; @(posedge clk);
    end
  endtask
  task expect_rd(input [15:0] a, input [31:0] e, input [127:0] name);
    reg [31:0] v;
    begin
      axr(a, v); checks = checks + 1;
      if (v !== e) begin errors = errors + 1; $display("FAIL %0s a=%h got=%h exp=%h", name, a, v, e); end
      else $display("OK   %0s a=%h = %h", name, a, v);
    end
  endtask
  // 자리 d(0=오른쪽)가 선택될 때까지 기다려 seg·dp·an을 본다 (자리 전환 2^16클록)
  task expect_pin(input [1:0] d, input [6:0] es, input edp, input [3:0] ean, input [127:0] name);
    begin
      wait (dut.digit_sel == d); @(negedge clk); checks = checks + 1;
      if (seg !== es || dp !== edp || an !== ean) begin errors = errors + 1;
        $display("FAIL %0s digit=%0d seg=%b dp=%b an=%b exp seg=%b dp=%b an=%b", name, d, seg, dp, an, es, edp, ean); end
      else $display("OK   %0s digit=%0d seg=%b dp=%b an=%b", name, d, seg, dp, an);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk); rstn = 1;
    expect_rd(16'hFFF0, 32'h53454737, "ID");
    expect_rd(16'hFFF4, 32'h01000100, "VER");
    expect_rd(16'h0000, 32'h0, "VALUE_reset");
    expect_rd(16'h0004, 32'h0, "MODE_reset");
    axw(16'h0000, 32'hDEAD1234, 4'hF); expect_rd(16'h0000, 32'h00001234, "VALUE");
    axw(16'h0000, 32'h0000AB00, 4'b0010); expect_rd(16'h0000, 32'h0000AB34, "VALUE_wstrb");
    axw(16'h0004, 32'hFFFFF5FA, 4'hF); expect_rd(16'h0004, 32'h0000050A, "MODE");
    axw(16'h0008, 32'hA5C3_7E81, 4'hF); expect_rd(16'h0008, 32'hA5C37E81, "RAW");
    axw(16'h000C, 32'hFFFF_FFF5, 4'hF); expect_rd(16'h000C, 32'h00000005, "DP");
    expect_rd(16'h0010, 32'h0, "unmapped");
    axw(16'hFFF0, 32'h12345678, 4'hF); expect_rd(16'hFFF0, 32'h53454737, "ID_readonly");
    // 핀: MODE RAW_EN=1010(자리1·3 RAW), BLANK=0101(자리0·2 끔)
    // 끔: 사양은 an = 1111만 정한다(seg 값은 무관) → an만 본다
    wait (dut.digit_sel == 2'd0); @(negedge clk); checks = checks + 1;
    if (an !== 4'b1111) begin errors = errors + 1; $display("FAIL pin_blank0 an=%b", an); end
    else $display("OK   pin_blank0 digit=0 an=%b", an);
    expect_pin(2'd1, ~7'h7E, ~1'b0, 4'b1101, "pin_raw1");      // RAW 바이트1 = 0x7E (dp 0)
    expect_pin(2'd3, ~7'h25, ~1'b1, 4'b0111, "pin_raw3");      // RAW 바이트3 = 0xA5 (dp 1)
    // 16진수 표시: MODE=0, VALUE=0xAB34(앞의 wstrb 쓰기 결과), DP=0101
    axw(16'h0004, 32'h0, 4'hF);
    expect_pin(2'd0, ~7'b1100110, ~1'b1, 4'b1110, "pin_hex0_4_dp");
    expect_pin(2'd1, ~7'b1001111, ~1'b0, 4'b1101, "pin_hex1_3");
    expect_pin(2'd2, ~7'b1111100, ~1'b1, 4'b1011, "pin_hex2_B_dp");
    expect_pin(2'd3, ~7'b1110111, ~1'b0, 4'b0111, "pin_hex3_A");
    if (errors == 0) $display("SEG7_TB_PASS checks=%0d id=53454737", checks);
    else $display("SEG7_TB_FAIL errors=%0d checks=%0d", errors, checks);
    $finish;
  end
  initial begin #20_000_000; $display("SEG7_TB_FAIL timeout"); $finish; end
endmodule
