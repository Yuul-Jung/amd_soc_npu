`timescale 1ns/1ps
`default_nettype none
// 14장 그룹 스케줄러: 08장 4PE를 4+4+2 세 그룹으로 세 번 돌려 10개 점수(내적 + Bias)를 모으고,
// 동점이면 낮은 번호를 고르는 argmax로 클래스 0~9를 낸다.
// 입력 64원소는 13장 적재기, 가중치는 차선(PE)별 04장 BRAM 4개 (주소 = 그룹*64 + 원소).
// 클래스 c → 그룹 c/4, 차선 c%4. 마지막 그룹의 차선 2·3은 클래스가 없으므로 가중치 0을 넣고 결과를 버린다.
module npu10_group_scheduler #(
    parameter integer ACC_WIDTH = 32
) (
    input  wire                      clk,
    input  wire                      resetn,
    input  wire                      load_start_i,
    input  wire                      in_valid_i,
    input  wire                [7:0] in_data_i,
    input  wire                      in_last_i,
    output wire                      x_loaded_o,
    output wire                      x_len_err_o,
    output wire                      x_range_err_o,
    input  wire                      w_wr_en_i,
    input  wire                [3:0] w_class_i,
    input  wire                [5:0] w_addr_i,
    input  wire                [7:0] w_data_i,
    input  wire                      b_wr_en_i,
    input  wire                [3:0] b_class_i,
    input  wire      [ACC_WIDTH-1:0] b_data_i,
    input  wire                      start_i,
    output reg                       busy_o,
    output reg                       done_o,
    output reg                       error_o,
    output reg                 [3:0] class_o,
    output wire [10*ACC_WIDTH-1:0]   scores_o,
    output reg                [15:0] cycles_o
);
    localparam IDLE=0, LAUNCH=1, READ=2, WAIT_READ=3, SEND=4, WAIT_PE=5, ARGMAX=6;
    reg [2:0] state;
    reg [1:0] group_q;                 // 0: 클래스 0~3, 1: 4~7, 2: 8~9
    reg [5:0] idx_q;                   // 원소 번호 0~63
    reg [3:0] k_q;                     // argmax 비교 번호 1~9
    reg signed [ACC_WIDTH-1:0] bias_q  [0:9];
    reg signed [ACC_WIDTH-1:0] score_q [0:9];
    integer i;

    // ── 13장 입력 적재기 (64원소, 읽기는 이 모듈이 담당)
    wire signed [7:0] x_data;
    wire x_valid;
    npu10_input_loader loader (
        .clk(clk), .resetn(resetn), .load_start_i(load_start_i), .in_valid_i(in_valid_i),
        .in_data_i(in_data_i), .in_last_i(in_last_i), .rd_en_i(state == READ), .rd_addr_i(idx_q),
        .rd_data_o(x_data), .rd_valid_o(x_valid), .loading_o(), .loaded_o(x_loaded_o),
        .len_err_o(x_len_err_o), .range_err_o(x_range_err_o), .count_o());

    // ── 가중치 BRAM 4개 (차선별 8비트×256, 그룹 3개 × 64원소 사용)
    wire w_ok = w_wr_en_i && !busy_o && (w_class_i <= 4'd9);
    wire [31:0] w_bus;                 // 4차선 × 8비트, PE 입력
    wire [3:0]  w_valid;
    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : lane
        wire signed [7:0] w_rd;
        bram_sync_buffer #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) weight_ram (
            .clk(clk), .resetn(resetn),
            .wr_en(w_ok && w_class_i[1:0] == g), .wr_addr({w_class_i[3:2], w_addr_i}), .wr_data(w_data_i),
            .rd_en(state == READ), .rd_addr({group_q, idx_q}),
            .rd_data(w_rd), .rd_valid(w_valid[g]));
        // 그룹 2의 차선 2·3은 클래스 10·11이 없으므로 0을 곱한다.
        assign w_bus[g*8 +: 8] = (group_q == 2'd2 && g >= 2) ? 8'sd0 : w_rd;
        assign scores_o[g*ACC_WIDTH +: ACC_WIDTH] = score_q[g];
        assign scores_o[(g+4)*ACC_WIDTH +: ACC_WIDTH] = score_q[g+4];
    end endgenerate
    assign scores_o[8*ACC_WIDTH +: 2*ACC_WIDTH] = {score_q[9], score_q[8]};

    // ── 08장 4PE (같은 입력 x를 4차선에 나눠 주고 차선별 가중치와 곱해 누산)
    wire [3:0] pe_ready;
    wire pe_done;
    wire [4*ACC_WIDTH-1:0] pe_res;
    pe_array4 #(.DATA_WIDTH(8), .ACC_WIDTH(ACC_WIDTH)) pe (
        .clk(clk), .resetn(resetn), .start_i(state == LAUNCH), .length_i(9'd64),
        .valid_i({4{state == SEND}}), .a_i({4{x_data}}), .b_i(w_bus),
        .ready_o(pe_ready), .busy_o(), .done_o(pe_done), .error_o(), .pe_results_o(pe_res), .sum_o());

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE; busy_o <= 0; done_o <= 0; error_o <= 0; class_o <= 0; cycles_o <= 0;
            group_q <= 0; idx_q <= 0; k_q <= 0;
            for (i = 0; i < 10; i = i + 1) begin bias_q[i] <= 0; score_q[i] <= 0; end
        end else begin
            done_o <= 0; error_o <= 0;
            if (b_wr_en_i && !busy_o && b_class_i <= 4'd9) bias_q[b_class_i] <= b_data_i;
            if (busy_o) cycles_o <= cycles_o + 16'd1;
            case (state)
                IDLE: if (start_i) begin
                    if (!x_loaded_o) error_o <= 1;           // 64원소가 없으면 시작하지 않는다
                    else begin
                        busy_o <= 1; cycles_o <= 0; group_q <= 0; idx_q <= 0; state <= LAUNCH;
                    end
                end
                LAUNCH: state <= READ;                          // 4PE 누산기 비우고 길이 64 등록
                READ: state <= WAIT_READ;                       // 입력·가중치 BRAM 읽기 요청
                WAIT_READ: if (x_valid && (&w_valid)) state <= SEND;
                    else begin state <= IDLE; busy_o <= 0; error_o <= 1; end
                SEND: if (&pe_ready) begin
                    if (idx_q == 6'd63) state <= WAIT_PE;
                    else begin idx_q <= idx_q + 6'd1; state <= READ; end
                end
                WAIT_PE: if (pe_done) begin
                    for (i = 0; i < 10; i = i + 1)
                        if (i / 4 == group_q) score_q[i] <= $signed(pe_res[(i % 4)*ACC_WIDTH +: ACC_WIDTH]) + bias_q[i];
                    idx_q <= 0;
                    if (group_q == 2'd2) begin class_o <= 0; k_q <= 1; state <= ARGMAX; end
                    else begin group_q <= group_q + 2'd1; state <= LAUNCH; end
                end
                ARGMAX: begin                                   // 한 클록에 하나씩 비교, 같으면 앞 번호 유지
                    if (score_q[k_q] > score_q[class_o]) class_o <= k_q;
                    if (k_q == 4'd9) begin state <= IDLE; busy_o <= 0; done_o <= 1; end
                    else k_q <= k_q + 4'd1;
                end
                default: begin state <= IDLE; busy_o <= 0; error_o <= 1; end
            endcase
        end
    end
endmodule
`default_nettype wire
