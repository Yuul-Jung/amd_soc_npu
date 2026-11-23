// p3_group10_core 자동 판정 테스트벤치.
// 3-1 p3_frame64_buffer 실제 RTL과 연결: 스트림 → 프레임 버퍼 → 4PE 3그룹 → 10점수·Class.
// Python 벡터(가중치·Bias·입력)를 쓰기 포트로 적재하고 결과를 actual에 기록한다(Python이 비트 단위 비교).
// 추가 판정: 프레임 없는 start 거부, Busy 중 쓰기·start 거부, 범위 밖 class 거부, Busy 중 Reset 후 재실행,
// done 1클록 펄스, 처리 클록 수 일정, x 읽기는 프레임 보관 중에만.
`timescale 1ns/1ps
module tb_p3_group10_core;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;

    reg [7:0] s_data = 0;
    reg s_valid = 0, s_last = 0, frame_ack = 0;
    wire s_ready, frame_valid, x_rd_valid, err_short, err_long;
    wire x_rd_en;
    wire [5:0] x_rd_addr;
    wire signed [7:0] x_rd_data;
    reg start = 0, w_wr = 0, b_wr = 0;
    reg [3:0] wr_class = 0;
    reg [5:0] wr_addr = 0;
    reg signed [7:0] w_data = 0;
    reg signed [23:0] b_data = 0;
    wire load_ready, busy, done, error;
    wire [3:0] cls;
    wire [249:0] scores;

    p3_frame64_buffer buffer(
        .clk(clk), .resetn(resetn),
        .s_data_i(s_data), .s_valid_i(s_valid), .s_last_i(s_last), .s_ready_o(s_ready),
        .frame_valid_o(frame_valid), .frame_ack_i(frame_ack),
        .rd_en_i(x_rd_en), .rd_addr_i(x_rd_addr), .rd_data_o(x_rd_data), .rd_valid_o(x_rd_valid),
        .err_short_o(err_short), .err_long_o(err_long));
    p3_group10_core core(
        .clk(clk), .resetn(resetn), .start_i(start), .x_valid_i(frame_valid),
        .x_rd_en_o(x_rd_en), .x_rd_addr_o(x_rd_addr), .x_rd_data_i(x_rd_data),
        .w_wr_en_i(w_wr), .b_wr_en_i(b_wr), .wr_class_i(wr_class), .wr_addr_i(wr_addr),
        .w_data_i(w_data), .b_data_i(b_data), .load_ready_o(load_ready),
        .busy_o(busy), .done_o(done), .error_o(error), .class_o(cls), .scores_o(scores));

    // 상시 규칙 검사
    integer n_error = 0, n_done = 0;
    reg prev_done = 0;
    always @(posedge clk) begin
        if (resetn) begin
            if (x_rd_en && !frame_valid) $fatal(1, "core read x without held frame");
            if (done && prev_done) $fatal(1, "done longer than 1 clock");
            if (load_ready === busy) $fatal(1, "load_ready must be !busy");
            if (err_short || err_long) $fatal(1, "unexpected frame error");
            if (error) n_error = n_error + 1;
            if (done) n_done = n_done + 1;
        end
        prev_done = done;
    end

    integer x [0:63];
    integer w [0:9][0:63];
    integer b [0:9];
    integer tmp, vf, af, rc, ncase, cidx, i, c, cyc, cyc_ref, err_before;
    reg [8*256-1:0] vpath, apath;

    task automatic load_model;
        begin
            for (c = 0; c < 10; c = c + 1)
                for (i = 0; i < 64; i = i + 1) begin
                    @(negedge clk);
                    w_wr = 1; wr_class = c; wr_addr = i; w_data = w[c][i];
                end
            for (c = 0; c < 10; c = c + 1) begin
                @(negedge clk);
                w_wr = 0; b_wr = 1; wr_class = c; b_data = b[c];
            end
            @(negedge clk);
            w_wr = 0; b_wr = 0;
        end
    endtask
    task automatic send_frame;
        integer k;
        begin
            for (k = 0; k < 64; k = k + 1) begin
                @(negedge clk);
                s_data = x[k]; s_valid = 1; s_last = (k == 63);
                while (!s_ready) @(negedge clk);
            end
            @(negedge clk);
            s_valid = 0; s_last = 0;
            if (!frame_valid) $fatal(1, "frame not held after 64 bytes");
        end
    endtask
    task automatic pulse_start;
        begin
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
        end
    endtask
    task automatic expect_error(input [8*40-1:0] what);
        begin
            @(negedge clk);
            if (n_error != err_before + 1) $fatal(1, "missing error pulse: %0s", what);
            err_before = n_error;
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vpath)) $fatal(1, "+VECTORS required");
        if (!$value$plusargs("ACTUAL=%s", apath)) $fatal(1, "+ACTUAL required");
        vf = $fopen(vpath, "r");
        af = $fopen(apath, "w");
        rc = $fscanf(vf, "%d", ncase);
        repeat (4) @(negedge clk);
        resetn = 1;
        @(negedge clk);
        cyc_ref = -1;
        err_before = 0;

        // 프레임 없이 start → 거부
        pulse_start;
        if (busy) $fatal(1, "started without frame");
        expect_error("start without frame");
        // 범위 밖 class 쓰기 → 거부
        @(negedge clk); w_wr = 1; wr_class = 10; wr_addr = 0; w_data = 5;
        @(negedge clk); w_wr = 0;
        expect_error("class 10 write");

        for (cidx = 0; cidx < ncase; cidx = cidx + 1) begin
            // 배열 원소에 직접 $fscanf하지 않고 임시 변수로 읽는다.
            for (i = 0; i < 64; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); x[i] = tmp; end
            for (c = 0; c < 10; c = c + 1)
                for (i = 0; i < 64; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); w[c][i] = tmp; end
            for (c = 0; c < 10; c = c + 1) begin rc = $fscanf(vf, "%d", tmp); b[c] = tmp; end
            load_model;
            send_frame;

            if (cidx == 1) begin
                // Busy 중 Reset: 프레임·Bias 소실 → 재적재 후 재실행
                pulse_start;
                repeat (50) @(negedge clk);
                if (!busy) $fatal(1, "not busy before reset test");
                resetn = 0;
                repeat (3) @(negedge clk);
                resetn = 1;
                @(negedge clk);
                if (busy || frame_valid) $fatal(1, "reset did not clear busy/frame");
                load_model;
                send_frame;
            end

            pulse_start;
            cyc = 1;
            if (cidx == 0) begin
                // Busy 중 쓰기와 start는 무시·오류. 결과는 Python 기대값 그대로여야 한다.
                @(negedge clk); w_wr = 1; wr_class = 0; wr_addr = 0; w_data = 99;
                @(negedge clk); w_wr = 0;
                @(negedge clk); start = 1;
                @(negedge clk); start = 0;
                // 오류 펄스는 다음 상승 에지에서 계수되므로 한 클록 더 기다린다.
                @(negedge clk);
                cyc = cyc + 5;
                if (n_error != err_before + 2) $fatal(1, "busy write/start not rejected");
                err_before = n_error;
            end
            while (!done) begin
                @(negedge clk);
                cyc = cyc + 1;
                if (cyc > 1000) $fatal(1, "core timeout");
            end
            if (busy) $fatal(1, "busy after done");
            if (cyc_ref < 0) cyc_ref = cyc;
            else if (cyc != cyc_ref) $fatal(1, "cycle count changed %0d vs %0d", cyc, cyc_ref);
            for (c = 0; c < 10; c = c + 1)
                $fwrite(af, "%0d ", $signed(scores[c*25 +: 25]));
            $fwrite(af, "C%0d\n", cls);
            @(negedge clk);
            frame_ack = 1;
            @(negedge clk);
            frame_ack = 0;
            if (n_error != err_before) $fatal(1, "unexpected error pulse in case %0d", cidx);
        end
        $fclose(af);
        $display("RTL_SIM_PASS GROUP10 cases=%0d start_to_done_cycles=%0d errors_checked=%0d",
            ncase, cyc_ref, n_error);
        $finish;
    end
    initial begin #50000000; $fatal(1, "TB timeout"); end
endmodule
