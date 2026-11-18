`timescale 1ns/1ps
`default_nettype none
// 18장 데이터 폭 매개변수 784→10: 17장과 같은 13타일·코어 밖 누산·Bias 한 번 구조를 DATA_WIDTH(8 또는 16)로 일반화한다.
// 15장 코어는 8비트로 고정이므로, 08장 4PE를 직접 써서 타일(13)·그룹(3) 반복을 이 모듈 하나에 둔다.
// INT16 최악: |내적| ≤ 784·32640·32768 (41비트) + Bias → ACC_WIDTH 48 사용.
module npu_tiled_784_p #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ACC_WIDTH = 32
) (
    input  wire                      clk,
    input  wire                      resetn,
    input  wire                      x_wr_en_i,
    input  wire                [9:0] x_addr_i,
    input  wire     [DATA_WIDTH-1:0] x_data_i,
    input  wire                      w_wr_en_i,
    input  wire                [3:0] w_neuron_i,
    input  wire                [9:0] w_addr_i,
    input  wire     [DATA_WIDTH-1:0] w_data_i,
    input  wire                      b_wr_en_i,
    input  wire                [3:0] b_neuron_i,
    input  wire      [ACC_WIDTH-1:0] b_data_i,
    input  wire                      start_i,
    output wire                      busy_o,
    output wire [10*ACC_WIDTH-1:0]   scores_o,
    output reg                       done_o,
    output reg                       error_o,
    output wire                [3:0] class_o,
    output reg                [15:0] cycles_o
);
    localparam integer DW = DATA_WIDTH;
    localparam IDLE=0, LAUNCH=1, READ=2, WAIT_READ=3, SEND=4, WAIT_PE=5, BIAS=6, AM_GO=7, AM_WAIT=8;
    reg [3:0] state;
    reg [3:0] tile_q;                                     // 0~12
    reg [1:0] group_q;                                    // 0~2
    reg [5:0] idx_q;
    reg signed [ACC_WIDTH-1:0] acc_q [0:9];
    reg signed [ACC_WIDTH-1:0] score_q [0:9];
    reg signed [ACC_WIDTH-1:0] bias_q [0:9];
    integer i;

    wire [6:0] len = (tile_q == 4'd12) ? 7'd16 : 7'd64;
    wire [9:0] addr = {tile_q, 6'd0} + idx_q;
    assign busy_o = (state != IDLE);

    wire signed [DW-1:0] x_rd; wire x_rv;
    bram_sync_buffer #(.DATA_WIDTH(DW), .ADDR_WIDTH(10)) x_ram (
        .clk(clk), .resetn(resetn), .wr_en(x_wr_en_i && !busy_o), .wr_addr(x_addr_i), .wr_data(x_data_i),
        .rd_en(state == READ), .rd_addr(addr), .rd_data(x_rd), .rd_valid(x_rv));
    wire [4*DW-1:0] w_rd, w_bus; wire [3:0] w_rv;
    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : lane
        bram_sync_buffer #(.DATA_WIDTH(DW), .ADDR_WIDTH(12)) w_ram (
            .clk(clk), .resetn(resetn),
            .wr_en(w_wr_en_i && !busy_o && w_neuron_i <= 9 && w_neuron_i[1:0] == g),
            .wr_addr({w_neuron_i[3:2], w_addr_i}), .wr_data(w_data_i),
            .rd_en(state == READ), .rd_addr({group_q, addr}), .rd_data(w_rd[g*DW +: DW]), .rd_valid(w_rv[g]));
        assign w_bus[g*DW +: DW] = (group_q == 2'd2 && g >= 2) ? {DW{1'b0}} : w_rd[g*DW +: DW];
    end endgenerate
    generate for (g = 0; g < 10; g = g + 1) begin : o
        assign scores_o[g*ACC_WIDTH +: ACC_WIDTH] = score_q[g];
    end endgenerate

    wire [3:0] pe_ready; wire pe_done; wire [4*ACC_WIDTH-1:0] pe_res;
    pe_array4 #(.DATA_WIDTH(DW), .ACC_WIDTH(ACC_WIDTH)) pe (
        .clk(clk), .resetn(resetn), .start_i(state == LAUNCH), .length_i({2'b00, len}),
        .valid_i({4{state == SEND}}), .a_i({4{x_rd}}), .b_i(w_bus),
        .ready_o(pe_ready), .busy_o(), .done_o(pe_done), .error_o(), .pe_results_o(pe_res), .sum_o());

    wire am_done;
    npu_argmax #(.N(10), .W(ACC_WIDTH)) argmax (
        .clk(clk), .resetn(resetn), .start_i(state == AM_GO), .scores_i(scores_o),
        .busy_o(), .done_o(am_done), .class_o(class_o));

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE; tile_q <= 0; group_q <= 0; idx_q <= 0; done_o <= 0; error_o <= 0; cycles_o <= 0;
            for (i = 0; i < 10; i = i + 1) begin acc_q[i] <= 0; score_q[i] <= 0; bias_q[i] <= 0; end
        end else begin
            done_o <= 0; error_o <= 0;
            if (busy_o) cycles_o <= cycles_o + 16'd1;
            if (b_wr_en_i && !busy_o && b_neuron_i <= 9) bias_q[b_neuron_i] <= b_data_i;
            case (state)
                IDLE: if (start_i) begin
                    tile_q <= 0; group_q <= 0; idx_q <= 0; cycles_o <= 0; state <= LAUNCH;
                    for (i = 0; i < 10; i = i + 1) acc_q[i] <= 0;
                end
                LAUNCH: state <= READ;
                READ: state <= WAIT_READ;
                WAIT_READ: if (x_rv && (&w_rv)) state <= SEND;
                    else begin state <= IDLE; error_o <= 1; end
                SEND: if (&pe_ready) begin
                    if (idx_q == len - 7'd1) state <= WAIT_PE;
                    else begin idx_q <= idx_q + 6'd1; state <= READ; end
                end
                WAIT_PE: if (pe_done) begin                    // 코어 밖 누산: 그룹의 뉴런 4개(마지막 그룹 2개)
                    for (i = 0; i < 10; i = i + 1)
                        if (i / 4 == group_q) acc_q[i] <= acc_q[i] + $signed(pe_res[(i % 4)*ACC_WIDTH +: ACC_WIDTH]);
                    idx_q <= 0;
                    if (group_q != 2'd2) begin group_q <= group_q + 2'd1; state <= LAUNCH; end
                    else if (tile_q != 4'd12) begin group_q <= 0; tile_q <= tile_q + 4'd1; state <= LAUNCH; end
                    else state <= BIAS;
                end
                BIAS: begin
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
