`timescale 1ns/1ps
`default_nettype none
// 17장 784원소 10분류: 28×28 입력을 64원소 타일 13개(64×12 + 16)로 나눠 15장 Dense 코어를 13번 돌린다.
// 타일별 부분합은 코어 밖 누산기에서 더하고, Bias는 13타일이 끝난 뒤 한 번만 더한 다음 16장 argmax로 클래스를 낸다.
module npu_tiled_784 #(
    parameter integer ACC_WIDTH = 32
) (
    input  wire                     clk,
    input  wire                     resetn,
    input  wire                     x_wr_en_i,          // 입력 784원소 쓰기 (INT8, 0~127)
    input  wire               [9:0] x_addr_i,
    input  wire               [7:0] x_data_i,
    input  wire                     w_wr_en_i,          // 가중치 10×784 쓰기
    input  wire               [3:0] w_neuron_i,
    input  wire               [9:0] w_addr_i,
    input  wire               [7:0] w_data_i,
    input  wire                     b_wr_en_i,
    input  wire               [3:0] b_neuron_i,
    input  wire     [ACC_WIDTH-1:0] b_data_i,
    input  wire                     start_i,
    output wire                     busy_o,
    output reg                      tile_done_o,        // 타일 하나 누산 완료 1클록 펄스
    output reg                [3:0] tile_o,             // 지금 실행 중인 타일 번호 0~12
    output reg                [3:0] tile_done_num_o,    // tile_done_o가 가리키는 (방금 끝난) 타일 번호
    output wire               [6:0] tile_len_o,         // 지금 타일 원소 수 (0~11: 64, 12: 16)
    output wire [10*ACC_WIDTH-1:0]  acc_o,              // 타일 부분합 누계 (Bias 없음)
    output wire [10*ACC_WIDTH-1:0]  scores_o,           // 누계 + Bias (13타일 뒤)
    output reg                      done_o,
    output reg                      error_o,
    output wire               [3:0] class_o
);
    localparam integer TILES = 13, LAST_LEN = 784 - 64 * 12;
    localparam IDLE=0, TILE_START=1, TILE_RUN=2, BIAS=3, AM_GO=4, AM_WAIT=5;
    reg [2:0] state;
    reg signed [ACC_WIDTH-1:0] acc_q [0:9];
    reg signed [ACC_WIDTH-1:0] score_q [0:9];
    reg signed [ACC_WIDTH-1:0] bias_q [0:9];
    integer i;

    assign busy_o = (state != IDLE);
    assign tile_len_o = (tile_o == TILES - 1) ? LAST_LEN[6:0] : 7'd64;

    // ── 15장 코어: 읽기 포트를 타일 주소로 바꿔 연결
    wire x_rd_en, w_rd_en; wire [5:0] x_idx, w_idx; wire [1:0] w_group;
    wire signed [7:0] x_rd; wire x_rv; wire [31:0] w_rd; wire [3:0] w_rv;
    wire core_done, core_err; wire [10*ACC_WIDTH-1:0] dots;
    npu_dense_core #(.N_OUT(10), .ACC_WIDTH(ACC_WIDTH)) core (
        .clk(clk), .resetn(resetn), .start_i(state == TILE_START), .len_i(tile_len_o),
        .x_rd_en_o(x_rd_en), .x_rd_idx_o(x_idx), .x_data_i(x_rd), .x_valid_i(x_rv),
        .w_rd_en_o(w_rd_en), .w_rd_group_o(w_group), .w_rd_idx_o(w_idx), .w_data_i(w_rd), .w_valid_i(w_rv),
        .busy_o(), .done_o(core_done), .error_o(core_err), .dots_o(dots));

    wire [9:0] x_tile_addr = {tile_o, 6'd0} + x_idx;      // 타일 t의 원소 i = 전체 주소 t*64 + i
    wire [9:0] w_tile_addr = {tile_o, 6'd0} + w_idx;
    bram_sync_buffer #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) x_ram (
        .clk(clk), .resetn(resetn), .wr_en(x_wr_en_i && !busy_o), .wr_addr(x_addr_i), .wr_data(x_data_i),
        .rd_en(x_rd_en), .rd_addr(x_tile_addr), .rd_data(x_rd), .rd_valid(x_rv));
    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : lane
        bram_sync_buffer #(.DATA_WIDTH(8), .ADDR_WIDTH(12)) w_ram (
            .clk(clk), .resetn(resetn),
            .wr_en(w_wr_en_i && !busy_o && w_neuron_i <= 9 && w_neuron_i[1:0] == g),
            .wr_addr({w_neuron_i[3:2], w_addr_i}), .wr_data(w_data_i),
            .rd_en(w_rd_en), .rd_addr({w_group, w_tile_addr}), .rd_data(w_rd[g*8 +: 8]), .rd_valid(w_rv[g]));
    end endgenerate
    generate for (g = 0; g < 10; g = g + 1) begin : o
        assign acc_o[g*ACC_WIDTH +: ACC_WIDTH] = acc_q[g];
        assign scores_o[g*ACC_WIDTH +: ACC_WIDTH] = score_q[g];
    end endgenerate

    wire am_done;
    npu_argmax #(.N(10), .W(ACC_WIDTH)) argmax (
        .clk(clk), .resetn(resetn), .start_i(state == AM_GO), .scores_i(scores_o),
        .busy_o(), .done_o(am_done), .class_o(class_o));

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE; tile_o <= 0; tile_done_num_o <= 0; tile_done_o <= 0; done_o <= 0; error_o <= 0;
            for (i = 0; i < 10; i = i + 1) begin acc_q[i] <= 0; score_q[i] <= 0; bias_q[i] <= 0; end
        end else begin
            tile_done_o <= 0; done_o <= 0; error_o <= 0;
            if (b_wr_en_i && !busy_o && b_neuron_i <= 9) bias_q[b_neuron_i] <= b_data_i;
            case (state)
                IDLE: if (start_i) begin
                    tile_o <= 0; state <= TILE_START;
                    for (i = 0; i < 10; i = i + 1) acc_q[i] <= 0;
                end
                TILE_START: state <= TILE_RUN;
                TILE_RUN: if (core_err) begin state <= IDLE; error_o <= 1; end
                    else if (core_done) begin                  // 코어 밖에서 타일 부분합 누산
                        for (i = 0; i < 10; i = i + 1) acc_q[i] <= acc_q[i] + $signed(dots[i*ACC_WIDTH +: ACC_WIDTH]);
                        tile_done_o <= 1; tile_done_num_o <= tile_o;
                        if (tile_o == TILES - 1) state <= BIAS;
                        else begin tile_o <= tile_o + 4'd1; state <= TILE_START; end
                    end
                BIAS: begin                                     // Bias는 13타일 누산 뒤 한 번
                    for (i = 0; i < 10; i = i + 1) score_q[i] <= acc_q[i] + bias_q[i];
                    state <= AM_GO;
                end
                AM_GO: state <= AM_WAIT;
                AM_WAIT: if (am_done) begin state <= IDLE; done_o <= 1; end
                default: begin state <= IDLE; error_o <= 1; end
            endcase
        end
    end
endmodule
`default_nettype wire
