`timescale 1ns/1ps
// (추가) 20장: 17장 Tile Controller(784입력·10분류 NPU)를 AXI4-Lite 제어·상태 레지스터로 감싼 Slave.
// 데이터 경로(14장 코어·17장 컨트롤러)는 그대로 두고 버스 어댑터만 추가한다. x 타일은 04장 bram_sync_buffer.
//
// 레지스터(32비트, 오프셋): 0x00 CTRL  0x04 STATUS  0x08 LENGTH  0x0C CLASS  0x10 X_INDEX  0x14 X_DATA
//   0x18 W_CLASS  0x1C W_INDEX  0x20 W_DATA  0x24 BIAS_LO  0x28 BIAS_HI  0x2C SCORE_SEL
//   0x30 SCORE_LO  0x34 SCORE_HI  0x38 IRQ_EN. 0x3C는 미할당(SLVERR).
// 응답 정책: 버스 수준 거부(미할당 주소, 읽기 전용 쓰기, 동작 레지스터 부분 WSTRB, 범위 초과 값,
//   프레임 잠금 중 X_DATA)는 SLVERR이며 아무 효과도 없다. NPU 동작 오류는 STATUS.ERROR·ERR_CODE로 알린다.
// AW와 W는 따로 도착할 수 있다: 각각 1개씩 보관했다가 둘 다 있으면 실행하고 B 응답을 BREADY까지 유지한다.
module p3_npu_axi_lite #(
    parameter integer DATA_W = 8,      // x·W signed 폭 (17장 기본 INT8)
    parameter integer CORE_ACC_W = 24, // 14장 코어 lane 누산 폭
    parameter integer PART_W = 25      // 14장 코어 점수 폭
)(
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
    input wire [5:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot,     // AXI4-Lite 인터페이스 규격용(사용하지 않음)
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [5:0] s_axi_araddr,
    input wire [2:0] s_axi_arprot,     // AXI4-Lite 인터페이스 규격용(사용하지 않음)
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,
    output wire irq_o                  // IRQ_EN[0] && STATUS.DONE (레벨)
);
    localparam integer ACC_W = 41, BIAS_W = 40, SCORE_W = 42, N_IN = 784;
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    localparam [3:0] R_CTRL = 4'h0, R_STATUS = 4'h1, R_LENGTH = 4'h2, R_CLASS = 4'h3,
                     R_XIDX = 4'h4, R_XDATA = 4'h5, R_WCLASS = 4'h6, R_WIDX = 4'h7,
                     R_WDATA = 4'h8, R_BLO = 4'h9, R_BHI = 4'hA, R_SSEL = 4'hB,
                     R_SLO = 4'hC, R_SHI = 4'hD, R_IRQEN = 4'hE;
    // ERR_CODE: 1~6 = 17장 컨트롤러 코드, 아래는 이 어댑터가 검출하는 코드
    localparam [3:0] ERR_NO_FRAME = 4'd4, ERR_LENGTH = 4'd8, ERR_W_MISSING = 4'd9;
    wire clk = s_axi_aclk;
    wire resetn = s_axi_aresetn;

    // ---------------- NPU 데이터 경로 ----------------
    reg start_q, abort_q, go_q;
    reg [3:0] go_id_q;
    reg x_held_q;
    reg x_wr_q, w_wr_q, b_wr_q;
    reg [5:0] x_wr_addr_q;
    reg signed [DATA_W-1:0] x_wr_data_q, w_data_q;
    reg [3:0] wr_class_q;
    reg [5:0] wr_addr_q;
    reg signed [BIAS_W-1:0] b_data_q;
    wire x_rd_en, frame_ack, load_ready, busy, done, error, ovf;
    wire [5:0] x_rd_addr;
    wire signed [DATA_W-1:0] x_rd_data;
    wire [2:0] npu_err_code;
    wire [3:0] tile_idx, npu_class;
    wire [10*SCORE_W-1:0] scores;

    bram_sync_buffer #(.DATA_WIDTH(DATA_W), .ADDR_WIDTH(6)) xbuf(
        .clk(clk), .resetn(resetn), .wr_en(x_wr_q), .rd_en(x_rd_en),
        .wr_addr(x_wr_addr_q), .rd_addr(x_rd_addr), .wr_data(x_wr_data_q),
        .rd_data(x_rd_data), .rd_valid());
    p3_tile784_10 #(.ACC_W(ACC_W), .BIAS_W(BIAS_W), .SCORE_W(SCORE_W), .DATA_W(DATA_W),
                    .CORE_ACC_W(CORE_ACC_W), .PART_W(PART_W)) npu(
        .clk(clk), .resetn(resetn), .start_i(start_q), .abort_i(abort_q),
        .tile_go_i(go_q), .tile_id_i(go_id_q),
        .x_valid_i(x_held_q), .x_rd_en_o(x_rd_en), .x_rd_addr_o(x_rd_addr),
        .x_rd_data_i(x_rd_data), .frame_ack_o(frame_ack),
        .w_wr_en_i(w_wr_q), .b_wr_en_i(b_wr_q), .wr_class_i(wr_class_q), .wr_addr_i(wr_addr_q),
        .w_data_i(w_data_q), .b_data_i(b_data_q), .load_ready_o(load_ready),
        .busy_o(busy), .done_o(done), .error_o(error), .err_code_o(npu_err_code), .ovf_o(ovf),
        .tile_idx_o(tile_idx), .tile_done_o(), .part_scores_o(),
        .class_o(npu_class), .scores_o(scores));

    // ---------------- 레지스터 ----------------
    reg [31:0] length_q, bias_lo_q;
    reg [5:0] x_index_q, w_index_q;
    reg [3:0] w_class_q, score_sel_q, err_code_q;
    reg irq_en_q, done_st_q, err_st_q;
    reg [63:0] x_map_q;            // 현재 타일 x 주소별 쓰기 여부
    reg [9:0] w_cnt_q;             // 현재 타일에서 수락된 W 쓰기 수
    reg [31:0] score_hi_q;         // SCORE_LO 읽기 시점의 상위 비트(스냅샷)
    assign irq_o = irq_en_q && done_st_q;
    wire in_load = busy && load_ready;
    wire [9:0] w_need = (tile_idx == 4'd12) ? 10'd160 : 10'd640;

    // 쓰기 채널: AW·W 각각 1개 보관
    reg aw_q, w_q;
    reg [3:0] aw_idx_q;
    reg [31:0] wd_q;
    reg [3:0] ws_q;
    assign s_axi_awready = resetn && !aw_q && !s_axi_bvalid;
    assign s_axi_wready = resetn && !w_q && !s_axi_bvalid;
    wire wr_exec = aw_q && w_q && !s_axi_bvalid;

    function [31:0] merge(input [31:0] old, input [31:0] nv, input [3:0] strb);
        integer i;
        begin
            for (i = 0; i < 4; i = i + 1)
                merge[8*i +: 8] = strb[i] ? nv[8*i +: 8] : old[8*i +: 8];
        end
    endfunction
    // 32비트 값이 signed n비트 범위인가(상위 비트가 모두 부호와 같음)
    function fits_signed(input [31:0] v, input integer n);
        integer i;
        begin
            fits_signed = 1'b1;
            for (i = 0; i < 32; i = i + 1)
                if (i >= n - 1 && v[i] != v[n-1]) fits_signed = 1'b0;
        end
    endfunction

    wire full_strb = (ws_q == 4'hF);
    // 설정 레지스터는 WSTRB 바이트만 바꾼 값으로 범위를 검사하고 저장한다
    wire [31:0] xidx_m = merge({26'd0, x_index_q}, wd_q, ws_q);
    wire [31:0] wcls_m = merge({28'd0, w_class_q}, wd_q, ws_q);
    wire [31:0] widx_m = merge({26'd0, w_index_q}, wd_q, ws_q);
    wire [31:0] ssel_m = merge({28'd0, score_sel_q}, wd_q, ws_q);
    wire [31:0] irq_m = merge({31'd0, irq_en_q}, wd_q, ws_q);
    wire [2:0] cmd = wd_q[2:0];                  // CTRL bit0 START, bit1 TILE_GO, bit2 ABORT
    wire cmd_one = (cmd == 3'b001) || (cmd == 3'b010) || (cmd == 3'b100);
    // 실행할 쓰기의 SLVERR 여부
    reg wr_bad;
    always @* begin
        case (aw_idx_q)
            R_CTRL: wr_bad = !full_strb || !cmd_one;
            R_STATUS, R_LENGTH, R_BLO: wr_bad = 1'b0;
            R_IRQEN: wr_bad = irq_m > 32'd1;
            R_XIDX: wr_bad = xidx_m > 32'd63;
            R_XDATA: wr_bad = !full_strb || x_held_q || !fits_signed(wd_q, DATA_W);
            R_WCLASS: wr_bad = wcls_m > 32'd9;
            R_WIDX: wr_bad = widx_m > 32'd63;
            R_WDATA: wr_bad = !full_strb || !fits_signed(wd_q, DATA_W);
            R_BHI: wr_bad = !full_strb || !fits_signed(wd_q, BIAS_W - 32);
            R_SSEL: wr_bad = ssel_m > 32'd9;
            default: wr_bad = 1'b1;   // CLASS·SCORE_LO·SCORE_HI 읽기 전용, 0x3C 미할당
        endcase
    end

    // 읽기 채널
    assign s_axi_arready = resetn && !s_axi_rvalid;
    wire rd_acc = s_axi_arvalid && s_axi_arready;
    wire [3:0] ar_idx = s_axi_araddr[5:2];
    wire [SCORE_W-1:0] sel_score = scores[score_sel_q*SCORE_W +: SCORE_W];
    wire [31:0] status = {16'd0, err_code_q, tile_idx, 2'd0, x_held_q, load_ready,
                          ovf, err_st_q, done_st_q, busy};

    always @(posedge clk) begin
        if (!resetn) begin
            aw_q <= 1'b0; w_q <= 1'b0; aw_idx_q <= 4'd0; wd_q <= 32'd0; ws_q <= 4'd0;
            s_axi_bvalid <= 1'b0; s_axi_bresp <= OKAY;
            s_axi_rvalid <= 1'b0; s_axi_rresp <= OKAY; s_axi_rdata <= 32'd0;
            start_q <= 1'b0; abort_q <= 1'b0; go_q <= 1'b0; go_id_q <= 4'd0;
            x_held_q <= 1'b0; x_wr_q <= 1'b0; w_wr_q <= 1'b0; b_wr_q <= 1'b0;
            x_wr_addr_q <= 6'd0; x_wr_data_q <= {DATA_W{1'b0}}; w_data_q <= {DATA_W{1'b0}};
            wr_class_q <= 4'd0; wr_addr_q <= 6'd0; b_data_q <= {BIAS_W{1'b0}};
            length_q <= N_IN; bias_lo_q <= 32'd0; x_index_q <= 6'd0; w_index_q <= 6'd0;
            w_class_q <= 4'd0; score_sel_q <= 4'd0; err_code_q <= 4'd0;
            irq_en_q <= 1'b0; done_st_q <= 1'b0; err_st_q <= 1'b0;
            x_map_q <= 64'd0; w_cnt_q <= 10'd0; score_hi_q <= 32'd0;
        end else begin
            start_q <= 1'b0; abort_q <= 1'b0; go_q <= 1'b0;
            x_wr_q <= 1'b0; w_wr_q <= 1'b0; b_wr_q <= 1'b0;
            if (s_axi_awvalid && s_axi_awready) begin
                aw_q <= 1'b1;
                aw_idx_q <= s_axi_awaddr[5:2];
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_q <= 1'b1;
                wd_q <= s_axi_wdata;
                ws_q <= s_axi_wstrb;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            // NPU 상태 반영(쓰기 실행보다 먼저: 같은 클록의 W1C·START가 우선)
            if (done)
                done_st_q <= 1'b1;
            if (error) begin
                err_st_q <= 1'b1;
                err_code_q <= {1'b0, npu_err_code};
            end
            if (frame_ack) begin
                x_held_q <= 1'b0;
                x_map_q <= 64'd0;
                w_cnt_q <= 10'd0;
            end
            if (w_wr_q && load_ready && w_cnt_q != 10'h3FF)
                w_cnt_q <= w_cnt_q + 10'd1;

            if (wr_exec) begin
                aw_q <= 1'b0;
                w_q <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= wr_bad ? SLVERR : OKAY;
                if (!wr_bad) case (aw_idx_q)
                    R_CTRL: begin
                        if (cmd[0]) begin
                            if (length_q != N_IN) begin
                                err_st_q <= 1'b1;
                                err_code_q <= ERR_LENGTH;
                            end else begin
                                start_q <= 1'b1;
                                if (!busy) done_st_q <= 1'b0;
                            end
                        end
                        if (cmd[2])
                            abort_q <= 1'b1;
                        if (cmd[1]) begin
                            go_id_q <= wd_q[11:8];
                            if (!in_load || x_held_q) begin
                                go_q <= 1'b1;          // 상태 판정은 컨트롤러가 한다
                            end else if (x_map_q != {64{1'b1}}) begin
                                err_st_q <= 1'b1;
                                err_code_q <= ERR_NO_FRAME;
                            end else if (w_cnt_q < w_need) begin
                                err_st_q <= 1'b1;
                                err_code_q <= ERR_W_MISSING;
                            end else begin
                                x_held_q <= 1'b1;      // 결과 수락(frame_ack)까지 X_DATA 잠금
                                go_q <= 1'b1;
                            end
                        end
                    end
                    R_STATUS: begin                   // W1C: bit1 DONE, bit2 ERROR
                        if (ws_q[0] && wd_q[1]) done_st_q <= 1'b0;
                        if (ws_q[0] && wd_q[2]) err_st_q <= 1'b0;
                    end
                    R_LENGTH: length_q <= merge(length_q, wd_q, ws_q);
                    R_XIDX: x_index_q <= xidx_m[5:0];
                    R_XDATA: begin
                        x_wr_q <= 1'b1;
                        x_wr_addr_q <= x_index_q;
                        x_wr_data_q <= wd_q[DATA_W-1:0];
                        x_map_q[x_index_q] <= 1'b1;
                        x_index_q <= x_index_q + 6'd1;
                    end
                    R_WCLASS: w_class_q <= wcls_m[3:0];
                    R_WIDX: w_index_q <= widx_m[5:0];
                    R_WDATA: begin
                        w_wr_q <= 1'b1;
                        wr_class_q <= w_class_q;
                        wr_addr_q <= w_index_q;
                        w_data_q <= wd_q[DATA_W-1:0];
                        w_index_q <= w_index_q + 6'd1;
                    end
                    R_BLO: bias_lo_q <= merge(bias_lo_q, wd_q, ws_q);
                    R_BHI: begin                      // BIAS_LO와 합쳐 W_CLASS의 Bias로 확정
                        b_wr_q <= 1'b1;
                        wr_class_q <= w_class_q;
                        b_data_q <= {wd_q[BIAS_W-33:0], bias_lo_q};
                    end
                    R_SSEL: score_sel_q <= ssel_m[3:0];
                    R_IRQEN: irq_en_q <= irq_m[0];
                    default: ;
                endcase
            end

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
            if (rd_acc) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= (ar_idx == 4'hF) ? SLVERR : OKAY;
                case (ar_idx)
                    R_STATUS: s_axi_rdata <= status;
                    R_LENGTH: s_axi_rdata <= length_q;
                    R_CLASS: s_axi_rdata <= {28'd0, npu_class};
                    R_XIDX: s_axi_rdata <= {26'd0, x_index_q};
                    R_WCLASS: s_axi_rdata <= {28'd0, w_class_q};
                    R_WIDX: s_axi_rdata <= {26'd0, w_index_q};
                    R_BLO: s_axi_rdata <= bias_lo_q;
                    R_SSEL: s_axi_rdata <= {28'd0, score_sel_q};
                    R_SLO: begin                      // 하위 32비트와 상위 비트를 같은 순간에 잡는다
                        s_axi_rdata <= sel_score[31:0];
                        score_hi_q <= {{(64-SCORE_W){sel_score[SCORE_W-1]}}, sel_score[SCORE_W-1:32]};
                    end
                    R_SHI: s_axi_rdata <= score_hi_q;
                    R_IRQEN: s_axi_rdata <= {31'd0, irq_en_q};
                    default: s_axi_rdata <= 32'd0;    // CTRL·X_DATA·W_DATA·BIAS_HI는 쓰기 전용, 0x3C 미할당
                endcase
            end
        end
    end
    // synthesis translate_off
    initial begin
        if (DATA_W < 2 || DATA_W > 16)
            $fatal(1, "Require 2 <= DATA_W <= 16");
    end
    // synthesis translate_on
endmodule
