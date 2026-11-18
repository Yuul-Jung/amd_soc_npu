`timescale 1ns/1ps
`default_nettype none
// 26장 소형 CNN: 8×8 입력(13장 계약) → 3×3 합성곱 필터 4개(보폭 1, 여백 없음) → ReLU·05장 양자화 → 6×6×4
//                → 2×2 최대 풀링 → 3×3×4 = 36특징 → 15장 Dense 64→10(36~63번 입력은 0) → 16장 argmax.
// 합성곱 출력 하나는 07장 내적 코어로 길이 9 내적을 한 번 돌려 만든다. 기존 NPU 파일은 고치지 않는다.
module npu_cnn3x3 #(
    parameter integer SHIFT = 6                  // 합성곱 출력 = sat_int8(round(ReLU(내적 + Bias) / 2^SHIFT))
) (
    input  wire                 clk,
    input  wire                 resetn,
    input  wire                 x_wr_en_i,       // 입력 8×8 (INT8, 0~127)
    input  wire           [5:0] x_addr_i,
    input  wire           [7:0] x_data_i,
    input  wire                 k_wr_en_i,       // 합성곱 가중치: 필터 f, 위치 0~8 (행 우선)
    input  wire           [1:0] k_filter_i,
    input  wire           [3:0] k_addr_i,
    input  wire           [7:0] k_data_i,
    input  wire                 kb_wr_en_i,      // 합성곱 Bias (필터별 32비트)
    input  wire           [1:0] kb_filter_i,
    input  wire          [31:0] kb_data_i,
    input  wire                 d_w_wr_en_i,     // Dense 가중치·Bias (15장 포트 그대로)
    input  wire           [3:0] d_neuron_i,
    input  wire           [5:0] d_addr_i,
    input  wire           [7:0] d_data_i,
    input  wire                 d_b_wr_en_i,
    input  wire          [31:0] d_b_data_i,
    input  wire                 start_i,
    output wire                 busy_o,
    output wire         [287:0] pooled_o,        // 36특징 (f*9 + py*3 + px)
    output wire         [319:0] scores_o,
    output reg                  done_o,
    output reg                  error_o,
    output wire           [3:0] class_o
);
    localparam IDLE=0, CONV_GO=1, CONV_FEED=2, CONV_WAIT=3, CONV_Q=4, POOL=5, DENSE=6, ARGMAX=7;
    reg [2:0] state;
    reg signed [7:0]  x_q  [0:63];
    reg signed [7:0]  k_q  [0:35];
    reg signed [31:0] kb_q [0:3];
    reg signed [7:0]  conv_q [0:143];           // f*36 + oy*6 + ox
    reg signed [7:0]  pool_q [0:35];
    reg [1:0] f_q; reg [2:0] oy_q, ox_q; reg [3:0] t_q; reg [5:0] p_q;
    integer i;
    wire busy = (state != IDLE);
    assign busy_o = busy;

    always @(posedge clk) begin                  // 쓰기 포트 (실행 중 무시)
        if (x_wr_en_i && !busy) x_q[x_addr_i] <= x_data_i;
        if (k_wr_en_i && !busy && k_addr_i < 9) k_q[k_filter_i * 9 + k_addr_i] <= k_data_i;
        if (kb_wr_en_i && !busy) kb_q[kb_filter_i] <= kb_data_i;
    end

    // ── 합성곱 출력 1개 = 길이 9 내적 (07장 코어)
    wire [1:0] ky = (t_q >= 6) ? 2'd2 : (t_q >= 3) ? 2'd1 : 2'd0;
    wire [1:0] kx = t_q - ky * 3;
    wire signed [7:0] a = x_q[(oy_q + ky) * 8 + ox_q + kx];
    wire signed [7:0] b = k_q[f_q * 9 + t_q];
    wire dot_ready, dot_done; wire signed [31:0] dot;
    vector_dot_core #(.DATA_WIDTH(8), .ACC_WIDTH(32)) conv_dot (
        .clk(clk), .resetn(resetn), .start_i(state == CONV_GO), .valid_i(state == CONV_FEED), .length_i(9'd9),
        .a_i(a), .b_i(b), .ready_o(dot_ready), .busy_o(), .done_o(dot_done), .error_o(), .result_o(dot));

    // ── ReLU → 05장 양자화기 (1클록)
    wire signed [31:0] pre = dot + kb_q[f_q];
    wire signed [31:0] relu = pre[31] ? 32'sd0 : pre;
    wire signed [7:0] q; wire q_valid;
    fixed_quantizer #(.IN_WIDTH(32), .OUT_WIDTH(8), .SHIFT(SHIFT), .ROUND(1), .SATURATE(1)) quant (
        .clk(clk), .resetn(resetn), .valid_i(state == CONV_WAIT && dot_done), .x_i(relu),
        .q_o(q), .valid_o(q_valid), .overflow_o());

    // ── 2×2 최대 풀링 (ReLU 뒤라 모두 0 이상)
    wire [1:0] pf = p_q / 9; wire [3:0] pr = p_q % 9; wire [1:0] py = pr / 3; wire [1:0] px = pr % 3;
    wire [7:0] base = pf * 36 + py * 12 + px * 2;                       // (2py)*6 + 2px
    wire signed [7:0] m0 = conv_q[base], m1 = conv_q[base + 1], m2 = conv_q[base + 6], m3 = conv_q[base + 7];
    wire signed [7:0] m01 = (m1 > m0) ? m1 : m0, m23 = (m3 > m2) ? m3 : m2;
    wire signed [7:0] mx = (m23 > m01) ? m23 : m01;

    // ── 15장 Dense 64→10 (입력 = 풀링 36개, 나머지 0, 1클록 지연 읽기)
    wire d_x_en; wire [5:0] d_x_idx; reg signed [7:0] d_x; reg d_xv;
    wire d_done, d_err;
    npu_dense #(.N_IN(64), .N_OUT(10), .ACC_WIDTH(32)) dense (
        .clk(clk), .resetn(resetn), .model_clear_i(1'b0),
        .w_wr_en_i(d_w_wr_en_i && !busy), .w_neuron_i(d_neuron_i), .w_addr_i(d_addr_i), .w_data_i(d_data_i),
        .b_wr_en_i(d_b_wr_en_i && !busy), .b_neuron_i(d_neuron_i), .b_data_i(d_b_data_i),
        .model_sum_o(), .model_err_o(),
        .x_rd_en_o(d_x_en), .x_rd_idx_o(d_x_idx), .x_data_i(d_x), .x_valid_i(d_xv),
        .start_i(state == POOL && p_q == 36), .busy_o(), .done_o(d_done), .error_o(d_err), .scores_o(scores_o));
    always @(posedge clk) begin
        d_xv <= resetn && d_x_en;
        if (d_x_en) d_x <= (d_x_idx < 36) ? pool_q[d_x_idx] : 8'sd0;
    end

    wire am_done;
    npu_argmax #(.N(10), .W(32)) argmax (
        .clk(clk), .resetn(resetn), .start_i(d_done), .scores_i(scores_o), .busy_o(), .done_o(am_done), .class_o(class_o));

    genvar g;
    generate for (g = 0; g < 36; g = g + 1) begin : po
        assign pooled_o[g*8 +: 8] = pool_q[g];
    end endgenerate

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE; f_q <= 0; oy_q <= 0; ox_q <= 0; t_q <= 0; p_q <= 0; done_o <= 0; error_o <= 0;
        end else begin
            done_o <= 0; error_o <= 0;
            case (state)
                IDLE: if (start_i) begin f_q <= 0; oy_q <= 0; ox_q <= 0; state <= CONV_GO; end
                CONV_GO: begin t_q <= 0; state <= CONV_FEED; end
                CONV_FEED: if (dot_ready) begin                 // 9쌍을 한 클록에 하나씩
                    if (t_q == 8) state <= CONV_WAIT; else t_q <= t_q + 4'd1;
                end
                CONV_WAIT: if (dot_done) state <= CONV_Q;
                CONV_Q: if (q_valid) begin                      // 양자화 결과 저장, 다음 위치·필터
                    conv_q[f_q * 36 + oy_q * 6 + ox_q] <= q;
                    if (ox_q != 5) begin ox_q <= ox_q + 3'd1; state <= CONV_GO; end
                    else if (oy_q != 5) begin ox_q <= 0; oy_q <= oy_q + 3'd1; state <= CONV_GO; end
                    else if (f_q != 3) begin ox_q <= 0; oy_q <= 0; f_q <= f_q + 2'd1; state <= CONV_GO; end
                    else begin p_q <= 0; state <= POOL; end
                end
                POOL: begin                                     // p_q 0~35: 풀링 1개씩, 36: Dense 시작
                    if (p_q < 36) begin pool_q[p_q] <= mx; p_q <= p_q + 6'd1; end
                    else state <= DENSE;
                end
                DENSE: if (d_err) begin state <= IDLE; error_o <= 1; end
                    else if (d_done) state <= ARGMAX;
                ARGMAX: if (am_done) begin state <= IDLE; done_o <= 1; end
                default: begin state <= IDLE; error_o <= 1; end
            endcase
        end
    end
endmodule
`default_nettype wire
