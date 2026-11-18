`timescale 1ns/1ps
`default_nettype none
// 15장 Dense 모델 저장소: 가중치(차선별 04장 BRAM 4개)·Bias 레지스터·적재 검증합.
// 가중치 주소 = {그룹, 원소}. 검증합 = 받아들인 가중치(부호 확장)와 Bias의 합 (mod 2^32) → PC 값과 비교.
module npu_dense_store #(
    parameter integer N_IN = 64,           // 2의 거듭제곱, 2~64
    parameter integer N_OUT = 10,          // 1~16
    parameter integer ACC_WIDTH = 32
) (
    input  wire                        clk,
    input  wire                        resetn,
    input  wire                        clear_i,      // 검증합·오류 지움
    input  wire                        wr_lock_i,    // 1이면 쓰기 무시 (연산 중)
    input  wire                        w_wr_en_i,
    input  wire                  [3:0] w_neuron_i,
    input  wire                  [5:0] w_addr_i,
    input  wire                  [7:0] w_data_i,
    input  wire                        b_wr_en_i,
    input  wire                  [3:0] b_neuron_i,
    input  wire        [ACC_WIDTH-1:0] b_data_i,
    input  wire                        w_rd_en_i,
    input  wire                  [1:0] w_rd_group_i,
    input  wire                  [5:0] w_rd_idx_i,
    output wire                 [31:0] w_data_o,
    output wire                  [3:0] w_valid_o,
    output wire [N_OUT*ACC_WIDTH-1:0]  bias_o,
    output reg                  [31:0] sum_o,
    output reg                         wr_err_o      // 범위 밖 주소·뉴런 쓰기 (무시하고 표시)
);
    localparam integer AW = $clog2(N_IN);
    reg signed [ACC_WIDTH-1:0] bias_q [0:N_OUT-1];
    integer i;
    wire w_in_range = (w_neuron_i < N_OUT) && (w_addr_i < N_IN);
    wire b_in_range = (b_neuron_i < N_OUT);
    wire w_fire = w_wr_en_i && !wr_lock_i && w_in_range;
    wire b_fire = b_wr_en_i && !wr_lock_i && b_in_range;

    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : lane
        bram_sync_buffer #(.DATA_WIDTH(8), .ADDR_WIDTH(2 + AW)) weight_ram (
            .clk(clk), .resetn(resetn),
            .wr_en(w_fire && w_neuron_i[1:0] == g), .wr_addr({w_neuron_i[3:2], w_addr_i[AW-1:0]}), .wr_data(w_data_i),
            .rd_en(w_rd_en_i), .rd_addr({w_rd_group_i, w_rd_idx_i[AW-1:0]}),
            .rd_data(w_data_o[g*8 +: 8]), .rd_valid(w_valid_o[g]));
    end endgenerate
    generate for (g = 0; g < N_OUT; g = g + 1) begin : b
        assign bias_o[g*ACC_WIDTH +: ACC_WIDTH] = bias_q[g];
    end endgenerate

    always @(posedge clk) begin
        if (!resetn) begin
            sum_o <= 0; wr_err_o <= 0;
            for (i = 0; i < N_OUT; i = i + 1) bias_q[i] <= 0;
        end else begin
            if (clear_i) begin
                sum_o <= 0; wr_err_o <= 0;
            end else begin
                if ((w_wr_en_i && !w_in_range) || (b_wr_en_i && !b_in_range)) wr_err_o <= 1;
                sum_o <= sum_o + (w_fire ? {{24{w_data_i[7]}}, w_data_i} : 32'd0)
                               + (b_fire ? b_data_i[31:0] : 32'd0);
            end
            if (b_fire) bias_q[b_neuron_i] <= b_data_i;
        end
    end
endmodule
`default_nettype wire
