// (추가) 17장 p3_tile784_10 자동 판정 테스트벤치.
// 13장 p3_frame64_buffer 실제 RTL과 연결: 타일마다 W 적재 → 64바이트 프레임 → tile_go → 부분합 누산.
// 마지막 타일은 W를 16주소만 다시 쓰고(나머지 48주소는 타일 11 가중치 잔류), x 주소 16~63에는 0이 아닌
// 쓰레기 값을 보낸다. 타일별 부분합·최종 점수·Class·overflow를 actual에 기록하고 Python이 비트 단위 비교.
// +FULL 추가 판정: 상태별 명령 거부, 타일 중복·누락, 프레임 없는 tile_go, 동작 중 W/Bias 쓰기 거부,
// RUN·LOAD 중 Reset 후 재실행, LOAD 중 취소 후 재실행, 코어 Bias 0 유지(화이트박스).
// (변경) 18장: DATA_W 파라미터. 8이면 위와 같이 13장 8비트 프레임 버퍼를 쓰고,
// 16이면 04장 bram_sync_buffer(16비트×64)에 x 타일을 쓴 뒤 TB가 프레임 보관 플래그를 세운다
// (frame_ack까지 다음 타일 쓰기 대기 = 13장 버퍼의 s_ready 계약과 같은 순서 규칙).
`timescale 1ns/1ps
module tb_p3_tile784_10;
    parameter integer ACC_W = 41;
    parameter integer BIAS_W = 40;
    parameter integer DATA_W = 8;
    localparam integer SCORE_W = ((ACC_W > BIAS_W) ? ACC_W : BIAS_W) + 1;
    localparam integer CORE_ACC_W = (DATA_W == 8) ? 24 : 2 * DATA_W + 6;
    localparam integer PART_W = ((CORE_ACC_W > 24) ? CORE_ACC_W : 24) + 1;
    localparam [2:0] ERR_STATE=3'd1, ERR_TILE_DUP=3'd2, ERR_TILE_SKIP=3'd3,
                     ERR_NO_FRAME=3'd4, ERR_WRITE=3'd5;
    localparam integer MODE_CLEAN=0, MODE_ERRORS=1, MODE_RESET_RUN=2, MODE_RESET_LOAD=3,
                       MODE_ABORT=4;

    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;

    reg [7:0] s_data = 0;
    reg s_valid = 0, s_last = 0;
    wire s_ready, frame_valid, frame_ack, x_rd_valid, err_short, err_long;
    wire x_rd_en;
    wire [5:0] x_rd_addr;
    wire signed [DATA_W-1:0] x_rd_data;
    reg start = 0, abort = 0, tile_go = 0, w_wr = 0, b_wr = 0;
    reg [3:0] tile_id = 0, wr_class = 0;
    reg [5:0] wr_addr = 0;
    reg signed [DATA_W-1:0] w_data = 0;
    reg signed [BIAS_W-1:0] b_data = 0;
    wire load_ready, busy, done, error, ovf, tile_done;
    wire [2:0] err_code;
    wire [3:0] tile_idx, cls;
    wire [10*PART_W-1:0] parts;
    wire [10*SCORE_W-1:0] scores;
    // DATA_W > 8: 04장 버퍼 쓰기 포트와 TB 프레임 보관 플래그
    reg x_wr = 0, x_commit = 0, x_held = 0;
    reg [5:0] x_wr_addr = 0;
    reg signed [DATA_W-1:0] x_wr_data = 0;

    generate
        if (DATA_W == 8) begin : buf8
            p3_frame64_buffer buffer(
                .clk(clk), .resetn(resetn),
                .s_data_i(s_data), .s_valid_i(s_valid), .s_last_i(s_last), .s_ready_o(s_ready),
                .frame_valid_o(frame_valid), .frame_ack_i(frame_ack),
                .rd_en_i(x_rd_en), .rd_addr_i(x_rd_addr), .rd_data_o(x_rd_data),
                .rd_valid_o(x_rd_valid), .err_short_o(err_short), .err_long_o(err_long));
        end else begin : bufw
            bram_sync_buffer #(.DATA_WIDTH(DATA_W), .ADDR_WIDTH(6)) buffer(
                .clk(clk), .resetn(resetn), .wr_en(x_wr), .rd_en(x_rd_en),
                .wr_addr(x_wr_addr), .rd_addr(x_rd_addr), .wr_data(x_wr_data),
                .rd_data(x_rd_data), .rd_valid(x_rd_valid));
            always @(posedge clk)
                if (!resetn || frame_ack) x_held <= 1'b0;
                else if (x_commit) x_held <= 1'b1;
            assign frame_valid = x_held;
            assign s_ready = resetn && !x_held;
            assign err_short = 1'b0;
            assign err_long = 1'b0;
        end
    endgenerate
    p3_tile784_10 #(.ACC_W(ACC_W), .BIAS_W(BIAS_W), .SCORE_W(SCORE_W), .DATA_W(DATA_W),
                    .CORE_ACC_W(CORE_ACC_W), .PART_W(PART_W)) dut(
        .clk(clk), .resetn(resetn), .start_i(start), .abort_i(abort),
        .tile_go_i(tile_go), .tile_id_i(tile_id),
        .x_valid_i(frame_valid), .x_rd_en_o(x_rd_en), .x_rd_addr_o(x_rd_addr),
        .x_rd_data_i(x_rd_data), .frame_ack_o(frame_ack),
        .w_wr_en_i(w_wr), .b_wr_en_i(b_wr), .wr_class_i(wr_class), .wr_addr_i(wr_addr),
        .w_data_i(w_data), .b_data_i(b_data), .load_ready_o(load_ready),
        .busy_o(busy), .done_o(done), .error_o(error), .err_code_o(err_code), .ovf_o(ovf),
        .tile_idx_o(tile_idx), .tile_done_o(tile_done), .part_scores_o(parts),
        .class_o(cls), .scores_o(scores));

    // 상시 규칙 검사
    integer n_error = 0, last_code = 0, cycle = 0, go_cycle = 0, tile_cyc = -1, k;
    reg prev_done = 0, prev_tile_done = 0, abort_expected = 0;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (resetn) begin
            if (x_rd_en && !frame_valid) $fatal(1, "core read x without held frame");
            if (done && prev_done) $fatal(1, "done longer than 1 clock");
            if (tile_done && prev_tile_done) $fatal(1, "tile_done longer than 1 clock");
            if (err_short || err_long) $fatal(1, "unexpected frame error");
            // 결과 수락(tile_done)과 같은 클록 또는 취소일 때만 프레임 해제
            if (frame_ack && !tile_done && !abort_expected) $fatal(1, "frame released early");
            // 코어 계산 중에는 다음 타일 프레임·가중치가 들어갈 수 없다
            if (dut.core.busy_o && s_ready) $fatal(1, "next tile frame accepted during compute");
            if (dut.core.busy_o && dut.core.w_wr_en_i) $fatal(1, "core weight write during compute");
            if (dut.core.error_o) $fatal(1, "core error leaked through controller");
            // Bias 중복 방지: 코어 Bias는 항상 0
            for (k = 0; k < 10; k = k + 1)
                if (dut.core.bias[k] !== 24'sd0) $fatal(1, "core bias[%0d] not zero", k);
            if (x_wr && x_held) $fatal(1, "x tile overwritten while held");
            if (error) begin
                n_error = n_error + 1;
                last_code = err_code;
            end
            if (dut.core_start_q) go_cycle = cycle;
            if (tile_done) begin
                if (tile_cyc < 0) tile_cyc = cycle - go_cycle;
                else if (cycle - go_cycle != tile_cyc)
                    $fatal(1, "tile cycles changed %0d vs %0d", cycle - go_cycle, tile_cyc);
            end
        end
        prev_done = done;
        prev_tile_done = tile_done;
    end

    integer X [0:783];
    integer PAD [0:47];
    integer W [0:9][0:783];
    reg signed [63:0] B [0:9];
    reg signed [63:0] P [0:12][0:9];  // 완주한 추론의 타일별 부분합
    reg signed [63:0] tmp64;
    integer tmp, vf, af, rc, ncase, cidx, i, c, err_before, full;
    reg [8*256-1:0] vpath, apath;

    task automatic expect_error(input [2:0] code, input [8*40-1:0] what);
        begin
            @(negedge clk);
            if (n_error != err_before + 1 || last_code != code)
                $fatal(1, "missing error %0d (got count %0d code %0d): %0s",
                       code, n_error - err_before, last_code, what);
            err_before = n_error;
        end
    endtask
    task automatic pulse_start;
        begin @(negedge clk); start = 1; @(negedge clk); start = 0; end
    endtask
    task automatic pulse_abort;
        begin @(negedge clk); abort = 1; @(negedge clk); abort = 0; end
    endtask
    task automatic pulse_go(input integer id);
        begin @(negedge clk); tile_go = 1; tile_id = id; @(negedge clk); tile_go = 0; end
    endtask
    task automatic write_w(input integer cl, input integer addr, input integer val);
        begin
            @(negedge clk); w_wr = 1; wr_class = cl; wr_addr = addr; w_data = val;
            @(negedge clk); w_wr = 0;
        end
    endtask
    task automatic write_b(input integer cl, input reg signed [63:0] val);
        begin
            @(negedge clk); b_wr = 1; wr_class = cl; b_data = val;
            @(negedge clk); b_wr = 0;
        end
    endtask
    task automatic load_bias;
        begin
            for (c = 0; c < 10; c = c + 1) begin
                @(negedge clk);
                b_wr = 1; wr_class = c; b_data = B[c];
            end
            @(negedge clk);
            b_wr = 0;
        end
    endtask
    // 타일 t의 가중치: class c, 주소 i ← W[c][64t+i]. 마지막 타일은 유효 16주소만 쓴다.
    task automatic load_tile_w(input integer t, input integer len);
        begin
            for (c = 0; c < 10; c = c + 1)
                for (i = 0; i < len; i = i + 1) begin
                    @(negedge clk);
                    if (!load_ready) $fatal(1, "weight load not ready");
                    w_wr = 1; wr_class = c; wr_addr = i; w_data = W[c][64*t + i];
                end
            @(negedge clk);
            w_wr = 0;
        end
    endtask
    task automatic send_tile_x(input integer t, input integer len);
        integer j;
        begin
            if (DATA_W == 8) begin
                for (j = 0; j < 64; j = j + 1) begin
                    @(negedge clk);
                    s_data = (j < len) ? X[64*t + j] : PAD[j - len];
                    s_valid = 1; s_last = (j == 63);
                    while (!s_ready) @(negedge clk);
                end
                @(negedge clk);
                s_valid = 0; s_last = 0;
            end else begin
                while (!s_ready) @(negedge clk);
                for (j = 0; j < 64; j = j + 1) begin
                    @(negedge clk);
                    x_wr = 1; x_wr_addr = j;
                    x_wr_data = (j < len) ? X[64*t + j] : PAD[j - len];
                end
                @(negedge clk);
                x_wr = 0; x_commit = 1;
                @(negedge clk);
                x_commit = 0;
            end
            if (!frame_valid) $fatal(1, "tile %0d frame not held", t);
        end
    endtask
    task automatic do_reset;
        begin
            @(negedge clk);
            resetn = 0;
            repeat (3) @(negedge clk);
            resetn = 1;
            @(negedge clk);
            if (busy || frame_valid || ovf || tile_idx != 0 || !load_ready || dut.state != 0)
                $fatal(1, "reset did not return controller to IDLE");
        end
    endtask

    // 한 번의 784 추론. mode에 따라 오류 주입·중도 Reset·취소. 완주한 경우만 기록한다.
    task automatic run_inference(input integer mode);
        integer t, len, j;
        reg cut;
        begin
            cut = 0;
            load_bias;
            pulse_start;
            if (!busy) $fatal(1, "start not accepted");
            for (t = 0; t < 13 && !cut; t = t + 1) begin
                len = (t == 12) ? 16 : 64;
                // 결과 수락(ACK) 1클록 뒤 LOAD로 돌아온다
                j = 0;
                while (!load_ready) begin
                    @(negedge clk);
                    j = j + 1;
                    if (j > 2) $fatal(1, "load_ready not restored before tile %0d", t);
                end
                if (tile_idx != t || frame_valid) $fatal(1, "not waiting for tile %0d", t);
                load_tile_w(t, len);
                if (mode == MODE_ERRORS && t == 2) begin
                    pulse_go(2);
                    expect_error(ERR_NO_FRAME, "tile_go without frame");
                end
                if (mode == MODE_ERRORS && t == 4) begin
                    // 추론 중 Bias 변경·범위 밖 class·중복 start는 거부(결과 불변으로 확인)
                    write_b(3, 12345);
                    expect_error(ERR_WRITE, "bias write during inference");
                    write_w(10, 0, 7);
                    expect_error(ERR_WRITE, "class 10 weight write");
                    pulse_start;
                    expect_error(ERR_STATE, "start while active");
                end
                send_tile_x(t, len);
                if (mode == MODE_RESET_LOAD && t == 8) begin
                    do_reset;
                    cut = 1;
                end else if (mode == MODE_ABORT && t == 7) begin
                    abort_expected = 1;
                    pulse_abort;
                    @(negedge clk);
                    abort_expected = 0;
                    if (busy || frame_valid || !s_ready || !load_ready) $fatal(1, "abort did not release");
                    if (n_error != err_before) $fatal(1, "abort raised error");
                    cut = 1;
                end else begin
                    if (mode == MODE_ERRORS && t == 1) begin
                        pulse_go(0);
                        expect_error(ERR_TILE_DUP, "duplicate tile 0");
                        pulse_go(2);
                        expect_error(ERR_TILE_SKIP, "skip tile 1");
                        pulse_go(13);
                        expect_error(ERR_TILE_SKIP, "tile id 13");
                    end
                    pulse_go(t);
                    if (mode == MODE_ERRORS && t == 3) begin
                        // 계산 중: W(마지막 그룹이 늦게 읽는 class 9, 주소 63)·Bias 쓰기, 명령 모두 거부
                        write_w(9, 63, 99);
                        expect_error(ERR_WRITE, "weight write during compute");
                        write_b(0, 1);
                        expect_error(ERR_WRITE, "bias write during compute");
                        pulse_start;
                        expect_error(ERR_STATE, "start during compute");
                        pulse_go(3);
                        expect_error(ERR_STATE, "tile_go during compute");
                        pulse_abort;
                        expect_error(ERR_STATE, "abort during compute");
                        if (s_ready) $fatal(1, "next frame accepted during compute");
                    end
                    if (mode == MODE_RESET_RUN && t == 5) begin
                        repeat (50) @(negedge clk);
                        if (!dut.core.busy_o) $fatal(1, "core not running before reset");
                        do_reset;
                        cut = 1;
                    end else begin
                        j = 0;
                        while (!tile_done) begin
                            @(negedge clk);
                            j = j + 1;
                            if (j > 1000) $fatal(1, "tile %0d timeout", t);
                        end
                        if (tile_idx != t) $fatal(1, "tile_done index %0d != %0d", tile_idx, t);
                        if (!busy || done) $fatal(1, "busy/done wrong after tile %0d", t);
                        for (c = 0; c < 10; c = c + 1)
                            P[t][c] = $signed(parts[c*PART_W +: PART_W]);
                    end
                end
            end
            if (!cut) begin
                j = 0;
                while (!done) begin
                    @(negedge clk);
                    j = j + 1;
                    if (j > 20) $fatal(1, "done timeout");
                end
                if (busy || !load_ready) $fatal(1, "busy after done");
                for (t = 0; t < 13; t = t + 1) begin
                    $fwrite(af, "T%0d", t);
                    for (c = 0; c < 10; c = c + 1)
                        $fwrite(af, " %0d", P[t][c]);
                    $fwrite(af, "\n");
                end
                $fwrite(af, "S");
                for (c = 0; c < 10; c = c + 1)
                    $fwrite(af, " %0d", $signed(scores[c*SCORE_W +: SCORE_W]));
                $fwrite(af, " C%0d O%0d\n", cls, ovf);
                if (n_error != err_before) $fatal(1, "unexpected error pulse (code %0d)", last_code);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vpath)) $fatal(1, "+VECTORS required");
        if (!$value$plusargs("ACTUAL=%s", apath)) $fatal(1, "+ACTUAL required");
        full = $test$plusargs("FULL");
        vf = $fopen(vpath, "r");
        af = $fopen(apath, "w");
        rc = $fscanf(vf, "%d", ncase);
        repeat (4) @(negedge clk);
        resetn = 1;
        @(negedge clk);
        err_before = 0;
        if (full) begin
            // IDLE에서는 start만 허용
            pulse_go(0);
            expect_error(ERR_STATE, "tile_go in IDLE");
            pulse_abort;
            expect_error(ERR_STATE, "abort in IDLE");
        end
        for (cidx = 0; cidx < ncase; cidx = cidx + 1) begin
            // Icarus는 배열 원소에 직접 $fscanf할 수 없어 임시 변수로 읽는다.
            for (i = 0; i < 784; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); X[i] = tmp; end
            for (i = 0; i < 48; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); PAD[i] = tmp; end
            for (c = 0; c < 10; c = c + 1)
                for (i = 0; i < 784; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); W[c][i] = tmp; end
            for (c = 0; c < 10; c = c + 1) begin rc = $fscanf(vf, "%d", tmp64); B[c] = tmp64; end
            if (full && cidx == 1) begin
                run_inference(MODE_RESET_RUN);
                run_inference(MODE_RESET_LOAD);
            end
            if (full && cidx == 2)
                run_inference(MODE_ABORT);
            run_inference((full && cidx == 0) ? MODE_ERRORS : MODE_CLEAN);
        end
        $fclose(af);
        if (DATA_W == 8)
            $display("RTL_SIM_PASS TILE784 cases=%0d tiles=13 tile_go_to_accept_cycles=%0d acc_w=%0d bias_w=%0d score_w=%0d errors_checked=%0d",
                ncase, tile_cyc, ACC_W, BIAS_W, SCORE_W, n_error);
        else
            $display("RTL_SIM_PASS TILE784 cases=%0d tiles=13 tile_go_to_accept_cycles=%0d acc_w=%0d bias_w=%0d score_w=%0d errors_checked=%0d data_w=%0d part_w=%0d",
                ncase, tile_cyc, ACC_W, BIAS_W, SCORE_W, n_error, DATA_W, PART_W);
        $finish;
    end
    initial begin #200000000; $fatal(1, "TB timeout"); end
endmodule
