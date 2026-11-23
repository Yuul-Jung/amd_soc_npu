// 5-2 SoC 전체(MicroBlaze V + NPU) 행동 시뮬레이션. 벤치마크 ELF를 LMB에 연결해 실행하고,
// 프로그램이 GPIO 데이터 레지스터에 쓰는 값(AXI 쓰기)을 기록한다. 사용자 Top은
// 5-2 basys3_soc21_top(btn·seg·dp·an 포함)이다. 버튼은 누르지 않는다.
`timescale 1ns/1ps
module tb_soc_bench;
    reg clk = 0, btnC = 1, rx = 1;
    reg [15:0] sw = 16'd0;
    wire [15:0] led;
    wire tx, dp;
    wire [6:0] seg;
    wire [3:0] an;
    always #5 clk = ~clk;   // Basys3 W5 100 MHz
    basys3_soc21_top dut(.clk(clk), .btnC(btnC), .btn(4'b0000), .sw(sw), .led(led), .RsRx(rx), .RsTx(tx),
                         .seg(seg), .dp(dp), .an(an));

    wire aclk = dut.u_soc11.soc11_integration_i.axi_gpio_0.s_axi_aclk;
    wire wv = dut.u_soc11.soc11_integration_i.axi_gpio_0.s_axi_wvalid;
    wire wr = dut.u_soc11.soc11_integration_i.axi_gpio_0.s_axi_wready;
    wire [31:0] wd = dut.u_soc11.soc11_integration_i.axi_gpio_0.s_axi_wdata;
    reg [31:0] v [0:15];
    integer n = 0;
    initial begin
        #2000 btnC = 0;     // 버튼 Reset 해제(High 활성)
    end
    always @(posedge aclk) if (wv && wr) begin
        if (n == 0 && wd != 32'hBE0C0001) $fatal(1, "unexpected first GPIO word %h", wd);
        v[n] = wd;
        n = n + 1;
        if (wd == 32'hBE0C00FF) begin
            if (n != 9) $fatal(1, "report length %0d", n);
            $display("SOC_BENCH cpu_cycles=%0d npu_bias_cycles=%0d npu_cycles=%0d cpu_class=%0d npu_class=%0d scores_match=%0d rc=%0d sim_time_ns=%0t",
                     v[1], v[2], v[3], v[4], v[5], v[6], $signed(v[7]), $time);
            if (v[6] != 1 || v[4] != v[5] || v[7] != 0) $fatal(1, "SoC benchmark result mismatch");
            $display("SOC_RTL_SIM_PASS");
            $finish;
        end
    end
    initial begin #50_000_000; $fatal(1, "SoC simulation timeout (n=%0d)", n); end
endmodule
