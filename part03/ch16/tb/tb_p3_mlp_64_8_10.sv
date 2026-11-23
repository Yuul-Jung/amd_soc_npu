// 64→8→10 정수 MLP 자동 판정 테스트벤치.
// 3-1 프레임 버퍼 + p3_mlp_64_8_10. 명령(W/B/S/F)으로 두 계층 모델과 shift를 적재·유지하며,
// 프레임마다 은닉 8개·출력 점수 10개·Class를 기록한다(Python mlp_64_8_10과 비트 단위 비교).
// 추가 판정: 프레임 없는 start, 1층 범위 밖 class(8) 쓰기, 2층 동작 중 1층 쓰기 차단(결과 불변),
// 동작 중 start 거부, done 1클록, 처리 클록 수 일정.
`timescale 1ns/1ps
module tb_p3_mlp_64_8_10;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    reg [7:0] s_data = 0;
    reg s_valid = 0, s_last = 0, frame_ack = 0;
    wire s_ready, frame_valid, x_rd_valid, err_short, err_long;
    wire x_rd_en;
    wire [5:0] x_rd_addr;
    wire signed [7:0] x_rd_data;
    reg start = 0, wr_layer = 0, w_wr = 0, b_wr = 0;
    reg [4:0] shift = 0;
    reg [3:0] wr_class = 0;
    reg [5:0] wr_addr = 0;
    reg signed [7:0] w_data = 0;
    reg signed [23:0] b_data = 0;
    wire load_ready, busy, done, error;
    wire [3:0] cls;
    wire [249:0] scores;
    wire [63:0] hidden;

    p3_frame64_buffer buffer(
        .clk(clk), .resetn(resetn),
        .s_data_i(s_data), .s_valid_i(s_valid), .s_last_i(s_last), .s_ready_o(s_ready),
        .frame_valid_o(frame_valid), .frame_ack_i(frame_ack),
        .rd_en_i(x_rd_en), .rd_addr_i(x_rd_addr), .rd_data_o(x_rd_data), .rd_valid_o(x_rd_valid),
        .err_short_o(err_short), .err_long_o(err_long));
    p3_mlp_64_8_10 mlp(
        .clk(clk), .resetn(resetn), .start_i(start), .shift_i(shift), .x_valid_i(frame_valid),
        .x_rd_en_o(x_rd_en), .x_rd_addr_o(x_rd_addr), .x_rd_data_i(x_rd_data),
        .wr_layer_i(wr_layer), .w_wr_en_i(w_wr), .b_wr_en_i(b_wr), .wr_class_i(wr_class),
        .wr_addr_i(wr_addr), .w_data_i(w_data), .b_data_i(b_data), .load_ready_o(load_ready),
        .busy_o(busy), .done_o(done), .error_o(error), .class_o(cls),
        .scores_o(scores), .hidden_o(hidden));

    integer n_error = 0, err_before = 0;
    reg prev_done = 0;
    always @(posedge clk) begin
        if (resetn) begin
            if (error) n_error = n_error + 1;
            if (done && prev_done) $fatal(1, "done longer than 1 clock");
            if (load_ready === busy) $fatal(1, "load_ready must be !busy");
            if (x_rd_en && !frame_valid) $fatal(1, "layer1 read without frame");
            if (err_short || err_long) $fatal(1, "unexpected frame error");
        end
        prev_done = done;
    end

    task automatic write_op(input integer layer, input integer is_bias, input integer c,
                            input integer a, input integer v);
        begin
            @(negedge clk);
            wr_layer = layer; wr_class = c; wr_addr = a;
            if (is_bias) begin b_wr = 1; b_data = v; end
            else begin w_wr = 1; w_data = v; end
            @(negedge clk);
            w_wr = 0; b_wr = 0;
        end
    endtask
    task automatic check_error(input [8*40-1:0] what);
        begin
            @(negedge clk);
            if (n_error != err_before + 1) $fatal(1, "missing error: %0s", what);
            err_before = n_error;
        end
    endtask

    reg [8*8-1:0] tag;
    integer p4_shift = 0;
    reg signed [7:0] w_before;
    reg signed [23:0] b_before;
    integer f_ops, f_act, rc, p1, p2, p3, p4, k, v, cyc, cyc_ref = -1, n_frames = 0;
    reg signed [7:0] xbuf [0:63];
    reg [8*256-1:0] ops_path, act_path;
    initial begin
        if (!$value$plusargs("OPS=%s", ops_path)) $fatal(1, "+OPS required");
        if (!$value$plusargs("ACTUAL=%s", act_path)) $fatal(1, "+ACTUAL required");
        f_ops = $fopen(ops_path, "r");
        f_act = $fopen(act_path, "w");
        repeat (4) @(negedge clk);
        resetn = 1;
        @(negedge clk);
        // 프레임 없는 start
        start = 1; @(negedge clk); start = 0;
        check_error("start without frame");
        if (busy) $fatal(1, "started without frame");
        // 1층은 8출력이므로 class 8 쓰기는 거부
        write_op(0, 0, 8, 0, 5);
        check_error("layer1 class 8 write");
        tag = "";
        while (tag != "E") begin
            rc = $fscanf(f_ops, "%s %d %d %d %d", tag, p1, p2, p3, p4);
            if (rc != 5) $fatal(1, "bad op line");
            if (tag == "W") write_op(p1, 0, p2, p3, p4);
            else if (tag == "B") write_op(p1, 1, p2, 0, p4);
            else if (tag == "S") begin shift = p4; p4_shift = p4; end
            else if (tag == "F") begin
                for (k = 0; k < 64; k = k + 1) begin
                    rc = $fscanf(f_ops, "%d", v);
                    xbuf[k] = v;
                end
                for (k = 0; k < 64; k = k + 1) begin
                    @(negedge clk);
                    s_data = xbuf[k]; s_valid = 1; s_last = (k == 63);
                    while (!s_ready) @(negedge clk);
                end
                @(negedge clk);
                s_valid = 0; s_last = 0;
                start = 1;
                @(negedge clk);
                start = 0;
                // shift는 start 시점에 래치되어야 한다: 동작 중 입력을 반전해도 결과 불변
                shift = ~p4_shift;
                cyc = 1;
                if (n_frames == 0) begin
                    // 2층 동작 구간까지 기다린 뒤 1층 가중치·Bias 쓰기 시도: 차단되어야 결과 불변
                    while (!mlp.layer2.busy_o) begin @(negedge clk); cyc = cyc + 1; end
                    // 화이트박스: 차단된 쓰기 전후 1층 bank0[0]·bias[0] 불변 확인
                    w_before = mlp.layer1.bank0[0];
                    b_before = mlp.layer1.bias[0];
                    @(negedge clk); wr_layer = 0; w_wr = 1; wr_class = 0; wr_addr = 0;
                    w_data = ~w_before;
                    @(negedge clk); w_wr = 0; b_wr = 1; b_data = 12345;
                    @(negedge clk); b_wr = 0; start = 1;
                    @(negedge clk); start = 0;
                    @(negedge clk);
                    cyc = cyc + 5;
                    if (n_error != err_before + 3) $fatal(1, "busy writes/start not rejected");
                    if (mlp.layer1.bank0[0] !== w_before || mlp.layer1.bias[0] !== b_before)
                        $fatal(1, "layer1 model modified by write during MLP busy");
                    err_before = n_error;
                end
                while (!done) begin
                    @(negedge clk);
                    cyc = cyc + 1;
                    if (cyc > 2000) $fatal(1, "MLP timeout");
                end
                if (busy) $fatal(1, "busy after done");
                shift = p4_shift;
                if (cyc_ref < 0) cyc_ref = cyc;
                else if (cyc != cyc_ref) $fatal(1, "cycle count changed %0d vs %0d", cyc, cyc_ref);
                $fwrite(f_act, "H");
                for (k = 0; k < 8; k = k + 1)
                    $fwrite(f_act, " %0d", $signed(hidden[k*8 +: 8]));
                $fwrite(f_act, " S");
                for (k = 0; k < 10; k = k + 1)
                    $fwrite(f_act, " %0d", $signed(scores[k*25 +: 25]));
                $fwrite(f_act, " C%0d\n", cls);
                frame_ack = 1;
                @(negedge clk);
                frame_ack = 0;
                n_frames = n_frames + 1;
                if (n_error != err_before) $fatal(1, "unexpected error in frame %0d", n_frames);
            end
        end
        $fclose(f_act);
        $display("RTL_SIM_PASS MLP64_8_10 frames=%0d start_to_done_cycles=%0d errors_checked=%0d",
            n_frames, cyc_ref, n_error);
        $finish;
    end
    initial begin #200000000; $fatal(1, "TB timeout"); end
endmodule
