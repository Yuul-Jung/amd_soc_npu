// 4장 784 가속기 묶음: 서브젝트 모듈을 STAGE만큼 쌓는다. 서브젝트 모듈 파일은 고치지 않는다.
//   4-1 (STAGE>=1) precision_compare: 같은 32비트 값을 INT8·INT16으로 (구 06장, 안에 05장 양자화기 2개)
//   4-2 (STAGE>=2) p3_tile784_10 INT8: 784 = 64×12 + 16, 13타일 외부 누산 (구 17장, 안에 3-2 코어)
//                  x 타일은 3-1 p3_frame64_buffer
//   4-3 (STAGE>=3) p3_tile784_10 INT16 (구 18장 파라미터). x 타일은 2-1 bram_sync_buffer 16×64
//   4-4 (STAGE>=4) 1PE·4PE·8PE: 3-2 p3_group10_core를 #(64,1)·#(64,10)·#(64,6)+#(64,4)로 (구 19장),
//                  시작부터 끝까지 클록 수를 센다. Bias 없이 한 타일(64입력 → 10출력)만.
// 엔진 번호 p: 0 = INT8, 1 = INT16. PE 구성 g: 1, 4, 8.
`timescale 1ns/1ps
`default_nettype none
module p04_bank #(
    parameter integer STAGE = 4
) (
    input  wire               clk,
    input  wire               resetn,
    // 4-1
    input  wire               q_valid_i,
    input  wire signed [31:0] q_x_i,
    output wire               q_done_o,
    output wire signed [7:0]  q8_o,
    output wire signed [15:0] q16_o,
    output wire               q_ov8_o,
    output wire               q_ov16_o,
    // x 타일: INT8 스트림 (3-1 버퍼), INT16 단어 쓰기
    input  wire [7:0]         s_data_i,
    input  wire               s_valid_i,
    input  wire               s_last_i,
    output wire               s_ready_o,
    output wire               held8_o,
    input  wire               ack8_i,          // 콘솔이 들고 있는 INT8 타일을 놓음
    input  wire               x16_we_i,
    input  wire [5:0]         x16_addr_i,
    input  wire signed [15:0] x16_data_i,
    input  wire               x16_set_i,       // INT16 타일 64단어를 다 썼음
    output wire               held16_o,
    // 784 엔진 (p로 고름)
    input  wire               p_i,
    input  wire               start_i,
    input  wire               tile_go_i,
    input  wire [3:0]         tile_id_i,
    input  wire               w_wr_i,
    input  wire               b_wr_i,
    input  wire [3:0]         class_i,
    input  wire [5:0]         addr_i,
    input  wire signed [15:0] w_i,
    input  wire signed [39:0] b_i,
    output wire               tile_done_o,
    output wire               done_o,
    output wire               error_o,
    output wire [2:0]         err_code_o,
    output wire               ovf_o,
    output wire [3:0]         class_o,
    output wire [419:0]       scores_o,
    // 4-4 PE 구성
    input  wire [3:0]         g_i,             // 1, 4, 8
    input  wire               pe_wr_i,
    input  wire               pe_run_i,
    output reg                pe_done_o,
    output reg                pe_err_o,
    output reg  [15:0]        pe_cycles_o,
    output reg  [249:0]       pe_scores_o
);
    // ---------------- 4-1 ----------------
    precision_compare #(.SATURATE(1)) u_prec (
        .clk(clk), .resetn(resetn), .valid_i(q_valid_i), .x_i(q_x_i), .q8_o(q8_o), .q16_o(q16_o),
        .overflow8_o(q_ov8_o), .overflow16_o(q_ov16_o), .valid_o(q_done_o));

    // ---------------- x 타일 버퍼 ----------------
    wire               rd8_en, rd8_valid;
    wire [5:0]         rd8_addr;
    wire signed [7:0]  rd8_data;
    wire               ack8_eng;
    wire               err_short_unused, err_long_unused;
    generate if (STAGE >= 2) begin : g_buf8
        p3_frame64_buffer u_buf8 (
            .clk(clk), .resetn(resetn), .s_data_i(s_data_i), .s_valid_i(s_valid_i), .s_last_i(s_last_i),
            .s_ready_o(s_ready_o), .frame_valid_o(held8_o), .frame_ack_i(ack8_eng | ack8_i),
            .rd_en_i(rd8_en), .rd_addr_i(rd8_addr), .rd_data_o(rd8_data), .rd_valid_o(rd8_valid),
            .err_short_o(err_short_unused), .err_long_o(err_long_unused));
    end else begin : g_no_buf8
        assign s_ready_o = 1'b1; assign held8_o = 1'b0; assign rd8_data = 8'sd0; assign rd8_valid = 1'b0;
        assign err_short_unused = 1'b0; assign err_long_unused = 1'b0;
    end endgenerate

    // ---------------- 4-2·4-3: 784 엔진 ----------------
    wire [1:0]   e_tdone, e_done, e_err, e_ovf, e_rd, e_ack;
    wire [5:0]   e_addr [0:1];
    wire [2:0]   e_code [0:1];
    wire [3:0]   e_cls  [0:1];
    wire [419:0] e_sc   [0:1];

    generate if (STAGE >= 2) begin : g_t8
        p3_tile784_10 #(.DATA_W(8)) u_t8 (
            .clk(clk), .resetn(resetn), .start_i(start_i && !p_i), .abort_i(1'b0),
            .tile_go_i(tile_go_i && !p_i), .tile_id_i(tile_id_i),
            .x_valid_i(held8_o), .x_rd_en_o(e_rd[0]), .x_rd_addr_o(e_addr[0]), .x_rd_data_i(rd8_data),
            .frame_ack_o(e_ack[0]), .w_wr_en_i(w_wr_i && !p_i), .b_wr_en_i(b_wr_i && !p_i),
            .wr_class_i(class_i), .wr_addr_i(addr_i), .w_data_i(w_i[7:0]), .b_data_i(b_i),
            .load_ready_o(), .busy_o(), .done_o(e_done[0]), .error_o(e_err[0]), .err_code_o(e_code[0]),
            .ovf_o(e_ovf[0]), .tile_idx_o(), .tile_done_o(e_tdone[0]), .part_scores_o(),
            .class_o(e_cls[0]), .scores_o(e_sc[0]));
    end else begin : g_no_t8
        assign e_rd[0] = 1'b0; assign e_addr[0] = 6'd0; assign e_ack[0] = 1'b0; assign e_done[0] = 1'b0;
        assign e_err[0] = 1'b0; assign e_code[0] = 3'd0; assign e_ovf[0] = 1'b0; assign e_tdone[0] = 1'b0;
        assign e_cls[0] = 4'd0; assign e_sc[0] = 420'd0;
    end endgenerate
    assign ack8_eng = e_ack[0];

    generate if (STAGE >= 3) begin : g_t16
        // INT16 x 타일: 2-1 BRAM. 콘솔이 64단어를 쓰고 set → 엔진이 다 쓰면 frame_ack로 놓는다
        reg held;
        wire signed [15:0] rd16_data;
        wire rd16_valid;
        always @(posedge clk) begin
            if (!resetn || e_ack[1]) held <= 1'b0;
            else if (x16_set_i)       held <= 1'b1;
        end
        assign held16_o = held;
        bram_sync_buffer #(.DATA_WIDTH(16), .ADDR_WIDTH(6)) u_x16 (
            .clk(clk), .resetn(resetn), .wr_en(x16_we_i), .rd_en(e_rd[1]), .wr_addr(x16_addr_i),
            .rd_addr(e_addr[1]), .wr_data(x16_data_i), .rd_data(rd16_data), .rd_valid(rd16_valid));
        p3_tile784_10 #(.DATA_W(16), .CORE_ACC_W(38), .PART_W(39)) u_t16 (
            .clk(clk), .resetn(resetn), .start_i(start_i && p_i), .abort_i(1'b0),
            .tile_go_i(tile_go_i && p_i), .tile_id_i(tile_id_i),
            .x_valid_i(held), .x_rd_en_o(e_rd[1]), .x_rd_addr_o(e_addr[1]), .x_rd_data_i(rd16_data),
            .frame_ack_o(e_ack[1]), .w_wr_en_i(w_wr_i && p_i), .b_wr_en_i(b_wr_i && p_i),
            .wr_class_i(class_i), .wr_addr_i(addr_i), .w_data_i(w_i), .b_data_i(b_i),
            .load_ready_o(), .busy_o(), .done_o(e_done[1]), .error_o(e_err[1]), .err_code_o(e_code[1]),
            .ovf_o(e_ovf[1]), .tile_idx_o(), .tile_done_o(e_tdone[1]), .part_scores_o(),
            .class_o(e_cls[1]), .scores_o(e_sc[1]));
    end else begin : g_no_t16
        assign held16_o = 1'b0; assign e_rd[1] = 1'b0; assign e_addr[1] = 6'd0; assign e_ack[1] = 1'b0;
        assign e_done[1] = 1'b0; assign e_err[1] = 1'b0; assign e_code[1] = 3'd0; assign e_ovf[1] = 1'b0;
        assign e_tdone[1] = 1'b0; assign e_cls[1] = 4'd0; assign e_sc[1] = 420'd0;
    end endgenerate

    assign tile_done_o = e_tdone[p_i];
    assign done_o      = e_done[p_i];
    assign error_o     = e_err[p_i];
    assign err_code_o  = e_code[p_i];
    assign ovf_o       = e_ovf[p_i];
    assign class_o     = e_cls[p_i];
    assign scores_o    = e_sc[p_i];

    // ---------------- 4-4: PE 구성 ----------------
    wire        pe_rd;
    wire [5:0]  pe_addr;
    generate if (STAGE >= 4) begin : g_pe
        // class → PE8 코어: A = class 0~3·8~9 (로컬 0~5), B = class 4~7 (로컬 0~3)  (19장 TB와 같은 배치)
        wire       to_b    = (class_i >= 4'd4) && (class_i <= 4'd7);
        wire [3:0] a_local = (class_i >= 4'd8) ? class_i - 4'd4 : class_i;
        wire [3:0] b_local = class_i - 4'd4;
        wire [3:0] st = {4{pe_run_i}} & {g_i == 4'd8, g_i == 4'd8, g_i == 4'd4, g_i == 4'd1};   // {8b, 8a, 4, 1}
        wire [3:0] dn, er, rd;
        wire [5:0] ad [0:3];
        wire [24:0]  sc1;
        wire [249:0] sc4;
        wire [149:0] sc8a;
        wire [99:0]  sc8b;
        p3_group10_core #(.IN_LEN(64), .OUT_N(1)) u_pe1 (
            .clk(clk), .resetn(resetn), .start_i(st[0]), .x_valid_i(held8_o),
            .x_rd_en_o(rd[0]), .x_rd_addr_o(ad[0]), .x_rd_data_i(rd8_data),
            .w_wr_en_i(pe_wr_i && g_i == 4'd1), .b_wr_en_i(1'b0), .wr_class_i(4'd0), .wr_addr_i(addr_i),
            .w_data_i(w_i[7:0]), .b_data_i(24'sd0), .load_ready_o(), .busy_o(), .done_o(dn[0]),
            .error_o(er[0]), .class_o(), .scores_o(sc1));
        p3_group10_core #(.IN_LEN(64), .OUT_N(10)) u_pe4 (
            .clk(clk), .resetn(resetn), .start_i(st[1]), .x_valid_i(held8_o),
            .x_rd_en_o(rd[1]), .x_rd_addr_o(ad[1]), .x_rd_data_i(rd8_data),
            .w_wr_en_i(pe_wr_i && g_i == 4'd4), .b_wr_en_i(1'b0), .wr_class_i(class_i), .wr_addr_i(addr_i),
            .w_data_i(w_i[7:0]), .b_data_i(24'sd0), .load_ready_o(), .busy_o(), .done_o(dn[1]),
            .error_o(er[1]), .class_o(), .scores_o(sc4));
        p3_group10_core #(.IN_LEN(64), .OUT_N(6)) u_pe8a (
            .clk(clk), .resetn(resetn), .start_i(st[2]), .x_valid_i(held8_o),
            .x_rd_en_o(rd[2]), .x_rd_addr_o(ad[2]), .x_rd_data_i(rd8_data),
            .w_wr_en_i(pe_wr_i && g_i == 4'd8 && !to_b), .b_wr_en_i(1'b0), .wr_class_i(a_local),
            .wr_addr_i(addr_i), .w_data_i(w_i[7:0]), .b_data_i(24'sd0), .load_ready_o(), .busy_o(),
            .done_o(dn[2]), .error_o(er[2]), .class_o(), .scores_o(sc8a));
        p3_group10_core #(.IN_LEN(64), .OUT_N(4)) u_pe8b (
            .clk(clk), .resetn(resetn), .start_i(st[3]), .x_valid_i(held8_o),
            .x_rd_en_o(rd[3]), .x_rd_addr_o(ad[3]), .x_rd_data_i(rd8_data),
            .w_wr_en_i(pe_wr_i && g_i == 4'd8 && to_b), .b_wr_en_i(1'b0), .wr_class_i(b_local),
            .wr_addr_i(addr_i), .w_data_i(w_i[7:0]), .b_data_i(24'sd0), .load_ready_o(), .busy_o(),
            .done_o(dn[3]), .error_o(er[3]), .class_o(), .scores_o(sc8b));
        // PE8의 두 코어는 같은 주소를 읽는다 (출력 고정 스케줄, 19장). B가 먼저 끝나면 A 주소만 남는다
        assign pe_rd   = |rd;
        assign pe_addr = rd[0] ? ad[0] : rd[1] ? ad[1] : rd[2] ? ad[2] : ad[3];

        reg [3:0]  running, finished;
        reg [3:0]  g_q;
        always @(posedge clk) begin
            if (!resetn) begin
                running <= 4'd0; finished <= 4'd0; g_q <= 4'd0;
                pe_done_o <= 1'b0; pe_err_o <= 1'b0; pe_cycles_o <= 16'd0; pe_scores_o <= 250'd0;
            end else begin
                pe_done_o <= 1'b0; pe_err_o <= 1'b0;
                if (pe_run_i) begin
                    g_q <= g_i;
                    if (st == 4'd0) begin pe_err_o <= 1'b1; pe_done_o <= 1'b1; end   // g가 1·4·8이 아님
                    else begin running <= st; finished <= 4'd0; pe_cycles_o <= 16'd0; end
                end else if (running != 4'd0) begin
                    // 19장 정의: start 샘플 에지 → done 관측 에지. 시작 다음 클록부터 1씩 세면 done 클록 값과 같다
                    pe_cycles_o <= pe_cycles_o + 16'd1;
                    if (|(er & running)) begin
                        running <= 4'd0; pe_err_o <= 1'b1; pe_done_o <= 1'b1;
                    end else if (((finished | dn) & running) == running) begin
                        running <= 4'd0; pe_done_o <= 1'b1;
                        pe_scores_o <= (g_q == 4'd1) ? {225'd0, sc1} :
                                       (g_q == 4'd4) ? sc4 :
                                       {sc8a[149:100], sc8b, sc8a[99:0]};   // class 0~3 = A0~3, 4~7 = B, 8·9 = A4·5
                    end
                    finished <= finished | (dn & running);
                end
            end
        end
    end else begin : g_no_pe
        assign pe_rd = 1'b0; assign pe_addr = 6'd0;
        always @(posedge clk) begin
            pe_done_o <= pe_run_i; pe_err_o <= pe_run_i; pe_cycles_o <= 16'd0; pe_scores_o <= 250'd0;
        end
    end endgenerate

    // INT8 x 버퍼 읽기 포트: 784 INT8 엔진과 PE 코어가 나눠 쓴다 (한 번에 하나만 돈다)
    assign rd8_en   = e_rd[0] | pe_rd;
    assign rd8_addr = e_rd[0] ? e_addr[0] : pe_addr;
endmodule
`default_nettype wire
