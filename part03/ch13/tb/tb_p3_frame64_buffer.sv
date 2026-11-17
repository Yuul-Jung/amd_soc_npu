// (추가) 13장 p3_frame64_buffer 자동 판정 테스트벤치.
// Python이 만든 스트림(D 데이터/R Reset/Q FULL 중 Reset)을 무작위 valid 간격으로 넣고,
// 유효 프레임을 1클록 지연 읽기 포트로 64개 모두 읽어 actual 파일에 기록한다(Python이 비트 단위 비교).
// 매 클록 Ready/Valid·Busy·읽기 지연 규칙을 검사한다.
`timescale 1ns/1ps
module tb_p3_frame64_buffer;
    reg clk = 0, resetn = 0;
    reg [7:0] s_data = 0;
    reg s_valid = 0, s_last = 0, frame_ack = 0, rd_en = 0;
    reg [5:0] rd_addr = 0;
    wire s_ready, frame_valid, rd_valid, err_short, err_long;
    wire signed [7:0] rd_data;
    always #5 clk = ~clk;

    p3_frame64_buffer dut(
        .clk(clk), .resetn(resetn),
        .s_data_i(s_data), .s_valid_i(s_valid), .s_last_i(s_last), .s_ready_o(s_ready),
        .frame_valid_o(frame_valid), .frame_ack_i(frame_ack),
        .rd_en_i(rd_en), .rd_addr_i(rd_addr), .rd_data_o(rd_data), .rd_valid_o(rd_valid),
        .err_short_o(err_short), .err_long_o(err_long));

    integer seed = 13, n_short = 0, n_long = 0, n_frames = 0, out_fd;
    reg drop_flag = 0, reading = 0;
    reg prev_rd_req = 0, prev_stall = 0;
    reg [7:0] prev_data;
    reg prev_last;

    // 규칙 검사: Busy 중 ready=0, valid 유지 중 데이터 불변, 읽기 1클록 지연
    always @(posedge clk) begin
        if (resetn) begin
            if (frame_valid && s_ready) $fatal(1, "s_ready high while frame held");
            if (rd_valid !== prev_rd_req) $fatal(1, "rd_valid latency/state rule broken");
            if (err_short) n_short = n_short + 1;
            if (err_long) n_long = n_long + 1;
            if (err_short && err_long) $fatal(1, "both error pulses");
        end
        if (prev_stall && (!s_valid || s_data !== prev_data || s_last !== prev_last))
            $fatal(1, "TB changed stalled stream beat");
        prev_rd_req = resetn && rd_en && frame_valid;
        prev_stall = s_valid && !s_ready && resetn;
        prev_data = s_data;
        prev_last = s_last;
    end

    // 소비자: 유효 프레임을 읽고 기록한 뒤 무작위 지연 후 ack
    reg [7:0] frame_buf [0:63];
    integer a, wait_n;
    initial begin
        forever begin
            @(negedge clk);
            if (resetn && frame_valid && !drop_flag && !reading) begin
                reading = 1;
                // 주소 a 요청 -> 다음 상승 에지에서 mem[a] 출력 -> 다음 하강 에지에서 수집
                for (a = 0; a < 64; a = a + 1) begin
                    rd_en = 1; rd_addr = a;
                    @(negedge clk);
                    if (rd_valid !== 1'b1) $fatal(1, "rd_valid missing addr=%0d", a);
                    frame_buf[a] = rd_data;
                end
                rd_en = 0;
                for (a = 0; a < 64; a = a + 1) begin
                    $fwrite(out_fd, "%02x", frame_buf[a]);
                    if (a < 63) $fwrite(out_fd, " ");
                end
                $fwrite(out_fd, "\n");
                n_frames = n_frames + 1;
                // Busy 유지 확인: ack 전까지 frame_valid 유지
                wait_n = $urandom(seed) % 12;
                repeat (wait_n) begin
                    @(negedge clk);
                    if (!frame_valid) $fatal(1, "frame dropped before ack");
                end
                frame_ack = 1;
                @(negedge clk);
                frame_ack = 0;
                if (frame_valid) $fatal(1, "frame_valid not cleared by ack");
                reading = 0;
            end else if (!reading) begin
                // 유효 프레임이 없을 때 무작위 읽기 요청: rd_valid가 올라오면 안 된다(검사기에서 판정)
                rd_en = $urandom(seed) % 2;
                rd_addr = $urandom(seed);
            end
        end
    end

    // 생산자: 스트림 파일 재생
    reg [8*8-1:0] kind;
    integer fd, rc, val, last, gap, guard;
    reg [8*256-1:0] stream_path, actual_path;
    task automatic pulse_reset;
        begin
            @(negedge clk);
            s_valid = 0; s_last = 0;
            resetn = 0;
            repeat (3) @(negedge clk);
            if (frame_valid) $fatal(1, "frame_valid during reset");
            if (s_ready) $fatal(1, "s_ready high during reset");
            resetn = 1;
            @(negedge clk);
            if (!s_ready || frame_valid) $fatal(1, "bad state after reset");
        end
    endtask
    initial begin
        if (!$value$plusargs("STREAM=%s", stream_path)) $fatal(1, "+STREAM required");
        if (!$value$plusargs("ACTUAL=%s", actual_path)) $fatal(1, "+ACTUAL required");
        fd = $fopen(stream_path, "r");
        out_fd = $fopen(actual_path, "w");
        if (fd == 0 || out_fd == 0) $fatal(1, "cannot open files");
        repeat (4) @(negedge clk);
        resetn = 1;
        @(negedge clk);
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%s %h %d\n", kind, val, last);
            if (rc != 3) begin
                if (!$feof(fd)) $fatal(1, "bad stream line");
            end else if (kind == "R") begin
                pulse_reset;
            end else if (kind == "Q") begin
                // 직전 프레임은 소비자가 먼저 읽기 시작하도록 한 클록 이상 기다린 뒤 표시
                @(negedge clk);
                while (frame_valid || reading) @(negedge clk);
                drop_flag = 1;
            end else begin
                gap = $urandom(seed) % 4;
                repeat (gap) @(negedge clk);
                s_data = val; s_last = last; s_valid = 1;
                guard = 0;
                while (!s_ready) begin
                    @(negedge clk);
                    guard = guard + 1;
                    if (guard > 5000) $fatal(1, "stream stalled forever");
                end
                @(negedge clk);
                s_valid = 0; s_last = 0;
                if (drop_flag && last) begin
                    // Q: 완성 프레임을 ack 없이 Reset으로 폐기
                    @(negedge clk);
                    if (!frame_valid) $fatal(1, "Q frame not completed");
                    pulse_reset;
                    drop_flag = 0;
                end
            end
        end
        // 마지막 프레임 소비 대기
        guard = 0;
        while (frame_valid || reading) begin
            @(negedge clk);
            guard = guard + 1;
            if (guard > 5000) $fatal(1, "final frame not consumed");
        end
        repeat (5) @(negedge clk);
        $fwrite(out_fd, "ERR %0d %0d\n", n_short, n_long);
        $fclose(out_fd);
        $display("RTL_SIM_PASS FRAME64 frames=%0d short=%0d long=%0d", n_frames, n_short, n_long);
        $finish;
    end
    initial begin #20000000; $fatal(1, "TB timeout"); end
endmodule
