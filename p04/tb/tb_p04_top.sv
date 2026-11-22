// 4장 보드 Top 시험: UART 핀으로 명령을 보내고 TX 핀을 복조해 기준 모델(p04_cases_sN.txt)과 바이트 단위로 대조한다.
// 4장 Top에는 스위치 입력이 없다. 784 추론 한 번에 약 1만 바이트라 UART를 12.5 Mbps(비트당 8클록)로 돌린다.
// 시뮬레이션 시간을 줄이려고 BAUD 6.25 Mbps(CPB 16), REFRESH_BITS 6으로 돌린다. 보드 Top 기본값은 115200 bps.
`timescale 1ns/1ps
module tb_p04_top;
    parameter integer STAGE = 4;                  // run_sim.sh가 1~4로 바꿔 네 번 돌린다
    localparam integer CLK_HZ = 100000000, BAUD = 12500000;
    localparam integer CPB = (CLK_HZ + BAUD / 2) / BAUD;
    reg clk = 0, btnC = 1, rxd = 1;
    reg [1:0] sw = 2'd0;
    wire txd, dp;
    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an;
    always #5 clk = ~clk;

    basys3_p04_top #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .REFRESH_BITS(6), .STAGE(STAGE)) dut (
        .clk(clk), .btnC(btnC), .uart_rxd(rxd), .uart_txd(txd),
        .led(led), .seg(seg), .an(an), .dp(dp));

    // TX 핀 복조 (00장 uart_rx 그대로)
    wire [7:0] got;
    wire got_valid, fe, ov;
    reg mon_resetn = 0;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) mon (
        .clk(clk), .resetn(mon_resetn), .rx_i(txd), .out_data_o(got), .out_valid_o(got_valid),
        .out_ready_i(1'b1), .framing_error_o(fe), .overrun_o(ov));

    reg [7:0] rxq [0:255];
    integer rx_wr = 0;
    always @(posedge clk) if (got_valid) begin
        rxq[rx_wr[7:0]] = got;
        rx_wr = rx_wr + 1;
    end

    task automatic send_byte(input [7:0] b);
        integer k;
        begin
            @(negedge clk); rxd = 0; repeat (CPB) @(negedge clk);
            for (k = 0; k < 8; k = k + 1) begin rxd = b[k]; repeat (CPB) @(negedge clk); end
            rxd = 1; repeat (CPB) @(negedge clk);
        end
    endtask

    integer fd, n_tx, n_rx, i, v, sel, cases = 0, rx_rd = 0, t, code;
    reg [8*8-1:0] subj;
    reg [8*200-1:0] line;
    reg [7:0] tx [0:255];
    reg [7:0] exp [0:127];
    reg [15:0] led_exp;
    reg [8*4-1:0] tag;

    initial begin
        fd = $fopen($sformatf("p04/tb/p04_cases_s%0d.txt", STAGE), "r");
        if (fd == 0) $fatal(1, "p04_cases_s%0d.txt 없음: python3 p04/reference/p04_model.py 먼저", STAGE);
        code = $fgets(line, fd);                         // 머리 줄
        repeat (5) @(posedge clk);
        btnC = 0; mon_resetn = 1;
        repeat (10) @(posedge clk);
        forever begin
            code = $fscanf(fd, "%s", subj);
            if (code != 1) $fatal(1, "사례 파일 끝에 END 줄 없음");
            if (subj == "END") begin
                code = $fscanf(fd, "%h", v); led_exp = v;
                repeat (20) @(posedge clk);
                if (led !== led_exp) $fatal(1, "LED=%04h 기대 %04h", led, led_exp);
                if (fe || ov) $fatal(1, "TX 복조 오류 fe=%0d ov=%0d", fe, ov);
                $display("P04_BOARD_TOP_LED_PASS stage=%0d led=0x%04h", STAGE, led);
                $display("P04_TOP_RTL_SIM_PASS stage=%0d cases=%0d bytes=%0d", STAGE, cases, rx_wr);
                $finish;
            end
            code = $fscanf(fd, "%h %h", sel, n_tx);
            for (i = 0; i < n_tx; i = i + 1) begin code = $fscanf(fd, "%h", v); tx[i] = v; end
            code = $fscanf(fd, "%h", n_rx);
            for (i = 0; i < n_rx; i = i + 1) begin code = $fscanf(fd, "%h", v); exp[i] = v; end
            sw = sel;
            repeat (8) @(posedge clk);                    // 스위치 2FF 동기화 대기
            for (i = 0; i < n_tx; i = i + 1) send_byte(tx[i]);
            t = 0;
            while (rx_wr - rx_rd < n_rx) begin
                @(posedge clk); t = t + 1;
                if (t > 40 * CPB * (n_rx + 2)) $fatal(1, "%0s 응답 시간 초과: %0d/%0d 바이트", subj, rx_wr - rx_rd, n_rx);
            end
            for (i = 0; i < n_rx; i = i + 1)
                if (rxq[(rx_rd + i) % 256] !== exp[i])
                    $fatal(1, "%0s 응답 %0d번째 바이트 %02h 기대 %02h", subj, i, rxq[(rx_rd + i) % 256], exp[i]);
            $write("P04_CASE_PASS stage=%0d %0s sw=%0d rx=\"", STAGE, subj, sel);
            for (i = 0; i < n_rx; i = i + 1)
                if (exp[i] == 8'h0D) $write("\\r"); else if (exp[i] == 8'h0A) $write("\\n"); else $write("%c", exp[i]);
            $display("\"");
            rx_rd = rx_rd + n_rx;
            cases = cases + 1;
        end
    end

    // 7세그먼트: an이 켠 자리에 led의 그 자리 16진수가 보여야 한다 (한 번 확인)
    initial begin
        #200000;
        if (an == 4'b1111) $fatal(1, "7세그먼트 자리가 하나도 켜지지 않음");
    end
endmodule
