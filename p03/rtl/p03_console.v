// 3장 디버그 콘솔: 8×8 MNIST 서브젝트를 UART 명령으로 확인한다. 1·2장과 같은 형식 (1바이트 명령 + 바이너리).
//
//   명령 페이로드                      응답                                         서브젝트 (STAGE)
//   S    없음                          "I"                                          모두
//   F    n (1~80) + 화소 n바이트        "F:OK" / "F:SHORT" (n<64) / "F:LONG" (n>64)   3-1 (1)  n번째 바이트에 last
//   p    addr                          "P:" 2자리 (프레임 없으면 "ERR")              3-1 (1)
//   W    층 class addr v(int8)          "OK"                                         3-2 (2)  층 0 = 64→10, 1 = 64→8, 2 = 8→10
//   B    층 class b2 b1 b0 (int24)      "OK"                                         3-2 (2)
//   R    없음                          "R" 클래스 ":" 점수 7자리 ×10                3-2 (2)  64→10
//   H    없음                          "H" 클래스 ":" 점수 7자리 ×8                 3-3 (3)  64→8
//   G    없음                          "G" 클래스 ":" 점수 7자리 ×10                3-3 (3)  8→10 (프레임 앞 8원소)
//   Z    shift (0~31)                  "OK"                                         3-4 (4)
//   M    없음                          "M" 클래스 ":" 은닉 2자리 ×8 " " 점수 ×10     3-4 (4)  MLP
//   그 밖 (CR·LF 제외) "?",  범위 밖 "ERR",  코어 오류(프레임 없음 등) "ERR". 끝은 모두 \r\n
// 층 1은 3-3 64→8 코어와 3-4 MLP 1층에, 층 2는 3-3 8→10 코어와 MLP 2층에 함께 쓴다.
`timescale 1ns/1ps
`default_nettype none
module p03_console #(
    parameter integer STAGE = 4
) (
    input  wire               clk,
    input  wire               resetn,
    input  wire [7:0]         rx_data_i,
    input  wire               rx_valid_i,
    output wire               rx_ready_o,
    output reg  [7:0]         tx_data_o,
    output reg                tx_valid_o,
    input  wire               tx_ready_i,
    // 묶음으로
    output wire [7:0]         s_data_o,
    output wire               s_valid_o,
    output wire               s_last_o,
    input  wire               s_ready_i,
    input  wire               frame_valid_i,
    output reg                frame_ack_o,
    input  wire               err_short_i,
    input  wire               err_long_i,
    output reg                px_rd_o,
    output reg  [5:0]         px_addr_o,
    input  wire signed [7:0]  px_data_i,
    input  wire               px_valid_i,
    output reg                w_wr_o,
    output reg                b_wr_o,
    output reg  [1:0]         layer_o,
    output reg  [3:0]         class_o,
    output reg  [5:0]         addr_o,
    output reg  signed [7:0]  w_o,
    output reg  signed [23:0] b_o,
    output reg  [4:0]         shift_o,
    output reg  [1:0]         run_sel_o,
    output reg                run_o,
    input  wire               run_done_i,
    input  wire               run_err_i,
    input  wire [3:0]         run_class_i,
    input  wire [249:0]       run_scores_i,
    input  wire [63:0]        run_hidden_i,
    // 표시
    output reg  [15:0]        view_o,
    output reg  [3:0]         cls_o,
    output reg                cls_ok_o,
    output reg                fshort_o,
    output reg                flong_o
);
    localparam [3:0] S_IDLE = 4'd0, S_RECV = 4'd1, S_ISSUE = 4'd2, S_ACK = 4'd3, S_STREAM = 4'd4,
                     S_FWAIT = 4'd5, S_PX = 4'd6, S_RUN = 4'd7, S_LOAD = 4'd8, S_SEND = 4'd9;
    localparam integer MSG_MAX = 104;

    reg [3:0] state;
    reg [7:0] opc;
    reg [7:0] pl [0:4];
    reg [2:0] need, got;
    reg [6:0] n_left;
    reg       e_short, e_long;
    reg [1:0] fw;
    reg [7:0] msg [0:MSG_MAX-1];
    reg [6:0] msg_len, idx;
    integer   k, p;

    function [7:0] hex(input [3:0] n);
        hex = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
    endfunction

    function [2:0] plen(input [7:0] c);
        case (c)
            "S":     plen = 3'd0;
            "F":     plen = 3'd1;
            "p":     plen = 3'd1;
            "W":     plen = (STAGE >= 2) ? 3'd4 : 3'd7;
            "B":     plen = (STAGE >= 2) ? 3'd5 : 3'd7;
            "R":     plen = (STAGE >= 2) ? 3'd0 : 3'd7;
            "H":     plen = (STAGE >= 3) ? 3'd0 : 3'd7;
            "G":     plen = (STAGE >= 3) ? 3'd0 : 3'd7;
            "Z":     plen = (STAGE >= 4) ? 3'd1 : 3'd7;
            "M":     plen = (STAGE >= 4) ? 3'd0 : 3'd7;
            default: plen = 3'd7;
        endcase
    endfunction

    // 층별 범위: 층 0 class<10·addr<64, 층 1 class<8·addr<64, 층 2 class<10·addr<8. 3-2 빌드에는 층 0만
    wire [7:0] lay = pl[0], cl = pl[1], ad = pl[2];
    wire layer_ok = (lay == 8'd0) || (lay <= 8'd2 && STAGE >= 3);
    wire wb_ok = layer_ok && (lay == 8'd1 ? cl < 8'd8 : cl < 8'd10);
    wire fields_ok =
        (opc == "F") ? (pl[0] >= 8'd1 && pl[0] <= 8'd80) :
        (opc == "p") ? (pl[0] < 8'd64) :
        (opc == "W") ? (wb_ok && (lay == 8'd2 ? ad < 8'd8 : ad < 8'd64)) :
        (opc == "B") ? wb_ok :
        (opc == "Z") ? (pl[0] < 8'd32) : 1'b1;

    // 프레임 바이트는 UART에서 묶음으로 바로 흘린다 (묶음의 ready로 흐름 제어)
    assign s_data_o   = rx_data_i;
    assign s_valid_o  = (state == S_STREAM) && rx_valid_i;
    assign s_last_o   = (n_left == 7'd1);
    assign rx_ready_o = (state == S_IDLE) || (state == S_RECV) || (state == S_STREAM && s_ready_i);
    wire   rx_take    = rx_valid_i && rx_ready_o;

    task put_err;
        begin
            msg[0] <= "E"; msg[1] <= "R"; msg[2] <= "R"; msg[3] <= 8'h0D; msg[4] <= 8'h0A; msg_len <= 7'd5;
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE; opc <= 8'd0; need <= 3'd0; got <= 3'd0; n_left <= 7'd0;
            e_short <= 1'b0; e_long <= 1'b0; fw <= 2'd0; msg_len <= 7'd0; idx <= 7'd0;
            tx_data_o <= 8'd0; tx_valid_o <= 1'b0; frame_ack_o <= 1'b0; px_rd_o <= 1'b0; px_addr_o <= 6'd0;
            w_wr_o <= 1'b0; b_wr_o <= 1'b0; layer_o <= 2'd0; class_o <= 4'd0; addr_o <= 6'd0;
            w_o <= 8'sd0; b_o <= 24'sd0; shift_o <= 5'd0; run_sel_o <= 2'd0; run_o <= 1'b0;
            view_o <= 16'd0; cls_o <= 4'd0; cls_ok_o <= 1'b0; fshort_o <= 1'b0; flong_o <= 1'b0;
        end else begin
            frame_ack_o <= 1'b0; px_rd_o <= 1'b0; w_wr_o <= 1'b0; b_wr_o <= 1'b0; run_o <= 1'b0;
            case (state)
                S_IDLE: if (rx_take && rx_data_i != 8'h0D && rx_data_i != 8'h0A) begin
                    opc <= rx_data_i; got <= 3'd0; need <= plen(rx_data_i);
                    if (plen(rx_data_i) == 3'd7) begin
                        msg[0] <= "?"; msg[1] <= 8'h0D; msg[2] <= 8'h0A; msg_len <= 7'd3; state <= S_LOAD;
                    end else if (plen(rx_data_i) == 3'd0) begin
                        state <= S_ISSUE;
                    end else begin
                        state <= S_RECV;
                    end
                end
                S_RECV: if (rx_take) begin
                    pl[got] <= rx_data_i;
                    if (got + 3'd1 == need) state <= S_ISSUE;
                    else got <= got + 3'd1;
                end
                S_ISSUE: begin
                    if (!fields_ok) begin
                        put_err; state <= S_LOAD;
                    end else case (opc)
                        "S": begin msg[0] <= "I"; msg[1] <= 8'h0D; msg[2] <= 8'h0A; msg_len <= 7'd3; state <= S_LOAD; end
                        "F": begin                // 들고 있는 프레임은 먼저 놓는다
                            n_left <= pl[0][6:0]; e_short <= 1'b0; e_long <= 1'b0;
                            frame_ack_o <= frame_valid_i; state <= S_ACK;
                        end
                        "p": begin
                            if (!frame_valid_i) begin put_err; state <= S_LOAD; end
                            else begin px_rd_o <= 1'b1; px_addr_o <= pl[0][5:0]; state <= S_PX; end
                        end
                        "W", "B": begin
                            layer_o <= pl[0][1:0]; class_o <= pl[1][3:0];
                            if (opc == "W") begin addr_o <= pl[2][5:0]; w_o <= pl[3]; w_wr_o <= 1'b1; end
                            else begin b_o <= {pl[2], pl[3], pl[4]}; b_wr_o <= 1'b1; end
                            msg[0] <= "O"; msg[1] <= "K"; msg[2] <= 8'h0D; msg[3] <= 8'h0A; msg_len <= 7'd4; state <= S_LOAD;
                        end
                        "Z": begin
                            shift_o <= pl[0][4:0];
                            msg[0] <= "O"; msg[1] <= "K"; msg[2] <= 8'h0D; msg[3] <= 8'h0A; msg_len <= 7'd4; state <= S_LOAD;
                        end
                        default: begin            // R H G M
                            run_sel_o <= (opc == "R") ? 2'd0 : (opc == "H") ? 2'd1 : (opc == "G") ? 2'd2 : 2'd3;
                            run_o <= 1'b1; state <= S_RUN;
                        end
                    endcase
                end
                S_ACK: state <= S_STREAM;         // ack가 들어간 다음 클록부터 FILL
                S_STREAM: begin
                    if (err_short_i) e_short <= 1'b1;
                    if (err_long_i)  e_long  <= 1'b1;
                    if (rx_take) begin
                        if (n_left == 7'd1) begin fw <= 2'd0; state <= S_FWAIT; end
                        n_left <= n_left - 7'd1;
                    end
                end
                S_FWAIT: begin                    // 마지막 바이트 뒤 판정이 나올 때까지 2클록
                    if (err_short_i) e_short <= 1'b1;
                    if (err_long_i)  e_long  <= 1'b1;
                    fw <= fw + 2'd1;
                    if (fw == 2'd2) begin
                        msg[0] <= "F"; msg[1] <= ":";
                        if (frame_valid_i && !e_long) begin
                            msg[2] <= "O"; msg[3] <= "K"; msg[4] <= 8'h0D; msg[5] <= 8'h0A; msg_len <= 7'd6;
                        end else if (e_long) begin
                            msg[2] <= "L"; msg[3] <= "O"; msg[4] <= "N"; msg[5] <= "G"; msg[6] <= 8'h0D; msg[7] <= 8'h0A; msg_len <= 7'd8;
                        end else begin
                            msg[2] <= "S"; msg[3] <= "H"; msg[4] <= "O"; msg[5] <= "R"; msg[6] <= "T"; msg[7] <= 8'h0D; msg[8] <= 8'h0A; msg_len <= 7'd9;
                        end
                        fshort_o <= !frame_valid_i && !e_long;
                        flong_o  <= e_long;
                        state <= S_LOAD;
                    end
                end
                S_PX: if (px_valid_i) begin
                    msg[0] <= "P"; msg[1] <= ":"; msg[2] <= hex(px_data_i[7:4]); msg[3] <= hex(px_data_i[3:0]);
                    msg[4] <= 8'h0D; msg[5] <= 8'h0A; msg_len <= 7'd6;
                    view_o <= {{8{px_data_i[7]}}, px_data_i};
                    state <= S_LOAD;
                end
                S_RUN: if (run_done_i) begin
                    if (run_err_i) begin
                        put_err;
                    end else begin
                        msg[0] <= opc; msg[1] <= hex(run_class_i); msg[2] <= ":";
                        view_o <= {12'd0, run_class_i}; cls_o <= run_class_i; cls_ok_o <= 1'b1;
                        if (opc == "M") begin
                            for (k = 0; k < 8; k = k + 1) begin
                                msg[3 + 2*k] <= hex(run_hidden_i[8*k + 4 +: 4]);
                                msg[4 + 2*k] <= hex(run_hidden_i[8*k +: 4]);
                            end
                            msg[19] <= " ";
                            for (p = 0; p < 10; p = p + 1) begin
                                for (k = 0; k < 7; k = k + 1)
                                    msg[20 + 8*p + k] <= hex((k == 0) ? {{3{run_scores_i[25*p + 24]}}, run_scores_i[25*p + 24]}
                                                                     : run_scores_i[25*p + 4*(6-k) +: 4]);
                                if (p < 9) msg[27 + 8*p] <= ",";
                            end
                            msg[99] <= 8'h0D; msg[100] <= 8'h0A; msg_len <= 7'd101;
                        end else begin
                            for (p = 0; p < 10; p = p + 1) begin
                                for (k = 0; k < 7; k = k + 1)
                                    msg[3 + 8*p + k] <= hex((k == 0) ? {{3{run_scores_i[25*p + 24]}}, run_scores_i[25*p + 24]}
                                                                    : run_scores_i[25*p + 4*(6-k) +: 4]);
                                if (p < 9) msg[10 + 8*p] <= ",";
                            end
                            if (opc == "H") begin         // 8개
                                msg[66] <= 8'h0D; msg[67] <= 8'h0A; msg_len <= 7'd68;
                            end else begin
                                msg[82] <= 8'h0D; msg[83] <= 8'h0A; msg_len <= 7'd84;
                            end
                        end
                    end
                    state <= S_LOAD;
                end
                S_LOAD: begin
                    tx_data_o <= msg[0]; tx_valid_o <= 1'b1; idx <= 7'd0; state <= S_SEND;
                end
                S_SEND: if (tx_valid_o && tx_ready_i) begin
                    if (idx + 7'd1 == msg_len) begin
                        tx_valid_o <= 1'b0; state <= S_IDLE;
                    end else begin
                        tx_data_o <= msg[idx + 7'd1]; idx <= idx + 7'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
