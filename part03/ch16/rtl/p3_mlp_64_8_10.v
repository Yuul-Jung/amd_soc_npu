`timescale 1ns/1ps
// (추가) 16장: 64→8→10 정수 MLP. 14장 코어를 두 계층으로 재사용한다.
//   1층: p3_group10_core #(64, 8)  x = 13장 프레임 버퍼(외부 읽기 포트)
//   재양자화: p3_relu_requant × 8  hidden = sat_int8(round_shift_away(max(0, s1), shift))
//   2층: p3_group10_core #(8, 10)  x = 내부 은닉 레지스터(1클록 지연 읽기)
// 가중치·Bias 쓰기는 wr_layer_i(0=1층, 1=2층)로 선택하며, MLP 동작 중에는 두 계층 모두 쓰기를 막는다.
// shift_i는 start 시점에 래치한다.
module p3_mlp_64_8_10(
    input wire clk,
    input wire resetn,
    input wire start_i,
    input wire [4:0] shift_i,
    input wire x_valid_i,
    output wire x_rd_en_o,
    output wire [5:0] x_rd_addr_o,
    input wire signed [7:0] x_rd_data_i,
    input wire wr_layer_i,
    input wire w_wr_en_i,
    input wire b_wr_en_i,
    input wire [3:0] wr_class_i,
    input wire [5:0] wr_addr_i,
    input wire signed [7:0] w_data_i,
    input wire signed [23:0] b_data_i,
    output wire load_ready_o,
    output reg busy_o,
    output reg done_o,
    output wire error_o,
    output reg [3:0] class_o,
    output wire [249:0] scores_o,
    output wire [63:0] hidden_o
);
    localparam [2:0] IDLE=3'd0, L1=3'd1, L2_START=3'd2, L2=3'd3;
    reg [2:0] state;
    reg [4:0] shift_q;
    reg start1_q, start2_q, error_q;
    reg signed [7:0] hidden [0:7];
    reg signed [7:0] hid_rd_data;

    assign load_ready_o = resetn && !busy_o;
    // MLP 동작 중에는 어느 계층에도 쓰기를 전달하지 않는다.
    wire wr_any = w_wr_en_i || b_wr_en_i;
    wire w1_wr = w_wr_en_i && !wr_layer_i && load_ready_o;
    wire b1_wr = b_wr_en_i && !wr_layer_i && load_ready_o;
    wire w2_wr = w_wr_en_i && wr_layer_i && load_ready_o;
    wire b2_wr = b_wr_en_i && wr_layer_i && load_ready_o;

    wire done1, err1, done2, err2;
    wire [3:0] class2;
    wire [199:0] scores1;
    wire h_rd_en;
    wire [5:0] h_rd_addr;

    p3_group10_core #(.IN_LEN(64), .OUT_N(8)) layer1(
        .clk(clk), .resetn(resetn), .start_i(start1_q), .x_valid_i(x_valid_i),
        .x_rd_en_o(x_rd_en_o), .x_rd_addr_o(x_rd_addr_o), .x_rd_data_i(x_rd_data_i),
        .w_wr_en_i(w1_wr), .b_wr_en_i(b1_wr), .wr_class_i(wr_class_i), .wr_addr_i(wr_addr_i),
        .w_data_i(w_data_i), .b_data_i(b_data_i), .load_ready_o(),
        .busy_o(), .done_o(done1), .error_o(err1), .class_o(), .scores_o(scores1));
    p3_group10_core #(.IN_LEN(8), .OUT_N(10)) layer2(
        .clk(clk), .resetn(resetn), .start_i(start2_q), .x_valid_i(1'b1),
        .x_rd_en_o(h_rd_en), .x_rd_addr_o(h_rd_addr), .x_rd_data_i(hid_rd_data),
        .w_wr_en_i(w2_wr), .b_wr_en_i(b2_wr), .wr_class_i(wr_class_i), .wr_addr_i(wr_addr_i),
        .w_data_i(w_data_i), .b_data_i(b_data_i), .load_ready_o(),
        .busy_o(), .done_o(done2), .error_o(err2), .class_o(class2), .scores_o(scores_o));

    wire signed [7:0] q [0:7];
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : requant
            p3_relu_requant rq(.score_i(scores1[g*25 +: 25]), .shift_i(shift_q), .q_o(q[g]));
            assign hidden_o[g*8 +: 8] = hidden[g];
        end
    endgenerate

    // 2층 x 읽기: 13장 버퍼와 같은 1클록 지연 계약
    always @(posedge clk)
        if (h_rd_en)
            hid_rd_data <= hidden[h_rd_addr[2:0]];

    assign error_o = error_q || err1 || err2;

    integer k;
    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            shift_q <= 5'd0;
            start1_q <= 1'b0;
            start2_q <= 1'b0;
            error_q <= 1'b0;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            class_o <= 4'd0;
            for (k = 0; k < 8; k = k + 1)
                hidden[k] <= 8'sd0;
        end else begin
            start1_q <= 1'b0;
            start2_q <= 1'b0;
            done_o <= 1'b0;
            error_q <= 1'b0;
            // 동작 중 쓰기·start, 프레임 없는 start는 무시하고 오류 펄스
            if (wr_any && !load_ready_o)
                error_q <= 1'b1;
            case (state)
                IDLE: if (start_i) begin
                    if (!x_valid_i || wr_any) begin
                        error_q <= 1'b1;
                    end else begin
                        shift_q <= shift_i;
                        busy_o <= 1'b1;
                        start1_q <= 1'b1;
                        state <= L1;
                    end
                end
                L1: if (done1) begin
                    // 1층 점수가 확정된 클록에 재양자화 결과를 은닉 레지스터로 저장
                    for (k = 0; k < 8; k = k + 1)
                        hidden[k] <= q[k];
                    state <= L2_START;
                end
                L2_START: begin
                    start2_q <= 1'b1;
                    state <= L2;
                end
                L2: if (done2) begin
                    class_o <= class2;
                    done_o <= 1'b1;
                    busy_o <= 1'b0;
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                    busy_o <= 1'b0;
                end
            endcase
            if (start_i && state != IDLE)
                error_q <= 1'b1;
        end
    end
endmodule
