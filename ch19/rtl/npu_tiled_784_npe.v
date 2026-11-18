`timescale 1ns/1ps
`default_nettype none
// 19장 PE 수 매개변수 784→10 (INT8): 07장 내적 코어를 NPE개(1·2·4·8) 나란히 두고,
// 클래스 10개를 NPE개씩 그룹 ceil(10/NPE)번에 나눠 13타일을 돈다. 차선마다 가중치 RAM 1개(읽기 포트 1개)를 둔다.
// 사이클 = 그룹 수 × 타일 실행 시간 + 마무리. NPE=4이면 18장 DW=8과 점수가 같고, 08장 pe_array4의 완료 레지스터가 없어 그룹마다 2클록 빠르다.
module npu_tiled_784_npe #(
    parameter integer NPE = 4,                       // 1, 2, 4, 8
    parameter integer ACC_WIDTH = 32
) (
    input  wire                      clk,
    input  wire                      resetn,
    input  wire                      x_wr_en_i,
    input  wire                [9:0] x_addr_i,
    input  wire                [7:0] x_data_i,
    input  wire                      w_wr_en_i,
    input  wire                [3:0] w_neuron_i,
    input  wire                [9:0] w_addr_i,
    input  wire                [7:0] w_data_i,
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
    localparam integer LG = (NPE == 1) ? 0 : $clog2(NPE);
    localparam integer GROUPS = (10 + NPE - 1) / NPE;
    localparam integer GW = (GROUPS <= 1) ? 1 : $clog2(GROUPS);
    localparam IDLE=0, LAUNCH=1, READ=2, WAIT_READ=3, SEND=4, WAIT_PE=5, BIAS=6, AM_GO=7, AM_WAIT=8;
    reg [3:0] state;
    reg [3:0] tile_q;
    reg [GW-1:0] group_q;
    reg [5:0] idx_q;
    reg [NPE-1:0] finished;
    reg signed [ACC_WIDTH-1:0] acc_q [0:9];
    reg signed [ACC_WIDTH-1:0] score_q [0:9];
    reg signed [ACC_WIDTH-1:0] bias_q [0:9];
    integer i;

    wire [6:0] len = (tile_q == 4'd12) ? 7'd16 : 7'd64;
    wire [9:0] addr = {tile_q, 6'd0} + idx_q;
    assign busy_o = (state != IDLE);

    wire signed [7:0] x_rd; wire x_rv;
    bram_sync_buffer #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) x_ram (
        .clk(clk), .resetn(resetn), .wr_en(x_wr_en_i && !busy_o), .wr_addr(x_addr_i), .wr_data(x_data_i),
        .rd_en(state == READ), .rd_addr(addr), .rd_data(x_rd), .rd_valid(x_rv));

    // 클래스 n → 그룹 n / NPE, 차선 n % NPE (NPE는 2의 거듭제곱이라 시프트·마스크)
    wire [3:0] w_lane  = (NPE == 1) ? 4'd0 : (w_neuron_i & (NPE - 1));
    wire [3:0] w_group = w_neuron_i >> LG;
    wire [NPE-1:0] ready, lane_done, w_rv;
    wire [NPE*ACC_WIDTH-1:0] res;
    genvar g;
    generate for (g = 0; g < NPE; g = g + 1) begin : lane
        wire signed [7:0] w_rd;
        bram_sync_buffer #(.DATA_WIDTH(8), .ADDR_WIDTH(GW + 10)) w_ram (
            .clk(clk), .resetn(resetn),
            .wr_en(w_wr_en_i && !busy_o && w_neuron_i <= 9 && w_lane == g),
            .wr_addr({w_group[GW-1:0], w_addr_i}), .wr_data(w_data_i),
            .rd_en(state == READ), .rd_addr({group_q, addr}), .rd_data(w_rd), .rd_valid(w_rv[g]));
        wire signed [7:0] w_use = (group_q * NPE + g >= 10) ? 8'sd0 : w_rd;   // 클래스 10 이상 차선은 0
        wire [ACC_WIDTH-1:0] r;
        vector_dot_core #(.DATA_WIDTH(8), .ACC_WIDTH(ACC_WIDTH)) dot (
            .clk(clk), .resetn(resetn), .start_i(state == LAUNCH), .valid_i(state == SEND), .length_i({2'b00, len}),
            .a_i(x_rd), .b_i(w_use), .ready_o(ready[g]), .busy_o(), .done_o(lane_done[g]), .error_o(), .result_o(r));
        assign res[g*ACC_WIDTH +: ACC_WIDTH] = r;
    end endgenerate
    generate for (g = 0; g < 10; g = g + 1) begin : o
        assign scores_o[g*ACC_WIDTH +: ACC_WIDTH] = score_q[g];
    end endgenerate

    wire am_done;
    npu_argmax #(.N(10), .W(ACC_WIDTH)) argmax (
        .clk(clk), .resetn(resetn), .start_i(state == AM_GO), .scores_i(scores_o),
        .busy_o(), .done_o(am_done), .class_o(class_o));

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE; tile_q <= 0; group_q <= 0; idx_q <= 0; finished <= 0;
            done_o <= 0; error_o <= 0; cycles_o <= 0;
            for (i = 0; i < 10; i = i + 1) begin acc_q[i] <= 0; score_q[i] <= 0; bias_q[i] <= 0; end
        end else begin
            done_o <= 0; error_o <= 0;
            if (busy_o) cycles_o <= cycles_o + 16'd1;
            if (b_wr_en_i && !busy_o && b_neuron_i <= 9) bias_q[b_neuron_i] <= b_data_i;
            if (state == LAUNCH) finished <= 0;
            else finished <= finished | lane_done;
            case (state)
                IDLE: if (start_i) begin
                    tile_q <= 0; group_q <= 0; idx_q <= 0; cycles_o <= 0; state <= LAUNCH;
                    for (i = 0; i < 10; i = i + 1) acc_q[i] <= 0;
                end
                LAUNCH: state <= READ;
                READ: state <= WAIT_READ;
                WAIT_READ: if (x_rv && (&w_rv)) state <= SEND;
                    else begin state <= IDLE; error_o <= 1; end
                SEND: if (&ready) begin
                    if (idx_q == len - 7'd1) state <= WAIT_PE;
                    else begin idx_q <= idx_q + 6'd1; state <= READ; end
                end
                WAIT_PE: if (&(finished | lane_done)) begin   // 모든 차선 완료 (같은 길이라 같은 클록)
                    for (i = 0; i < 10; i = i + 1)
                        if (i / NPE == group_q) acc_q[i] <= acc_q[i] + $signed(res[(i % NPE)*ACC_WIDTH +: ACC_WIDTH]);
                    idx_q <= 0;
                    if (group_q != GROUPS - 1) begin group_q <= group_q + 1'b1; state <= LAUNCH; end
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
