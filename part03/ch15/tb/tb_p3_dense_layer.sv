// (추가) 15장 정수 Dense 계층 자동 판정 테스트벤치(64→10 분류기, 64→8, 8→10).
// 14장 p3_group10_core를 IN_LEN/OUT_N 파라미터로 재사용하고, x는 13장 p3_frame64_buffer에서 읽는다.
// 명령 파일(W/B/F)을 순서대로 실행해 모델을 유지·부분 갱신하며 프레임마다 점수·Class를 기록한다.
`timescale 1ns/1ps
module tb_p3_dense_layer;
    parameter integer IN_LEN = 64;
    parameter integer OUT_N = 10;
    localparam integer GROUPS = (OUT_N - 1) / 4 + 1;
    localparam integer EXPECT_CYCLES = GROUPS * (IN_LEN + 4) + 2;

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
    wire [OUT_N*25-1:0] scores;

    p3_frame64_buffer buffer(
        .clk(clk), .resetn(resetn),
        .s_data_i(s_data), .s_valid_i(s_valid), .s_last_i(s_last), .s_ready_o(s_ready),
        .frame_valid_o(frame_valid), .frame_ack_i(frame_ack),
        .rd_en_i(x_rd_en), .rd_addr_i(x_rd_addr), .rd_data_o(x_rd_data), .rd_valid_o(x_rd_valid),
        .err_short_o(err_short), .err_long_o(err_long));
    p3_group10_core #(.IN_LEN(IN_LEN), .OUT_N(OUT_N)) dense(
        .clk(clk), .resetn(resetn), .start_i(start), .x_valid_i(frame_valid),
        .x_rd_en_o(x_rd_en), .x_rd_addr_o(x_rd_addr), .x_rd_data_i(x_rd_data),
        .w_wr_en_i(w_wr), .b_wr_en_i(b_wr), .wr_class_i(wr_class), .wr_addr_i(wr_addr),
        .w_data_i(w_data), .b_data_i(b_data), .load_ready_o(load_ready),
        .busy_o(busy), .done_o(done), .error_o(error), .class_o(cls), .scores_o(scores));

    always @(posedge clk) if (resetn) begin
        if (error) $fatal(1, "unexpected error pulse");
        if (err_short || err_long) $fatal(1, "unexpected frame error");
        if (x_rd_en && x_rd_addr >= IN_LEN) $fatal(1, "read beyond IN_LEN");
        if (x_rd_en && !frame_valid) $fatal(1, "read without frame");
        if (busy && (w_wr || b_wr)) $fatal(1, "TB wrote while busy");
    end

    reg [8*8-1:0] tag;
    integer f_ops, f_act, rc, p1, p2, p3, k, v, cyc, n_frames = 0, n_w = 0, n_b = 0;
    reg signed [7:0] xbuf [0:63];
    reg [8*256-1:0] ops_path, act_path;

    initial begin
        if (!$value$plusargs("OPS=%s", ops_path)) $fatal(1, "+OPS required");
        if (!$value$plusargs("ACTUAL=%s", act_path)) $fatal(1, "+ACTUAL required");
        f_ops = $fopen(ops_path, "r");
        f_act = $fopen(act_path, "w");
        repeat (4) @(negedge clk);
        resetn = 1;
        tag = "";
        while (tag != "E") begin
            rc = $fscanf(f_ops, "%s %d %d %d", tag, p1, p2, p3);
            if (rc != 4) $fatal(1, "bad op line");
            if (tag == "W") begin
                @(negedge clk);
                w_wr = 1; wr_class = p1; wr_addr = p2; w_data = p3;
                @(negedge clk);
                w_wr = 0;
                n_w = n_w + 1;
            end else if (tag == "B") begin
                @(negedge clk);
                b_wr = 1; wr_class = p1; b_data = p3;
                @(negedge clk);
                b_wr = 0;
                n_b = n_b + 1;
            end else if (tag == "F") begin
                for (k = 0; k < 64; k = k + 1) begin
                    rc = $fscanf(f_ops, "%d", v);
                    xbuf[k] = v;
                end
                // 13장 스트림 계약으로 64바이트 전송
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
                cyc = 1;
                while (!done) begin
                    @(negedge clk);
                    cyc = cyc + 1;
                    if (cyc > 1000) $fatal(1, "dense timeout");
                end
                if (cyc != EXPECT_CYCLES) $fatal(1, "cycles %0d expected %0d", cyc, EXPECT_CYCLES);
                for (k = 0; k < OUT_N; k = k + 1)
                    $fwrite(f_act, "%0d ", $signed(scores[k*25 +: 25]));
                $fwrite(f_act, "C%0d\n", cls);
                frame_ack = 1;
                @(negedge clk);
                frame_ack = 0;
                n_frames = n_frames + 1;
            end
        end
        $fclose(f_act);
        $display("RTL_SIM_PASS DENSE %0dx%0d frames=%0d w_writes=%0d b_writes=%0d cycles=%0d",
            IN_LEN, OUT_N, n_frames, n_w, n_b, EXPECT_CYCLES);
        $finish;
    end
    initial begin #200000000; $fatal(1, "TB timeout"); end
endmodule
