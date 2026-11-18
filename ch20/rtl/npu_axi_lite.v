`timescale 1ns/1ps
`default_nettype none
// 20장 AXI4-Lite 슬레이브: 19장 연산 코어(NPE=4)를 CPU가 레지스터로 다루게 한다.
// 쓰기 주소(AW)와 쓰기 데이터(W)는 순서와 관계없이 따로 받아 두고, 둘이 모이면 한 번 쓰고 B 응답을 낸다.
// 읽기(AR)는 다음 클록에 R 응답. B·R은 READY가 올 때까지 VALID·데이터를 유지한다 (역압력).
//
// 레지스터 (바이트 주소, 32비트)
//   0x00 CTRL    W  bit0 START(1 쓰면 시작), bit1 CLR(DONE·ERROR 지움)
//   0x04 STATUS  R  bit0 BUSY, bit1 DONE(유지), bit2 ERROR(유지)
//   0x08 CLASS   R  [3:0] 결과 클래스
//   0x0C CYCLES  R  [15:0] 마지막 추론 클록 수
//   0x10 X_ADDR  RW [9:0] 다음 입력 주소 (X_DATA 쓰기마다 +1)
//   0x14 X_DATA  W  [7:0] 입력 값 → x[X_ADDR]
//   0x18 W_ADDR  RW [19:16] 클래스, [9:0] 원소 주소 (W_DATA 쓰기마다 원소 +1)
//   0x1C W_DATA  W  [7:0] 가중치 → w[클래스][원소]
//   0x20 B_SEL   RW [3:0] Bias 클래스 (B_DATA 쓰기마다 +1)
//   0x24 B_DATA  W  [31:0] Bias → b[B_SEL]
//   0x28 ID      R  0x4E505531 ("NPU1")
//   0x2C LENGTH  R  784 (입력 원소 수)
//   0x40~0x64 SCORE0~9 R 점수 (signed 32비트)
// WSTRB: 바이트 단위로 적용. X_DATA·W_DATA는 바이트 0(WSTRB[0])이 켜져 있을 때만 쓴다.
module npu_axi_lite #(
    parameter integer ADDR_WIDTH = 8
) (
    input  wire                  s_axi_aclk,
    input  wire                  s_axi_aresetn,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire           [31:0] s_axi_wdata,
    input  wire            [3:0] s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire            [1:0] s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output reg            [31:0] s_axi_rdata,
    output wire            [1:0] s_axi_rresp,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,
    output wire                  irq_o                    // DONE 또는 ERROR (레벨)
);
    wire clk = s_axi_aclk, rn = s_axi_aresetn;
    assign s_axi_bresp = 2'b00;                           // 항상 OKAY
    assign s_axi_rresp = 2'b00;

    // ── 쓰기: AW·W를 따로 받아 둔다 (한 번에 하나씩)
    reg aw_full, w_full;
    reg [ADDR_WIDTH-1:0] aw_q;
    reg [31:0] wd_q; reg [3:0] ws_q;
    assign s_axi_awready = !aw_full && !s_axi_bvalid;
    assign s_axi_wready  = !w_full && !s_axi_bvalid;
    wire do_write = aw_full && w_full && !s_axi_bvalid;

    // ── 읽기: 다음 클록에 응답, RREADY까지 유지
    assign s_axi_arready = !s_axi_rvalid;

    // ── 레지스터
    reg [9:0] x_addr; reg [3:0] w_cls; reg [9:0] w_addr; reg [3:0] b_sel;
    reg done_st, err_st;
    reg start_p, x_we, w_we, b_we;
    reg [7:0] x_d, w_d; reg [31:0] b_d; reg [9:0] x_a, w_a; reg [3:0] w_n, b_n;

    wire busy, done, error; wire [3:0] cls; wire [319:0] scores; wire [15:0] cycles;
    npu_tiled_784_npe #(.NPE(4), .ACC_WIDTH(32)) core (
        .clk(clk), .resetn(rn), .x_wr_en_i(x_we), .x_addr_i(x_a), .x_data_i(x_d),
        .w_wr_en_i(w_we), .w_neuron_i(w_n), .w_addr_i(w_a), .w_data_i(w_d),
        .b_wr_en_i(b_we), .b_neuron_i(b_n), .b_data_i(b_d), .start_i(start_p), .busy_o(busy),
        .scores_o(scores), .done_o(done), .error_o(error), .class_o(cls), .cycles_o(cycles));
    assign irq_o = done_st | err_st;

    // 바이트 단위 WSTRB 적용
    function [31:0] merge(input [31:0] old, input [31:0] nw, input [3:0] st);
        integer k;
        begin
            for (k = 0; k < 4; k = k + 1) merge[k*8 +: 8] = st[k] ? nw[k*8 +: 8] : old[k*8 +: 8];
        end
    endfunction
    wire [5:0] wreg = aw_q[7:2];
    wire [31:0] x_addr_m = merge({22'd0, x_addr}, wd_q, ws_q);
    wire [31:0] w_addr_m = merge({12'd0, w_cls, 6'd0, w_addr}, wd_q, ws_q);
    wire [31:0] b_sel_m  = merge({28'd0, b_sel}, wd_q, ws_q);

    always @(posedge clk) begin
        if (!rn) begin
            aw_full <= 0; w_full <= 0; s_axi_bvalid <= 0; aw_q <= 0; wd_q <= 0; ws_q <= 0;
            x_addr <= 0; w_cls <= 0; w_addr <= 0; b_sel <= 0; done_st <= 0; err_st <= 0;
            start_p <= 0; x_we <= 0; w_we <= 0; b_we <= 0;
            x_d <= 0; w_d <= 0; b_d <= 0; x_a <= 0; w_a <= 0; w_n <= 0; b_n <= 0;
        end else begin
            start_p <= 0; x_we <= 0; w_we <= 0; b_we <= 0;
            if (s_axi_awvalid && s_axi_awready) begin aw_q <= s_axi_awaddr; aw_full <= 1; end
            if (s_axi_wvalid && s_axi_wready) begin wd_q <= s_axi_wdata; ws_q <= s_axi_wstrb; w_full <= 1; end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (done) done_st <= 1;
            if (error) err_st <= 1;
            if (do_write) begin
                aw_full <= 0; w_full <= 0; s_axi_bvalid <= 1;
                case (wreg)
                    6'h00: begin
                        if (ws_q[0] && wd_q[0] && !busy) begin start_p <= 1; done_st <= 0; err_st <= 0; end
                        if (ws_q[0] && wd_q[1]) begin done_st <= 0; err_st <= 0; end
                    end
                    6'h04: x_addr <= x_addr_m[9:0];
                    6'h05: if (ws_q[0]) begin x_we <= 1; x_a <= x_addr; x_d <= wd_q[7:0]; x_addr <= x_addr + 10'd1; end
                    6'h06: begin w_cls <= w_addr_m[19:16]; w_addr <= w_addr_m[9:0]; end
                    6'h07: if (ws_q[0]) begin w_we <= 1; w_n <= w_cls; w_a <= w_addr; w_d <= wd_q[7:0]; w_addr <= w_addr + 10'd1; end
                    6'h08: b_sel <= b_sel_m[3:0];
                    6'h09: begin b_we <= 1; b_n <= b_sel; b_d <= merge(32'd0, wd_q, ws_q); b_sel <= b_sel + 4'd1; end
                    default: ;                                // 읽기 전용·없는 주소: 무시 (OKAY)
                endcase
            end
        end
    end

    // 읽기 응답
    wire [5:0] rreg = s_axi_araddr[7:2];
    reg [31:0] rmux;
    always @(*) begin
        case (rreg)
            6'h01: rmux = {29'd0, err_st, done_st, busy};
            6'h02: rmux = {28'd0, cls};
            6'h03: rmux = {16'd0, cycles};
            6'h04: rmux = {22'd0, x_addr};
            6'h06: rmux = {12'd0, w_cls, 6'd0, w_addr};
            6'h08: rmux = {28'd0, b_sel};
            6'h0A: rmux = 32'h4E505531;
            6'h0B: rmux = 32'd784;
            default: rmux = (rreg >= 6'h10 && rreg <= 6'h19) ? scores[(rreg - 6'h10)*32 +: 32] : 32'd0;
        endcase
    end
    always @(posedge clk) begin
        if (!rn) begin s_axi_rvalid <= 0; s_axi_rdata <= 0; end
        else begin
            if (s_axi_arvalid && s_axi_arready) begin s_axi_rvalid <= 1; s_axi_rdata <= rmux; end
            else if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
        end
    end
endmodule
`default_nettype wire
