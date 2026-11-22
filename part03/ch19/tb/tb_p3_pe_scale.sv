// (추가) 19장 PE 병렬도 비교 테스트벤치. 14장 p3_group10_core(변경 없음)로 세 구성을 만들어 같은 타일을 계산한다.
//   PE1 : 코어 #(64,1)  — lane 0만 유효. class마다 가중치 64개 재적재 후 10회 실행
//   PE4 : 코어 #(64,10) — 4+4+2 그룹
//   PE8 : 코어 A #(64,6) (class 0~3, 8~9) + 코어 B #(64,4) (class 4~7)를 같은 클록에 시작.
//         13장 프레임 버퍼 읽기 포트 하나를 두 코어가 공유(같은 주소 방송)한다.
// 각 구성의 10개 부분합과 코어별 start→done 사이클, 가중치 쓰기 수를 actual에 기록(Python 비교).
// 상시 검사: PE8 두 코어가 동시에 읽을 때 주소 동일, done 1클록, 사이클 수 일정, 오류 없음.
`timescale 1ns/1ps
module tb_p3_pe_scale;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;

    reg [7:0] s_data = 0;
    reg s_valid = 0, s_last = 0;
    reg ack1 = 0, ack4 = 0, ack8 = 0;
    wire rdy1, rdy4, rdy8, fv1, fv4, fv8;
    wire [5:0] err;
    reg st1 = 0, st4 = 0, st8 = 0;
    reg wr1 = 0, wr4 = 0, wr8a = 0, wr8b = 0;
    reg [3:0] wr_class = 0;
    reg [5:0] wr_addr = 0;
    reg signed [7:0] w_data = 0;

    // 구성별 코어 x 포트와 버퍼
    wire en1, en4, en8a, en8b, d1, d4, d8a, d8b, e1, e4, e8a, e8b;
    wire [5:0] a1, a4, a8a, a8b;
    wire signed [7:0] x1, x4, x8;
    wire [24:0] sc1;
    wire [249:0] sc4;
    wire [149:0] sc8a;
    wire [99:0] sc8b;
    // PE8 공유 읽기 포트: 두 코어 중 읽는 쪽 주소(동시이면 같은 주소여야 함)
    wire en8 = en8a || en8b;
    wire [5:0] a8 = en8a ? a8a : a8b;

    p3_frame64_buffer buf1(.clk(clk), .resetn(resetn), .s_data_i(s_data), .s_valid_i(s_valid),
        .s_last_i(s_last), .s_ready_o(rdy1), .frame_valid_o(fv1), .frame_ack_i(ack1),
        .rd_en_i(en1), .rd_addr_i(a1), .rd_data_o(x1), .rd_valid_o(), .err_short_o(err[0]),
        .err_long_o(err[1]));
    p3_frame64_buffer buf4(.clk(clk), .resetn(resetn), .s_data_i(s_data), .s_valid_i(s_valid),
        .s_last_i(s_last), .s_ready_o(rdy4), .frame_valid_o(fv4), .frame_ack_i(ack4),
        .rd_en_i(en4), .rd_addr_i(a4), .rd_data_o(x4), .rd_valid_o(), .err_short_o(err[2]),
        .err_long_o(err[3]));
    p3_frame64_buffer buf8(.clk(clk), .resetn(resetn), .s_data_i(s_data), .s_valid_i(s_valid),
        .s_last_i(s_last), .s_ready_o(rdy8), .frame_valid_o(fv8), .frame_ack_i(ack8),
        .rd_en_i(en8), .rd_addr_i(a8), .rd_data_o(x8), .rd_valid_o(), .err_short_o(err[4]),
        .err_long_o(err[5]));

    p3_group10_core #(.IN_LEN(64), .OUT_N(1)) pe1(.clk(clk), .resetn(resetn), .start_i(st1),
        .x_valid_i(fv1), .x_rd_en_o(en1), .x_rd_addr_o(a1), .x_rd_data_i(x1),
        .w_wr_en_i(wr1), .b_wr_en_i(1'b0), .wr_class_i(wr_class), .wr_addr_i(wr_addr),
        .w_data_i(w_data), .b_data_i(24'sd0), .load_ready_o(), .busy_o(), .done_o(d1),
        .error_o(e1), .class_o(), .scores_o(sc1));
    p3_group10_core #(.IN_LEN(64), .OUT_N(10)) pe4(.clk(clk), .resetn(resetn), .start_i(st4),
        .x_valid_i(fv4), .x_rd_en_o(en4), .x_rd_addr_o(a4), .x_rd_data_i(x4),
        .w_wr_en_i(wr4), .b_wr_en_i(1'b0), .wr_class_i(wr_class), .wr_addr_i(wr_addr),
        .w_data_i(w_data), .b_data_i(24'sd0), .load_ready_o(), .busy_o(), .done_o(d4),
        .error_o(e4), .class_o(), .scores_o(sc4));
    p3_group10_core #(.IN_LEN(64), .OUT_N(6)) pe8a(.clk(clk), .resetn(resetn), .start_i(st8),
        .x_valid_i(fv8), .x_rd_en_o(en8a), .x_rd_addr_o(a8a), .x_rd_data_i(x8),
        .w_wr_en_i(wr8a), .b_wr_en_i(1'b0), .wr_class_i(wr_class), .wr_addr_i(wr_addr),
        .w_data_i(w_data), .b_data_i(24'sd0), .load_ready_o(), .busy_o(), .done_o(d8a),
        .error_o(e8a), .class_o(), .scores_o(sc8a));
    p3_group10_core #(.IN_LEN(64), .OUT_N(4)) pe8b(.clk(clk), .resetn(resetn), .start_i(st8),
        .x_valid_i(fv8), .x_rd_en_o(en8b), .x_rd_addr_o(a8b), .x_rd_data_i(x8),
        .w_wr_en_i(wr8b), .b_wr_en_i(1'b0), .wr_class_i(wr_class), .wr_addr_i(wr_addr),
        .w_data_i(w_data), .b_data_i(24'sd0), .load_ready_o(), .busy_o(), .done_o(d8b),
        .error_o(e8b), .class_o(), .scores_o(sc8b));

    // 상시 검사와 사이클 측정: start 샘플 에지 → done 관측 에지
    integer cycle = 0, t1 = 0, t4 = 0, t8 = 0, c1 = -1, c4 = -1, c8a = -1, c8b = -1;
    integer nw1 = 0, nw4 = 0, nw8 = 0;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (resetn) begin
            if (en8a && en8b && a8a != a8b) $fatal(1, "PE8 shared x port address conflict");
            if (err != 0 || e1 || e4 || e8a || e8b) $fatal(1, "unexpected error");
            if (st1) t1 = cycle;
            if (st4) t4 = cycle;
            if (st8) t8 = cycle;
            if (wr1) nw1 = nw1 + 1;
            if (wr4) nw4 = nw4 + 1;
            if (wr8a || wr8b) nw8 = nw8 + 1;
            if (d1) begin
                if (c1 < 0) c1 = cycle - t1;
                else if (cycle - t1 != c1) $fatal(1, "PE1 cycles changed");
            end
            if (d4) begin
                if (c4 < 0) c4 = cycle - t4;
                else if (cycle - t4 != c4) $fatal(1, "PE4 cycles changed");
            end
            if (d8a) begin
                if (c8a < 0) c8a = cycle - t8;
                else if (cycle - t8 != c8a) $fatal(1, "PE8A cycles changed");
            end
            if (d8b) begin
                if (c8b < 0) c8b = cycle - t8;
                else if (cycle - t8 != c8b) $fatal(1, "PE8B cycles changed");
            end
        end
    end

    integer X [0:63];
    integer W [0:9][0:63];
    reg signed [24:0] P1 [0:9];
    reg signed [24:0] P4 [0:9];
    reg signed [24:0] P8 [0:9];
    integer tmp, vf, af, rc, nrun, r, i, c, guard, lw1, lw4, lw8, lw1_ref, lw4_ref, lw8_ref;
    reg seen4, seen8a, seen8b;
    reg [8*256-1:0] vpath, apath;

    // sel: 1=PE1, 4=PE4, 8=PE8 코어 A, 9=PE8 코어 B
    task automatic write_word(input integer sel, input integer cl, input integer addr, input integer val);
        begin
            @(negedge clk);
            wr_class = cl; wr_addr = addr; w_data = val;
            wr1 = (sel == 1); wr4 = (sel == 4); wr8a = (sel == 8); wr8b = (sel == 9);
            @(negedge clk);
            wr1 = 0; wr4 = 0; wr8a = 0; wr8b = 0;
        end
    endtask
    task automatic send_frame;
        integer k;
        begin
            for (k = 0; k < 64; k = k + 1) begin
                @(negedge clk);
                s_data = X[k]; s_valid = 1; s_last = (k == 63);
                while (!(rdy1 && rdy4 && rdy8)) @(negedge clk);
            end
            @(negedge clk);
            s_valid = 0; s_last = 0;
            if (!(fv1 && fv4 && fv8)) $fatal(1, "frame not held");
        end
    endtask
    task automatic ack(input integer sel);
        begin
            @(negedge clk);
            ack1 = (sel == 1); ack4 = (sel == 4); ack8 = (sel == 8);
            @(negedge clk);
            ack1 = 0; ack4 = 0; ack8 = 0;
        end
    endtask
    task automatic put(input [8*3-1:0] name, input integer run, input integer which);
        begin
            $fwrite(af, "R%0d %0s", run, name);
            for (c = 0; c < 10; c = c + 1)
                $fwrite(af, " %0d", which == 1 ? P1[c] : (which == 4 ? P4[c] : P8[c]));
            $fwrite(af, "\n");
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vpath)) $fatal(1, "+VECTORS required");
        if (!$value$plusargs("ACTUAL=%s", apath)) $fatal(1, "+ACTUAL required");
        vf = $fopen(vpath, "r");
        af = $fopen(apath, "w");
        rc = $fscanf(vf, "%d", nrun);
        repeat (4) @(negedge clk);
        resetn = 1;
        @(negedge clk);
        lw1_ref = -1;
        for (r = 0; r < nrun; r = r + 1) begin
            for (i = 0; i < 64; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); X[i] = tmp; end
            for (c = 0; c < 10; c = c + 1)
                for (i = 0; i < 64; i = i + 1) begin rc = $fscanf(vf, "%d", tmp); W[c][i] = tmp; end
            send_frame;
            // PE4·PE8 가중치 적재(쓰기 포트 1개, 1단어/클록)
            lw4 = nw4; lw8 = nw8;
            for (c = 0; c < 10; c = c + 1)
                for (i = 0; i < 64; i = i + 1) write_word(4, c, i, W[c][i]);
            for (c = 0; c < 10; c = c + 1)
                for (i = 0; i < 64; i = i + 1)
                    if (c < 4) write_word(8, c, i, W[c][i]);
                    else if (c < 8) write_word(9, c - 4, i, W[c][i]);
                    else write_word(8, c - 4, i, W[c][i]);
            // PE4와 PE8(두 코어)을 같은 클록에 시작, done 1클록 펄스를 각각 기다린다
            @(negedge clk); st4 = 1; st8 = 1;
            @(negedge clk); st4 = 0; st8 = 0;
            seen4 = 0; seen8a = 0; seen8b = 0; guard = 0;
            while (!(seen4 && seen8a && seen8b)) begin
                if (d4) begin
                    seen4 = 1;
                    for (c = 0; c < 10; c = c + 1) P4[c] = $signed(sc4[c*25 +: 25]);
                end
                if (d8a) seen8a = 1;
                if (d8b) seen8b = 1;
                @(negedge clk);
                guard = guard + 1;
                if (guard > 1000) $fatal(1, "PE4/PE8 timeout");
            end
            // PE8 전역 class ← 코어 A class 0~3·8~9, 코어 B class 4~7
            for (c = 0; c < 4; c = c + 1) begin
                P8[c] = $signed(sc8a[c*25 +: 25]);
                P8[c + 4] = $signed(sc8b[c*25 +: 25]);
            end
            P8[8] = $signed(sc8a[4*25 +: 25]);
            P8[9] = $signed(sc8a[5*25 +: 25]);
            ack(4);
            ack(8);
            // PE1: class마다 가중치 64개 재적재 → 실행
            lw1 = nw1;
            for (c = 0; c < 10; c = c + 1) begin
                for (i = 0; i < 64; i = i + 1) write_word(1, 0, i, W[c][i]);
                @(negedge clk); st1 = 1;
                @(negedge clk); st1 = 0;
                guard = 0;
                while (!d1) begin
                    @(negedge clk);
                    guard = guard + 1;
                    if (guard > 1000) $fatal(1, "PE1 timeout");
                end
                P1[c] = $signed(sc1);
            end
            ack(1);
            lw1 = nw1 - lw1; lw4 = nw4 - lw4; lw8 = nw8 - lw8;
            if (lw1_ref < 0) begin lw1_ref = lw1; lw4_ref = lw4; lw8_ref = lw8; end
            else if (lw1 != lw1_ref || lw4 != lw4_ref || lw8 != lw8_ref) $fatal(1, "load count changed");
            put("PE1", r, 1);
            put("PE4", r, 4);
            put("PE8", r, 8);
        end
        $fwrite(af, "PE1_pass=%0d PE1=%0d PE4=%0d PE8A=%0d PE8B=%0d PE8=%0d LOAD_W_PE1=%0d LOAD_W_PE4=%0d LOAD_W_PE8=%0d\n",
            c1, 10 * c1, c4, c8a, c8b, (c8a > c8b) ? c8a : c8b, lw1_ref, lw4_ref, lw8_ref);
        $fclose(af);
        $display("RTL_SIM_PASS PE_SCALE tile_runs=%0d PE1=%0dx10 PE4=%0d PE8=%0d(A %0d, B %0d) load_w=%0d",
            nrun, c1, c4, (c8a > c8b) ? c8a : c8b, c8a, c8b, lw4_ref);
        $finish;
    end
    initial begin #500000000; $fatal(1, "TB timeout"); end
endmodule
