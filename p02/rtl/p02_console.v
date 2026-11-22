// 2장 디버그 콘솔: 서브젝트 모듈을 UART 명령 하나씩으로 확인한다. 11장 명령과 같은 형식
// (1바이트 명령 + 바이너리 페이로드, 빅엔디언, stop-and-wait). X·W·B·S는 11장과 바이트까지 같다.
//
//   명령 페이로드              응답                                   서브젝트 (STAGE)
//   S    없음                  "I"                                    모두
//   X    addr hi lo            "OK"                                   2-1 (1)
//   W    n addr hi lo          "OK"                                   2-1 (1)
//   x    addr                  "X:" 16진수 4자리                       2-1 (1)
//   w    n addr                "W:" 16진수 4자리                       2-1 (1)
//   Q    int32 4바이트          "Q:" 2자리 " O:" 넘침 1자리             2-2 (2)  (32→8비트, SHIFT 8, 반올림, 포화)
//   D    len                   "D:" 10자리                            2-3 (3)  X·W0
//   P    len                   "P:" 10자리 ×4 (쉼표)                   2-4 (4)  X·W0~W3
//   B    n b4..b0 (signed40)    "OK"                                   2-5 (5)
//   L    len                   "L:" 4자리 ×4 " O:" 넘침 1자리          2-5 (5)  Dense(+Bias, ReLU, 16비트)
//   N    len                   "N:" 4자리 ×4 " O:" 넘침 1자리          2-6 (6)  npu_core (BRAM + Dense)
//   그 밖 (CR·LF 제외)          "?"         필드 범위 밖           "ERR"   (응답 끝은 모두 \r\n)
// len은 1~64, addr 0~63, n 0~3. view_o는 마지막 결과의 아래 16비트 (LED·7세그먼트용).
`timescale 1ns/1ps
`default_nettype none
module p02_console #(
    parameter integer STAGE = 8
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
    output reg  [3:0]         op_o,
    output reg                op_valid_o,
    output reg  [5:0]         addr_o,
    output reg  [1:0]         neuron_o,
    output reg  signed [15:0] data_o,
    output reg  signed [39:0] bias_o,
    output reg  signed [31:0] qin_o,
    output reg  [6:0]         len_o,
    input  wire               op_done_i,
    input  wire               op_error_i,
    input  wire [159:0]       res_i,
    input  wire [3:0]         flags_i,
    output reg  [15:0]        view_o
);
    localparam [3:0] OP_XWR = 4'd1, OP_WWR = 4'd2, OP_BWR = 4'd3, OP_XRD = 4'd4, OP_WRD = 4'd5,
                     OP_QNT = 4'd6, OP_DOT = 4'd7, OP_PE4 = 4'd8, OP_DENSE = 4'd9, OP_CORE = 4'd10;
    localparam [2:0] S_IDLE = 3'd0, S_RECV = 3'd1, S_ISSUE = 3'd2, S_WAIT = 3'd3, S_LOAD = 3'd4, S_SEND = 3'd5;
    localparam integer MSG_MAX = 48;

    reg [2:0] state;
    reg [7:0] opc;
    reg [7:0] pl [0:5];
    reg [2:0] need, got;
    reg [7:0] msg [0:MSG_MAX-1];
    reg [5:0] msg_len, idx;
    integer   i, k, p;

    function [7:0] hex(input [3:0] n);
        hex = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
    endfunction

    // 명령 → 페이로드 수. 이 STAGE에 없는 명령은 7 (= 모름)
    function [2:0] plen(input [7:0] c);
        case (c)
            "S":      plen = 3'd0;
            "X":      plen = 3'd3;
            "W":      plen = 3'd4;
            "x":      plen = 3'd1;
            "w":      plen = 3'd2;
            "Q":      plen = (STAGE >= 2) ? 3'd4 : 3'd7;
            "D":      plen = (STAGE >= 3) ? 3'd1 : 3'd7;
            "P":      plen = (STAGE >= 4) ? 3'd1 : 3'd7;
            "B":      plen = (STAGE >= 5) ? 3'd6 : 3'd7;
            "L":      plen = (STAGE >= 5) ? 3'd1 : 3'd7;
            "N":      plen = (STAGE >= 6) ? 3'd1 : 3'd7;
            default:  plen = 3'd7;
        endcase
    endfunction

    wire fields_ok =
        (opc == "X" || opc == "x") ? (pl[0] < 8'd64) :
        (opc == "W" || opc == "w") ? (pl[0] < 8'd4 && pl[1] < 8'd64) :
        (opc == "B")               ? (pl[0] < 8'd4) :
        (opc == "D" || opc == "P" || opc == "L" || opc == "N") ? (pl[0] >= 8'd1 && pl[0] <= 8'd64) : 1'b1;

    assign rx_ready_o = (state == S_IDLE) || (state == S_RECV);
    wire rx_take = rx_valid_i && rx_ready_o;

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE; opc <= 8'd0; need <= 3'd0; got <= 3'd0; msg_len <= 6'd0; idx <= 6'd0;
            tx_data_o <= 8'd0; tx_valid_o <= 1'b0; op_o <= 4'd0; op_valid_o <= 1'b0;
            addr_o <= 6'd0; neuron_o <= 2'd0; data_o <= 16'sd0; bias_o <= 40'sd0; qin_o <= 32'sd0; len_o <= 7'd0;
            view_o <= 16'd0;
        end else begin
            op_valid_o <= 1'b0;
            case (state)
                S_IDLE: if (rx_take && rx_data_i != 8'h0D && rx_data_i != 8'h0A) begin
                    opc <= rx_data_i; got <= 3'd0; need <= plen(rx_data_i);
                    if (plen(rx_data_i) == 3'd7) begin
                        msg[0] <= "?"; msg[1] <= 8'h0D; msg[2] <= 8'h0A; msg_len <= 6'd3; state <= S_LOAD;
                    end else if (rx_data_i == "S") begin
                        msg[0] <= "I"; msg[1] <= 8'h0D; msg[2] <= 8'h0A; msg_len <= 6'd3; state <= S_LOAD;
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
                        msg[0] <= "E"; msg[1] <= "R"; msg[2] <= "R"; msg[3] <= 8'h0D; msg[4] <= 8'h0A;
                        msg_len <= 6'd5; state <= S_LOAD;
                    end else begin
                        case (opc)
                            "X": begin op_o <= OP_XWR; addr_o <= pl[0][5:0]; data_o <= {pl[1], pl[2]}; end
                            "W": begin op_o <= OP_WWR; neuron_o <= pl[0][1:0]; addr_o <= pl[1][5:0]; data_o <= {pl[2], pl[3]}; end
                            "x": begin op_o <= OP_XRD; addr_o <= pl[0][5:0]; end
                            "w": begin op_o <= OP_WRD; neuron_o <= pl[0][1:0]; addr_o <= pl[1][5:0]; end
                            "Q": begin op_o <= OP_QNT; qin_o <= {pl[0], pl[1], pl[2], pl[3]}; end
                            "D": begin op_o <= OP_DOT; len_o <= pl[0][6:0]; end
                            "P": begin op_o <= OP_PE4; len_o <= pl[0][6:0]; end
                            "B": begin op_o <= OP_BWR; neuron_o <= pl[0][1:0]; bias_o <= {pl[1], pl[2], pl[3], pl[4], pl[5]}; end
                            "L": begin op_o <= OP_DENSE; len_o <= pl[0][6:0]; end
                            default: begin op_o <= OP_CORE; len_o <= pl[0][6:0]; end   // "N"
                        endcase
                        op_valid_o <= 1'b1;
                        state <= S_WAIT;
                    end
                end
                S_WAIT: if (op_done_i) begin
                    if (op_error_i) begin
                        msg[0] <= "E"; msg[1] <= "R"; msg[2] <= "R"; msg[3] <= 8'h0D; msg[4] <= 8'h0A; msg_len <= 6'd5;
                    end else begin
                        case (opc)
                            "X", "W", "B": begin
                                msg[0] <= "O"; msg[1] <= "K"; msg[2] <= 8'h0D; msg[3] <= 8'h0A; msg_len <= 6'd4;
                            end
                            "x", "w": begin
                                msg[0] <= (opc == "x") ? "X" : "W"; msg[1] <= ":";
                                for (k = 0; k < 4; k = k + 1) msg[2 + k] <= hex(res_i[4*(3-k) +: 4]);
                                msg[6] <= 8'h0D; msg[7] <= 8'h0A; msg_len <= 6'd8;
                                view_o <= res_i[15:0];
                            end
                            "Q": begin
                                msg[0] <= "Q"; msg[1] <= ":"; msg[2] <= hex(res_i[7:4]); msg[3] <= hex(res_i[3:0]);
                                msg[4] <= " "; msg[5] <= "O"; msg[6] <= ":"; msg[7] <= hex(flags_i);
                                msg[8] <= 8'h0D; msg[9] <= 8'h0A; msg_len <= 6'd10;
                                view_o <= {{8{res_i[7]}}, res_i[7:0]};
                            end
                            "D": begin
                                msg[0] <= "D"; msg[1] <= ":";
                                for (k = 0; k < 10; k = k + 1) msg[2 + k] <= hex(res_i[4*(9-k) +: 4]);
                                msg[12] <= 8'h0D; msg[13] <= 8'h0A; msg_len <= 6'd14;
                                view_o <= res_i[15:0];
                            end
                            "P": begin
                                msg[0] <= "P"; msg[1] <= ":";
                                for (p = 0; p < 4; p = p + 1) begin
                                    for (k = 0; k < 10; k = k + 1) msg[2 + 11*p + k] <= hex(res_i[40*p + 4*(9-k) +: 4]);
                                    if (p < 3) msg[12 + 11*p] <= ",";
                                end
                                msg[45] <= 8'h0D; msg[46] <= 8'h0A; msg_len <= 6'd47;
                                view_o <= res_i[15:0];
                            end
                            default: begin                       // "L", "N"
                                msg[0] <= opc; msg[1] <= ":";
                                for (p = 0; p < 4; p = p + 1) begin
                                    for (k = 0; k < 4; k = k + 1) msg[2 + 5*p + k] <= hex(res_i[16*p + 4*(3-k) +: 4]);
                                    if (p < 3) msg[6 + 5*p] <= ",";
                                end
                                msg[21] <= " "; msg[22] <= "O"; msg[23] <= ":"; msg[24] <= hex(flags_i);
                                msg[25] <= 8'h0D; msg[26] <= 8'h0A; msg_len <= 6'd27;
                                view_o <= res_i[15:0];
                            end
                        endcase
                    end
                    state <= S_LOAD;
                end
                S_LOAD: begin
                    tx_data_o <= msg[0]; tx_valid_o <= 1'b1; idx <= 6'd0; state <= S_SEND;
                end
                S_SEND: if (tx_valid_o && tx_ready_i) begin
                    if (idx + 6'd1 == msg_len) begin
                        tx_valid_o <= 1'b0; state <= S_IDLE;
                    end else begin
                        tx_data_o <= msg[idx + 6'd1]; idx <= idx + 6'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
