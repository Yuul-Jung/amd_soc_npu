// p3_alarm_policy 벡터 시험. Python sensor_reference.policy_vectors가 만든 클록별 입력·기대값
//   (rst cv cand ack | state latch cnt ack_ok alarm)을 그대로 대조한다. 지정 시나리오 + 무작위 4000클록.
`timescale 1ns/1ps
module tb_p3_alarm_policy;
    reg clk = 0, rst = 1, cv = 0, ack = 0;
    reg [1:0] cand = 0;
    wire [1:0] state, cnt;
    wire latch, ack_ok, alarm;
    wire [3:0] onehot;
    always #5 clk = ~clk;

    p3_alarm_policy #(.CLEAR_N(3)) dut(
        .clk(clk), .rst(rst), .cand_valid(cv), .cand(cand), .ack(ack),
        .state(state), .latch(latch), .cnt(cnt), .ack_ok(ack_ok), .alarm_o(alarm), .state_onehot(onehot));

    reg [8*256-1:0] vpath;
    integer f, r, n = 0, errors = 0, e_rst, e_cv, e_cand, e_ack, x_state, x_latch, x_cnt, x_ok, x_alarm;
    integer n_fault = 0, n_ackok = 0, n_down = 0;
    reg [1:0] prev_state;
    initial begin
        if (!$value$plusargs("VEC=%s", vpath)) $fatal(1, "+VEC required");
        f = $fopen(vpath, "r");
        if (f == 0) $fatal(1, "cannot open vectors");
        @(negedge clk);
        prev_state = 2'd3;
        while (!$feof(f)) begin
            r = $fscanf(f, "%d %d %d %d %d %d %d %d %d\n", e_rst, e_cv, e_cand, e_ack, x_state, x_latch, x_cnt, x_ok, x_alarm);
            if (r == 9) begin
                rst = e_rst; cv = e_cv; cand = e_cand; ack = e_ack;
                @(posedge clk); #1;
                if (state !== x_state || latch !== x_latch || cnt !== x_cnt || ack_ok !== x_ok || alarm !== x_alarm
                    || onehot !== (4'b1 << x_state)) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("MISMATCH row=%0d in=%0d%0d%0d%0d got s=%0d l=%0d c=%0d ok=%0d a=%0d exp %0d %0d %0d %0d %0d",
                                 n, e_rst, e_cv, e_cand, e_ack, state, latch, cnt, ack_ok, alarm,
                                 x_state, x_latch, x_cnt, x_ok, x_alarm);
                end
                if (state == 2'd2 && prev_state != 2'd2) n_fault = n_fault + 1;
                if (ack_ok) n_ackok = n_ackok + 1;
                if (!e_rst && e_cv && state != prev_state && state != e_cand) n_down = n_down + 1;
                prev_state = state;
                n = n + 1;
                @(negedge clk);
            end
        end
        if (errors == 0 && n > 100)
            $display("RTL_SIM_PASS ALARM_POLICY cycles=%0d fault_entries=%0d ack_ok=%0d hold_max_downs=%0d", n, n_fault, n_ackok, n_down);
        else
            $display("RTL_SIM_FAIL ALARM_POLICY cycles=%0d errors=%0d", n, errors);
        $finish;
    end
endmodule
