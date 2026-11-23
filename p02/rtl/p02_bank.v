// 2장 NPU 묶음: 서브젝트 모듈을 STAGE(끝낸 서브젝트 수)만큼 실제로 쌓는다.
//   2-1 (STAGE>=1) bram_sync_buffer 5개: X[64], W0~W3[64]       → 명령 x·w 되읽기
//   2-2 (STAGE>=2) fixed_quantizer 32→8비트, SHIFT 8             → 명령 Q
//   2-3 (STAGE>=3) vector_dot_core: X·W0 (안에 1-2 mac_core)       → 명령 D
//   2-4 (STAGE>=4) pe_array4: X·W0~W3 (안에 2-3 내적 4개)          → 명령 P
//   2-5 (STAGE>=5) dense_layer4: + Bias, ReLU, 16비트 양자화       → 명령 L
//   2-6 (STAGE>=6) npu_core: 자체 BRAM + Dense                    → 명령 N
//   2-7 (STAGE>=7) 엔진 포트: 명령 해석기가 npu_core를 통합 엔진처럼 쓴다 (점수 41비트 확장, argmax)
// D·P·L은 묶음의 BRAM에서 한 원소씩 읽어 각 모듈의 ready/valid로 넣는다. npu_core는 자체 BRAM을 쓰므로
// X·W 쓰기는 묶음 BRAM과 npu_core에 같이 들어간다. Bias는 묶음 레지스터 4개.
`timescale 1ns/1ps
`default_nettype none
module p02_bank #(
    parameter integer STAGE = 8
) (
    input  wire               clk,
    input  wire               resetn,
    // 디버그 콘솔 쪽
    input  wire [3:0]         op_i,          // OP_* (아래)
    input  wire               op_valid_i,    // 1클록
    input  wire [5:0]         addr_i,
    input  wire [1:0]         neuron_i,
    input  wire signed [15:0] data_i,
    input  wire signed [39:0] bias_i,
    input  wire signed [31:0] qin_i,
    input  wire [6:0]         len_i,
    output reg                op_done_o,     // 1클록. 이 클록에 res_o·flags_o 유효
    output reg                op_error_o,
    output reg  [159:0]       res_o,
    output reg  [3:0]         flags_o,
    // 엔진 포트 (명령 해석기, STAGE>=7). owner = 1이면 메모리 쓰기·코어 실행을 엔진 포트가 가진다
    input  wire               owner_engine_i,
    input  wire               e_start_i,
    input  wire [6:0]         e_length_i,
    input  wire               e_x_wr_i,
    input  wire               e_w_wr_i,
    input  wire               e_b_wr_i,
    input  wire [5:0]         e_addr_i,
    input  wire [1:0]         e_neuron_i,
    input  wire signed [15:0] e_data_i,
    input  wire signed [39:0] e_bias_i,
    output wire               e_load_ready_o,
    output wire               e_busy_o,
    output wire               e_done_o,
    output wire               e_error_o,
    output wire [1:0]         e_class_o,
    output wire [163:0]       e_scores_o
);
    localparam [3:0] OP_XWR = 4'd1, OP_WWR = 4'd2, OP_BWR = 4'd3, OP_XRD = 4'd4, OP_WRD = 4'd5,
                     OP_QNT = 4'd6, OP_DOT = 4'd7, OP_PE4 = 4'd8, OP_DENSE = 4'd9, OP_CORE = 4'd10;

    // ---------------- 쓰기 경로: 콘솔 또는 엔진 포트 ----------------
    wire               eng = (STAGE >= 7) && owner_engine_i;
    wire               x_we = eng ? e_x_wr_i : (op_valid_i && op_i == OP_XWR);
    wire               w_we = eng ? e_w_wr_i : (op_valid_i && op_i == OP_WWR);
    wire               b_we = eng ? e_b_wr_i : (op_valid_i && op_i == OP_BWR);
    wire [5:0]         w_addr = eng ? e_addr_i : addr_i;
    wire [1:0]         w_neur = eng ? e_neuron_i : neuron_i;
    wire signed [15:0] w_data = eng ? e_data_i : data_i;
    wire signed [39:0] w_bias = eng ? e_bias_i : bias_i;

    reg  [159:0] biases;                          // {b3,b2,b1,b0}
    always @(posedge clk) begin
        if (!resetn)  biases <= 160'd0;
        else if (b_we) biases[w_neur*40 +: 40] <= w_bias;
    end

    // ---------------- 2-1: BRAM 5개 ----------------
    reg         rd_en;
    reg  [5:0]  rd_addr;
    wire signed [15:0] x_rd;
    wire [63:0] w_rd;
    wire        x_rv;
    wire [3:0]  w_rv;
    bram_sync_buffer #(.DATA_WIDTH(16), .ADDR_WIDTH(6)) u_xmem (
        .clk(clk), .resetn(resetn), .wr_en(x_we), .rd_en(rd_en), .wr_addr(w_addr), .rd_addr(rd_addr),
        .wr_data(w_data), .rd_data(x_rd), .rd_valid(x_rv));
    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : g_wmem
        bram_sync_buffer #(.DATA_WIDTH(16), .ADDR_WIDTH(6)) u_wmem (
            .clk(clk), .resetn(resetn), .wr_en(w_we && w_neur == g), .rd_en(rd_en), .wr_addr(w_addr),
            .rd_addr(rd_addr), .wr_data(w_data), .rd_data(w_rd[g*16 +: 16]), .rd_valid(w_rv[g]));
    end endgenerate

    // ---------------- 2-2: 양자화기 ----------------
    reg               q_valid;
    wire signed [7:0] q_out;
    wire              q_ov, q_done;
    generate if (STAGE >= 2) begin : g_quant
        fixed_quantizer #(.IN_WIDTH(32), .OUT_WIDTH(8), .SHIFT(8), .ROUND(1), .SATURATE(1)) u_q (
            .clk(clk), .resetn(resetn), .valid_i(q_valid), .x_i(qin_i), .q_o(q_out), .valid_o(q_done), .overflow_o(q_ov));
    end else begin : g_no_quant
        assign q_out = 8'sd0; assign q_ov = 1'b0; assign q_done = 1'b0;
    end endgenerate

    // ---------------- 2-3·2-4·2-5: 한 원소씩 넣는 순서기 ----------------
    reg  [3:0]  seq_op;                           // OP_DOT / OP_PE4 / OP_DENSE
    reg         start;                            // 1클록
    reg  [8:0]  length;
    reg         push;                             // 원소 하나를 내놓은 상태
    reg  signed [15:0] x_q;
    reg  [63:0] w_q;

    wire        dot_ready, dot_done, dot_err;
    wire signed [39:0] dot_res;
    generate if (STAGE >= 3) begin : g_dot
        vector_dot_core #(.DATA_WIDTH(16), .ACC_WIDTH(40)) u_dot (
            .clk(clk), .resetn(resetn), .start_i(start && seq_op == OP_DOT), .valid_i(push && seq_op == OP_DOT),
            .length_i(length), .a_i(x_q), .b_i(w_q[15:0]), .ready_o(dot_ready), .busy_o(), .done_o(dot_done),
            .error_o(dot_err), .result_o(dot_res));
    end else begin : g_no_dot
        assign dot_ready = 1'b0; assign dot_done = 1'b0; assign dot_err = 1'b0; assign dot_res = 40'sd0;
    end endgenerate

    wire [3:0]   pe_ready;
    wire         pe_done, pe_err;
    wire [159:0] pe_res;
    generate if (STAGE >= 4) begin : g_pe
        pe_array4 #(.DATA_WIDTH(16), .ACC_WIDTH(40)) u_pe (
            .clk(clk), .resetn(resetn), .start_i(start && seq_op == OP_PE4), .length_i(length),
            .valid_i({4{push && seq_op == OP_PE4 && (&pe_ready)}}), .a_i({4{x_q}}), .b_i(w_q),
            .ready_o(pe_ready), .busy_o(), .done_o(pe_done), .error_o(pe_err), .pe_results_o(pe_res), .sum_o());
    end else begin : g_no_pe
        assign pe_ready = 4'd0; assign pe_done = 1'b0; assign pe_err = 1'b0; assign pe_res = 160'd0;
    end endgenerate

    wire        dn_ready, dn_done, dn_err;
    wire [63:0] dn_res;
    wire [3:0]  dn_ov;
    generate if (STAGE >= 5) begin : g_dense
        dense_layer4 #(.DATA_WIDTH(16), .ACC_WIDTH(40), .SHIFT(0)) u_dense (
            .clk(clk), .resetn(resetn), .start_i(start && seq_op == OP_DENSE), .valid_i(push && seq_op == OP_DENSE),
            .length_i(length), .x_i(x_q), .weights_i(w_q), .biases_i(biases), .ready_o(dn_ready), .busy_o(),
            .done_o(dn_done), .error_o(dn_err), .result_o(dn_res), .overflow_o(dn_ov));
    end else begin : g_no_dense
        assign dn_ready = 1'b0; assign dn_done = 1'b0; assign dn_err = 1'b0; assign dn_res = 64'd0; assign dn_ov = 4'd0;
    end endgenerate

    wire seq_ready = (seq_op == OP_DOT) ? dot_ready : (seq_op == OP_PE4) ? (&pe_ready) : dn_ready;
    wire seq_done  = (seq_op == OP_DOT) ? dot_done  : (seq_op == OP_PE4) ? pe_done      : dn_done;
    wire seq_err   = (seq_op == OP_DOT) ? dot_err   : (seq_op == OP_PE4) ? pe_err       : dn_err;

    // ---------------- 2-6: npu_core (자체 BRAM) ----------------
    reg         core_start_c;                     // 콘솔이 시작
    reg         eng_run;                          // 지금 실행이 엔진 포트 것
    wire        core_start = core_start_c || (eng && e_start_i);
    wire [8:0]  core_len = (eng && e_start_i) ? {2'b00, e_length_i} : {2'b00, len_i};
    wire        core_load_ready, core_busy, core_done, core_err;
    wire [63:0] core_res;
    wire [3:0]  core_ov;
    generate if (STAGE >= 6) begin : g_core
        npu_core #(.DATA_WIDTH(16), .ACC_WIDTH(40)) u_core (
            .clk(clk), .resetn(resetn), .start_i(core_start), .length_i(core_len), .biases_i(biases),
            .x_wr_en(x_we), .w_wr_en(w_we), .x_wr_addr(w_addr), .w_wr_addr(w_addr), .w_neuron(w_neur),
            .x_wr_data(w_data), .w_wr_data(w_data), .load_ready_o(core_load_ready), .busy_o(core_busy),
            .done_o(core_done), .error_o(core_err), .result_o(core_res), .overflow_o(core_ov));
    end else begin : g_no_core
        assign core_load_ready = resetn; assign core_busy = 1'b0; assign core_done = 1'b0;
        assign core_err = 1'b0; assign core_res = 64'd0; assign core_ov = 4'd0;
    end endgenerate

    // ---------------- 2-7: 엔진 포트 (npu_core를 통합 엔진 모양으로) ----------------
    generate if (STAGE >= 7) begin : g_eng
        wire signed [15:0] r0 = core_res[15:0],  r1 = core_res[31:16];
        wire signed [15:0] r2 = core_res[47:32], r3 = core_res[63:48];
        reg  [1:0] best;
        reg  signed [15:0] best_v;
        always @(*) begin                         // 통합 엔진과 같은 규칙: 큰 값, 같으면 앞 번호
            best = 2'd0; best_v = r0;
            if (r1 > best_v) begin best = 2'd1; best_v = r1; end
            if (r2 > best_v) begin best = 2'd2; best_v = r2; end
            if (r3 > best_v) begin best = 2'd3; best_v = r3; end
        end
        assign e_load_ready_o = core_load_ready && !e_start_i;
        assign e_busy_o   = core_busy && eng_run;
        assign e_done_o   = core_done && eng_run;
        assign e_error_o  = core_err && eng_run;
        assign e_class_o  = best;
        assign e_scores_o = {{{25{r3[15]}}, r3}, {{25{r2[15]}}, r2}, {{25{r1[15]}}, r1}, {{25{r0[15]}}, r0}};
    end else begin : g_no_eng
        assign e_load_ready_o = 1'b0; assign e_busy_o = 1'b0; assign e_done_o = 1'b0; assign e_error_o = 1'b0;
        assign e_class_o = 2'd0; assign e_scores_o = 164'd0;
    end endgenerate

    // ---------------- 콘솔 명령 처리 ----------------
    localparam [2:0] S_IDLE = 3'd0, S_RDW = 3'd1, S_QW = 3'd2, S_SRD = 3'd3, S_SRDW = 3'd4,
                     S_PUSH = 3'd5, S_SWAIT = 3'd6, S_CWAIT = 3'd7;
    reg [2:0] state;
    reg [3:0] cur_op;
    reg [5:0] idx;

    function stage_ok(input [3:0] op);
        stage_ok = (op <= OP_WRD) ||
                   (op == OP_QNT && STAGE >= 2) || (op == OP_DOT && STAGE >= 3) ||
                   (op == OP_PE4 && STAGE >= 4) || (op == OP_DENSE && STAGE >= 5) || (op == OP_CORE && STAGE >= 6);
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE; cur_op <= 4'd0; idx <= 6'd0;
            op_done_o <= 1'b0; op_error_o <= 1'b0; res_o <= 160'd0; flags_o <= 4'd0;
            rd_en <= 1'b0; rd_addr <= 6'd0; q_valid <= 1'b0;
            seq_op <= 4'd0; start <= 1'b0; length <= 9'd0; push <= 1'b0; x_q <= 16'sd0; w_q <= 64'd0;
            core_start_c <= 1'b0; eng_run <= 1'b0;
        end else begin
            op_done_o <= 1'b0; op_error_o <= 1'b0;
            rd_en <= 1'b0; q_valid <= 1'b0; start <= 1'b0; core_start_c <= 1'b0;
            if (eng && e_start_i) eng_run <= 1'b1;
            case (state)
                S_IDLE: if (op_valid_i && !eng) begin
                    cur_op <= op_i;
                    if (!stage_ok(op_i) || ((op_i >= OP_DOT) && (len_i == 7'd0 || len_i > 7'd64))) begin
                        op_error_o <= 1'b1; op_done_o <= 1'b1;
                    end else case (op_i)
                        OP_XWR, OP_WWR, OP_BWR: op_done_o <= 1'b1;
                        OP_XRD, OP_WRD: begin rd_en <= 1'b1; rd_addr <= addr_i; state <= S_RDW; end
                        OP_QNT: begin q_valid <= 1'b1; state <= S_QW; end
                        OP_DOT, OP_PE4, OP_DENSE: begin
                            seq_op <= op_i; length <= {2'b00, len_i}; start <= 1'b1; idx <= 6'd0; state <= S_SRD;
                        end
                        OP_CORE: begin core_start_c <= 1'b1; eng_run <= 1'b0; state <= S_CWAIT; end
                        default: begin op_error_o <= 1'b1; op_done_o <= 1'b1; end
                    endcase
                end
                S_RDW: if (x_rv) begin            // BRAM 동기 읽기: rd_valid가 선 클록에 값
                    res_o <= {144'd0, (cur_op == OP_XRD) ? x_rd : w_rd[neuron_i*16 +: 16]};
                    op_done_o <= 1'b1; state <= S_IDLE;
                end
                S_QW: if (q_done) begin
                    res_o <= {152'd0, q_out}; flags_o <= {3'd0, q_ov}; op_done_o <= 1'b1; state <= S_IDLE;
                end
                S_SRD: begin rd_en <= 1'b1; rd_addr <= idx; state <= S_SRDW; end
                S_SRDW: if (x_rv) begin x_q <= x_rd; w_q <= w_rd; push <= 1'b1; state <= S_PUSH; end
                S_PUSH: if (seq_ready) begin      // 이 클록에 모듈이 원소를 받는다
                    push <= 1'b0;
                    if ({1'b0, idx} + 7'd1 == length[6:0]) state <= S_SWAIT;
                    else begin idx <= idx + 6'd1; state <= S_SRD; end
                end
                S_SWAIT: if (seq_done || seq_err) begin
                    res_o <= (seq_op == OP_DOT) ? {120'd0, dot_res} : (seq_op == OP_PE4) ? pe_res : {96'd0, dn_res};
                    flags_o <= (seq_op == OP_DENSE) ? dn_ov : 4'd0;
                    op_error_o <= seq_err; op_done_o <= 1'b1; state <= S_IDLE;
                end
                S_CWAIT: if (core_done || core_err) begin
                    res_o <= {96'd0, core_res}; flags_o <= core_ov;
                    op_error_o <= core_err; op_done_o <= 1'b1; state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
            if (core_done || core_err) eng_run <= 1'b0;
        end
    end
endmodule
`default_nettype wire
