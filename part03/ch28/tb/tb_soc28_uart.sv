// 숫자 인식 SoC 전체 행동 시뮬레이션(xsim). 보드용 digit_app.elf를 그대로 LMB에 연결해 실행한다.
// TB가 PC 역할: USB-UART RsRx로 115200 8N1 프레임을 비트 단위로 보내고, RsTx를 복호해 줄 단위로 기록한다.
// 응답 뒤 LED 핀과 FND 핀(an/seg/dp)을 스캔 두 주기 동안 관찰해 기록한다. 판정은 Python(soc_sim_check.py)이 한다.
//   +FRAME=<한 줄에 1바이트 16진> +OUT=<기록 파일>
`timescale 1ns/1ps
module tb_soc28_uart;
    localparam real BIT_NS = 1.0e9 / 115200.0;
    reg clk = 0, btnC = 1, rx = 1;
    reg [15:0] sw = 16'd0;
    wire [15:0] led;
    wire tx, dp;
    wire [6:0] seg;
    wire [3:0] an;
    always #5 clk = ~clk;   // Basys3 W5 100 MHz
    // 5-2 SoC Top(표준 7세그먼트 IP, BTN GPIO). 버튼은 누르지 않는다.
    basys3_soc21_top dut(.clk(clk), .btnC(btnC), .btn(4'b0000), .sw(sw), .led(led), .RsRx(rx), .RsTx(tx),
                         .seg(seg), .dp(dp), .an(an));

    integer of, lines = 0, nbytes = 0, i, k;
    reg [8*256-1:0] fpath, opath;
    reg [7:0] frame_mem [0:1023];
    reg [8*250-1:0] cur;
    integer cur_n = 0;

    // ---- RsTx 복호: 시작 비트 하강 → 비트 중앙에서 8비트 표본(LSB 먼저) ----
    reg [7:0] ch;
    initial begin
        forever begin
            @(negedge tx);
            #(BIT_NS * 1.5);
            for (k = 0; k < 8; k = k + 1) begin
                ch[k] = tx;
                #(BIT_NS);
            end
            if (tx !== 1'b1) $fatal(1, "UART stop bit error");
            if (ch == 8'h0A) begin
                $fwrite(of, "UART %0s\n", cur);      // 앞쪽 빈 바이트(0)는 판정 스크립트가 지운다
                $display("UART< %0s  (t=%0t)", cur, $time);
                $fflush(of);
                lines = lines + 1;
                cur_n = 0;
                cur = 0;
            end else if (ch != 8'h0D && cur_n < 250) begin
                cur = {cur[8*249-1:0], ch};
                cur_n = cur_n + 1;
            end
        end
    end

    task send_byte(input [7:0] b);
        integer j;
        begin
            rx = 1'b0; #(BIT_NS);
            for (j = 0; j < 8; j = j + 1) begin rx = b[j]; #(BIT_NS); end
            rx = 1'b1; #(BIT_NS);
        end
    endtask

    // ---- FND 관찰: an이 한 자리만 Low인 동안의 seg/dp를 자리별로 기록 ----
    reg [3:0] seen;
    reg [6:0] seg_d [0:3];
    reg dp_d [0:3];
    integer d;
    task observe_fnd;
        integer t;
        begin
            seen = 4'b0;
            for (t = 0; t < 2 * 4 * (1 << 17) / 64; t = t + 1) begin   // 스캔 두 주기, 64클록마다 표본
                repeat (64) @(posedge clk);
                for (d = 0; d < 4; d = d + 1)
                    if (an == ~(4'b0001 << d)) begin
                        if (seen[d] && (seg_d[d] !== seg || dp_d[d] !== dp))
                            $fatal(1, "FND digit %0d changed while idle", d);
                        seen[d] = 1'b1; seg_d[d] = seg; dp_d[d] = dp;
                    end
            end
            for (d = 0; d < 4; d = d + 1)
                if (seen[d]) $fwrite(of, "FND digit=%0d an=%b seg=%02h dp=%0d\n", d, ~(4'b0001 << d), seg_d[d], dp_d[d]);
                else $fwrite(of, "FND digit=%0d off\n", d);
            $fwrite(of, "PIN led=%04h\n", led);
        end
    endtask

    initial begin
        if (!$value$plusargs("FRAME=%s", fpath)) $fatal(1, "+FRAME required");
        if (!$value$plusargs("OUT=%s", opath)) $fatal(1, "+OUT required");
        $readmemh(fpath, frame_mem);
        for (i = 0; i < 1024; i = i + 1) if (frame_mem[i] !== 8'bx) nbytes = i + 1;
        of = $fopen(opath, "w");
        #2000 btnC = 0;                 // 버튼 Reset 해제(High 활성)
        wait (lines == 2);              // 부팅: READY, DISP
        $fwrite(of, "BOOT_DONE t_ns=%0d\n", $time);
        observe_fnd();
        $fwrite(of, "SEND bytes=%0d t_ns=%0d\n", nbytes, $time);
        for (i = 0; i < nbytes; i = i + 1) send_byte(frame_mem[i]);
        wait (lines == 4);              // RESULT, DISP
        $fwrite(of, "RESPONSE_DONE t_ns=%0d\n", $time);
        observe_fnd();
        $fwrite(of, "SOC28_SIM_END t_ns=%0d\n", $time);
        $fclose(of);
        $display("SOC28_SIM_END");
        $finish;
    end
    initial begin #400_000_000; $fatal(1, "SoC simulation timeout (lines=%0d)", lines); end
endmodule
