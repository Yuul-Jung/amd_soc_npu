`timescale 1ns/1ps
// 30장 TB: 시나리오 입력을 클록마다 넣고 출력(en, pwm, dir, speed, block)을 클록마다 기록한다. Python 모델과 클록 단위로 비교한다.
module tb_motor_interlock;
    reg clk=0, rn=0, en_n=1, arm=0, en=0, av=0, ad=0; reg [2:0] sens=0; reg [7:0] asp=0;
    wire e, pwm, dir; wire [7:0] spd; wire [4:0] blk;
    motor_interlock #(.TICK(16), .STEP(8), .WD_LIMIT(400)) dut(.clk(clk), .resetn(rn), .estop_n_i(en_n), .arm_i(arm),
        .enable_i(en), .sensor_state_i(sens), .ai_valid_i(av), .ai_speed_i(asp), .ai_dir_i(ad),
        .en_o(e), .pwm_o(pwm), .dir_o(dir), .speed_o(spd), .block_o(blk));
    always #5 clk = ~clk;
    integer f, o, a0, a1, a2, a3, a4, a5, a6, n = 0; string vp, ap;
    initial begin
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap)) $fatal(1, "경로 인자");
        f = $fopen(vp, "r"); o = $fopen(ap, "w"); if (!f || !o) $fatal(1, "파일 열기");
        @(negedge clk); @(negedge clk); rn = 1;
        while ($fscanf(f, "%d %d %d %d %d %d %d", a0, a1, a2, a3, a4, a5, a6) == 7) begin
            en_n = a0; arm = a1; en = a2; sens = a3; av = a4; asp = a5; ad = a6;
            #1 $fwrite(o, "%0d %0d %0d %0d %0d\n", e, pwm, dir, spd, blk);   // 이 클록의 출력 (입력 반영 후 조합값)
            @(negedge clk); n = n + 1;
        end
        $display("RTL_SIM_PASS MOTOR_INTERLOCK cycles=%0d", n);
        $fclose(o); $finish;
    end
endmodule
