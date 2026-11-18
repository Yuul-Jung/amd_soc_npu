`timescale 1ns/1ps
`default_nettype none
// 15장 Dense 연산 코어: 08장 4PE로 뉴런 4개씩 그룹을 돌려 내적만 계산한다 (Bias는 바깥에서 더한다).
// 입력·가중치는 바깥 메모리에서 1클록 지연 읽기 포트로 받는다 → 16장(2층)·17장(타일)이 주소만 바꿔 재사용.
// 뉴런 n → 그룹 n/4, 차선 n%4. N_OUT을 넘는 차선은 가중치 0을 곱하고 결과를 버린다.
module npu_dense_core #(
    parameter integer N_OUT = 10,          // 1~16
    parameter integer ACC_WIDTH = 32
) (
    input  wire                        clk,
    input  wire                        resetn,
    input  wire                        start_i,
    input  wire                  [6:0] len_i,         // 이번 실행 원소 수 1~64
    output wire                        x_rd_en_o,
    output wire                  [5:0] x_rd_idx_o,
    input  wire signed           [7:0] x_data_i,
    input  wire                        x_valid_i,
    output wire                        w_rd_en_o,
    output wire                  [1:0] w_rd_group_o,
    output wire                  [5:0] w_rd_idx_o,
    input  wire                 [31:0] w_data_i,      // 차선 0~3 × INT8
    input  wire                  [3:0] w_valid_i,
    output reg                         busy_o,
    output reg                         done_o,
    output reg                         error_o,
    output wire [N_OUT*ACC_WIDTH-1:0]  dots_o
);
    localparam integer GROUPS = (N_OUT + 3) / 4;
    localparam IDLE=0, LAUNCH=1, READ=2, WAIT_READ=3, SEND=4, WAIT_PE=5;
    reg [2:0] state;
    reg [1:0] group_q;
    reg [5:0] idx_q;
    reg [6:0] len_q;
    reg signed [ACC_WIDTH-1:0] dot_q [0:N_OUT-1];
    integer i;

    assign x_rd_en_o = (state == READ);
    assign x_rd_idx_o = idx_q;
    assign w_rd_en_o = (state == READ);
    assign w_rd_group_o = group_q;
    assign w_rd_idx_o = idx_q;

    wire [31:0] w_bus;
    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : lane
        // 마지막 그룹에서 뉴런 번호가 N_OUT 이상인 차선은 0을 곱한다.
        assign w_bus[g*8 +: 8] = (group_q * 4 + g >= N_OUT) ? 8'd0 : w_data_i[g*8 +: 8];
    end endgenerate
    generate for (g = 0; g < N_OUT; g = g + 1) begin : out
        assign dots_o[g*ACC_WIDTH +: ACC_WIDTH] = dot_q[g];
    end endgenerate

    wire [3:0] pe_ready;
    wire pe_done;
    wire [4*ACC_WIDTH-1:0] pe_res;
    pe_array4 #(.DATA_WIDTH(8), .ACC_WIDTH(ACC_WIDTH)) pe (
        .clk(clk), .resetn(resetn), .start_i(state == LAUNCH), .length_i({2'b00, len_q}),
        .valid_i({4{state == SEND}}), .a_i({4{x_data_i}}), .b_i(w_bus),
        .ready_o(pe_ready), .busy_o(), .done_o(pe_done), .error_o(), .pe_results_o(pe_res), .sum_o());

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE; busy_o <= 0; done_o <= 0; error_o <= 0;
            group_q <= 0; idx_q <= 0; len_q <= 0;
            for (i = 0; i < N_OUT; i = i + 1) dot_q[i] <= 0;
        end else begin
            done_o <= 0; error_o <= 0;
            case (state)
                IDLE: if (start_i) begin
                    if (len_i == 0 || len_i > 7'd64) error_o <= 1;
                    else begin busy_o <= 1; len_q <= len_i; group_q <= 0; idx_q <= 0; state <= LAUNCH; end
                end
                LAUNCH: state <= READ;
                READ: state <= WAIT_READ;
                WAIT_READ: if (x_valid_i && (&w_valid_i)) state <= SEND;
                    else begin state <= IDLE; busy_o <= 0; error_o <= 1; end
                SEND: if (&pe_ready) begin
                    if (idx_q == len_q - 7'd1) state <= WAIT_PE;
                    else begin idx_q <= idx_q + 6'd1; state <= READ; end
                end
                WAIT_PE: if (pe_done) begin
                    for (i = 0; i < N_OUT; i = i + 1)
                        if (i / 4 == group_q) dot_q[i] <= $signed(pe_res[(i % 4)*ACC_WIDTH +: ACC_WIDTH]);
                    idx_q <= 0;
                    if (group_q == GROUPS - 1) begin state <= IDLE; busy_o <= 0; done_o <= 1; end
                    else begin group_q <= group_q + 2'd1; state <= LAUNCH; end
                end
                default: begin state <= IDLE; busy_o <= 0; error_o <= 1; end
            endcase
        end
    end
endmodule
`default_nettype wire
