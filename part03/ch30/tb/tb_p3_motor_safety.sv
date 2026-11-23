// p3_motor_safety 클록 단위 벡터 시험(UNIT 파라미터). Python motor_reference.unit_vectors가 만든
//   입력(rst cmd estop fault otemp lim_f lim_r)과 기대 출력(in1 in2 ena status 32비트)을 클록마다 대조한다.
//   Python 쪽에서 같은 출력이 안전 불변식(정지 조건 중 출력 0, IN1·IN2 동시 금지, 반전 데드타임)을 지키는지도 확인한다.
`timescale 1ns/1ps
module tb_p3_motor_safety;
    reg clk = 0, rst = 1, estop = 0, fault = 0, otemp = 0, lim_f = 0, lim_r = 0;
    reg [31:0] cmd = 0;
    wire in1, in2, ena;
    wire [31:0] status;
    always #5 clk = ~clk;

    p3_motor_safety #(.PWM_PERIOD(100), .DEAD_CYC(9), .WD_CYC(70), .RAMP_CYC(3)) dut(
        .clk(clk), .rst(rst), .cmd(cmd), .estop(estop), .fault(fault), .otemp(otemp), .lim_f(lim_f), .lim_r(lim_r),
        .in1(in1), .in2(in2), .ena(ena), .status(status));

    reg [8*256-1:0] vpath;
    integer f, r, n = 0, errors = 0, e_rst, e_es, e_fa, e_ot, e_lf, e_lr, x1, x2, xe, n_ena = 0, n_trip = 0;
    reg [31:0] e_cmd, xs;
    initial begin
        if (!$value$plusargs("VEC=%s", vpath)) $fatal(1, "+VEC required");
        f = $fopen(vpath, "r");
        if (f == 0) $fatal(1, "cannot open vectors");
        @(negedge clk);
        while (!$feof(f)) begin
            r = $fscanf(f, "%d %h %d %d %d %d %d %d %d %d %h\n", e_rst, e_cmd, e_es, e_fa, e_ot, e_lf, e_lr, x1, x2, xe, xs);
            if (r == 11) begin
                rst = e_rst; cmd = e_cmd; estop = e_es; fault = e_fa; otemp = e_ot; lim_f = e_lf; lim_r = e_lr;
                #1;
                if (!e_rst && (in1 !== x1[0] || in2 !== x2[0] || ena !== xe[0] || status !== xs)) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("MISMATCH row=%0d cmd=%h got %0d%0d%0d %h exp %0d%0d%0d %h", n, cmd, in1, in2, ena, status,
                                 x1, x2, xe, xs);
                end
                if (ena) n_ena = n_ena + 1;
                if (status[14]) n_trip = n_trip + 1;
                @(posedge clk);
                n = n + 1;
                @(negedge clk);
            end
        end
        if (errors == 0 && n > 1000 && n_ena > 0)
            $display("RTL_SIM_PASS MOTOR_SAFETY cycles=%0d ena_cycles=%0d trip_cycles=%0d", n, n_ena, n_trip);
        else
            $display("RTL_SIM_FAIL MOTOR_SAFETY cycles=%0d errors=%0d", n, errors);
        $finish;
    end
endmodule
