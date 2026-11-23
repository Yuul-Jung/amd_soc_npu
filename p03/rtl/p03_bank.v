// 3장 8×8 MNIST 묶음: 서브젝트 모듈을 STAGE만큼 쌓는다.
//   3-1 (STAGE>=1) p3_frame64_buffer: 64원소 INT8 프레임
//   3-2 (STAGE>=2) p3_group10_core 64→10: 4PE 3그룹, 점수·argmax        → 층 0
//   3-3 (STAGE>=3) p3_group10_core #(64,8)·#(8,10): 같은 코어를 모양만 바꿔 → 층 1·2
//   3-4 (STAGE>=4) p3_mlp_64_8_10: 1층 → ReLU·재양자화 → 2층             → 층 1·2를 함께 받음
// 프레임 버퍼 읽기 포트 하나를 콘솔(화소 읽기)과 코어들이 나눠 쓴다. 한 번에 하나만 돈다.
`timescale 1ns/1ps
`default_nettype none
module p03_bank #(
    parameter integer STAGE = 4
) (
    input  wire               clk,
    input  wire               resetn,
    // 프레임 스트림 (콘솔)
    input  wire [7:0]         s_data_i,
    input  wire               s_valid_i,
    input  wire               s_last_i,
    output wire               s_ready_o,
    output wire               frame_valid_o,
    input  wire               frame_ack_i,
    output wire               err_short_o,
    output wire               err_long_o,
    // 화소 읽기 (콘솔)
    input  wire               px_rd_i,
    input  wire [5:0]         px_addr_i,
    output wire signed [7:0]  px_data_o,
    output wire               px_valid_o,
    // 가중치·Bias 쓰기. layer 0 = 64→10, 1 = 64→8 (MLP 1층), 2 = 8→10 (MLP 2층)
    input  wire               w_wr_i,
    input  wire               b_wr_i,
    input  wire [1:0]         layer_i,
    input  wire [3:0]         class_i,
    input  wire [5:0]         addr_i,
    input  wire signed [7:0]  w_i,
    input  wire signed [23:0] b_i,
    input  wire [4:0]         shift_i,
    // 실행. sel 0 = 64→10, 1 = 64→8, 2 = 8→10, 3 = MLP
    input  wire [1:0]         run_sel_i,
    input  wire               run_i,
    output reg                run_done_o,
    output reg                run_err_o,
    output reg  [3:0]         class_o,
    output reg  [249:0]       scores_o,
    output reg  [63:0]        hidden_o
);
    // ---------------- 3-1: 프레임 버퍼 ----------------
    wire               rd_en, rd_valid;
    wire [5:0]         rd_addr;
    wire signed [7:0]  rd_data;
    p3_frame64_buffer u_frame (
        .clk(clk), .resetn(resetn), .s_data_i(s_data_i), .s_valid_i(s_valid_i), .s_last_i(s_last_i),
        .s_ready_o(s_ready_o), .frame_valid_o(frame_valid_o), .frame_ack_i(frame_ack_i),
        .rd_en_i(rd_en), .rd_addr_i(rd_addr), .rd_data_o(rd_data), .rd_valid_o(rd_valid),
        .err_short_o(err_short_o), .err_long_o(err_long_o));
    assign px_data_o  = rd_data;
    assign px_valid_o = rd_valid;

    // 코어 출력 묶음: [0] 64→10, [1] 64→8, [2] 8→10, [3] MLP
    wire [3:0]   c_rd, c_done, c_err;
    wire [5:0]   c_addr [0:3];
    wire [3:0]   c_cls  [0:3];
    wire [249:0] c_sc   [0:3];
    wire [63:0]  mlp_hidden;
    wire [3:0]   start = {4{run_i}} & (4'b0001 << run_sel_i);

    assign rd_en   = px_rd_i | (|c_rd);
    assign rd_addr = px_rd_i ? px_addr_i : c_rd[0] ? c_addr[0] : c_rd[1] ? c_addr[1] : c_rd[2] ? c_addr[2] : c_addr[3];

    // ---------------- 3-2: 64→10 코어 ----------------
    generate if (STAGE >= 2) begin : g_c10
        p3_group10_core #(.IN_LEN(64), .OUT_N(10)) u_c10 (
            .clk(clk), .resetn(resetn), .start_i(start[0]), .x_valid_i(frame_valid_o),
            .x_rd_en_o(c_rd[0]), .x_rd_addr_o(c_addr[0]), .x_rd_data_i(rd_data),
            .w_wr_en_i(w_wr_i && layer_i == 2'd0), .b_wr_en_i(b_wr_i && layer_i == 2'd0),
            .wr_class_i(class_i), .wr_addr_i(addr_i), .w_data_i(w_i), .b_data_i(b_i),
            .load_ready_o(), .busy_o(), .done_o(c_done[0]), .error_o(c_err[0]), .class_o(c_cls[0]),
            .scores_o(c_sc[0]));
    end else begin : g_no_c10
        assign c_rd[0] = 1'b0; assign c_addr[0] = 6'd0; assign c_done[0] = 1'b0; assign c_err[0] = 1'b0;
        assign c_cls[0] = 4'd0; assign c_sc[0] = 250'd0;
    end endgenerate

    // ---------------- 3-3: 64→8·8→10 (같은 코어, 파라미터만) ----------------
    generate if (STAGE >= 3) begin : g_shapes
        wire [199:0] sc8;
        p3_group10_core #(.IN_LEN(64), .OUT_N(8)) u_h8 (
            .clk(clk), .resetn(resetn), .start_i(start[1]), .x_valid_i(frame_valid_o),
            .x_rd_en_o(c_rd[1]), .x_rd_addr_o(c_addr[1]), .x_rd_data_i(rd_data),
            .w_wr_en_i(w_wr_i && layer_i == 2'd1), .b_wr_en_i(b_wr_i && layer_i == 2'd1),
            .wr_class_i(class_i), .wr_addr_i(addr_i), .w_data_i(w_i), .b_data_i(b_i),
            .load_ready_o(), .busy_o(), .done_o(c_done[1]), .error_o(c_err[1]), .class_o(c_cls[1]),
            .scores_o(sc8));
        assign c_sc[1] = {50'd0, sc8};
        p3_group10_core #(.IN_LEN(8), .OUT_N(10)) u_o10 (
            .clk(clk), .resetn(resetn), .start_i(start[2]), .x_valid_i(frame_valid_o),
            .x_rd_en_o(c_rd[2]), .x_rd_addr_o(c_addr[2]), .x_rd_data_i(rd_data),
            .w_wr_en_i(w_wr_i && layer_i == 2'd2), .b_wr_en_i(b_wr_i && layer_i == 2'd2),
            .wr_class_i(class_i), .wr_addr_i(addr_i), .w_data_i(w_i), .b_data_i(b_i),
            .load_ready_o(), .busy_o(), .done_o(c_done[2]), .error_o(c_err[2]), .class_o(c_cls[2]),
            .scores_o(c_sc[2]));
    end else begin : g_no_shapes
        assign c_rd[2:1] = 2'd0; assign c_addr[1] = 6'd0; assign c_addr[2] = 6'd0;
        assign c_done[2:1] = 2'd0; assign c_err[2:1] = 2'd0;
        assign c_cls[1] = 4'd0; assign c_cls[2] = 4'd0; assign c_sc[1] = 250'd0; assign c_sc[2] = 250'd0;
    end endgenerate

    // ---------------- 3-4: MLP 64→8→10 ----------------
    generate if (STAGE >= 4) begin : g_mlp
        p3_mlp_64_8_10 u_mlp (
            .clk(clk), .resetn(resetn), .start_i(start[3]), .shift_i(shift_i), .x_valid_i(frame_valid_o),
            .x_rd_en_o(c_rd[3]), .x_rd_addr_o(c_addr[3]), .x_rd_data_i(rd_data),
            .wr_layer_i(layer_i == 2'd2), .w_wr_en_i(w_wr_i && layer_i != 2'd0),
            .b_wr_en_i(b_wr_i && layer_i != 2'd0), .wr_class_i(class_i), .wr_addr_i(addr_i),
            .w_data_i(w_i), .b_data_i(b_i), .load_ready_o(), .busy_o(), .done_o(c_done[3]),
            .error_o(c_err[3]), .class_o(c_cls[3]), .scores_o(c_sc[3]), .hidden_o(mlp_hidden));
    end else begin : g_no_mlp
        assign c_rd[3] = 1'b0; assign c_addr[3] = 6'd0; assign c_done[3] = 1'b0; assign c_err[3] = 1'b0;
        assign c_cls[3] = 4'd0; assign c_sc[3] = 250'd0; assign mlp_hidden = 64'd0;
    end endgenerate

    // ---------------- 실행 결과 ----------------
    reg       running;
    reg [1:0] sel_q;
    wire      avail = (run_sel_i == 2'd0 && STAGE >= 2) || ((run_sel_i == 2'd1 || run_sel_i == 2'd2) && STAGE >= 3) ||
                      (run_sel_i == 2'd3 && STAGE >= 4);
    always @(posedge clk) begin
        if (!resetn) begin
            running <= 1'b0; sel_q <= 2'd0; run_done_o <= 1'b0; run_err_o <= 1'b0;
            class_o <= 4'd0; scores_o <= 250'd0; hidden_o <= 64'd0;
        end else begin
            run_done_o <= 1'b0; run_err_o <= 1'b0;
            if (run_i) begin
                sel_q <= run_sel_i;
                if (!avail) begin                  // 이 STAGE에 아직 없는 코어
                    run_err_o <= 1'b1; run_done_o <= 1'b1;
                end else begin
                    running <= 1'b1;
                end
            end else if (running && (c_done[sel_q] || c_err[sel_q])) begin
                running <= 1'b0;
                run_done_o <= 1'b1;
                run_err_o  <= c_err[sel_q];
                class_o    <= c_cls[sel_q];
                scores_o   <= c_sc[sel_q];
                hidden_o   <= mlp_hidden;
            end
        end
    end
endmodule
`default_nettype wire
