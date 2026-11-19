// 4장 디버그 콘솔: 784 가속기 서브젝트를 UART 명령으로 확인한다. 1~3장과 같은 형식 (1바이트 명령 + 바이너리).
// p = 엔진 (0 INT8, 1 INT16), 원소 하나 = INT8 1바이트 / INT16 2바이트(빅엔디언). g = PE 구성 1·4·8.
//
//   명령 페이로드                         응답                                       서브젝트 (STAGE)
//   S    없음                             "I"                                        모두
//   Q    int32 4바이트                     "Q:" INT8 2자리 "," INT16 4자리 " O:" 넘침 2자리   4-1 (1)
//   B    p class b4..b0 (signed40)         "OK"                                       4-2 (2)   IDLE에서만
//   V    p class n + 원소 n개              "OK"   W[class][0..n-1] 쓰기                4-2 (2)
//   A    p                                "OK"   784 추론 시작 (외부 누산 Clear)       4-2 (2)
//   X    p n(=64) + 원소 64개               "OK"   x 타일 (마지막 타일은 16 + 0 48개)     4-2 (2)
//   T    p 타일번호                         "T" 번호 / 마지막 타일 "C" 클래스 ":" 점수 11자리 ×10   4-2 (2)
//   U    g class n + 바이트 n개             "OK"   PE 구성 g의 가중치 (PE1은 class 무시)   4-4 (4)
//   K    g                                "K" g ":" 클록 4자리 " " 점수 7자리 (PE1 1개, 그 밖 10개)  4-4 (4)
//   엔진 오류 "E" 코드 (17장 err_code: 1 상태, 2 타일 중복, 3 타일 건너뜀, 4 프레임 없음, 5 쓰기)
//   모르는 명령 "?", 범위 밖 "ERR". 끝은 모두 \r\n.  p = 1은 STAGE 3부터.
`timescale 1ns/1ps
`default_nettype none
module p04_console #(
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
    output reg                q_valid_o,
    output reg  signed [31:0] q_x_o,
    input  wire               q_done_i,
    input  wire signed [7:0]  q8_i,
    input  wire signed [15:0] q16_i,
    input  wire               q_ov8_i,
    input  wire               q_ov16_i,
    output wire [7:0]         s_data_o,
    output wire               s_valid_o,
    output wire               s_last_o,
    input  wire               s_ready_i,
    input  wire               held8_i,
    output reg                ack8_o,
    output reg                x16_we_o,
    output reg  [5:0]         x16_addr_o,
    output reg  signed [15:0] x16_data_o,
    output reg                x16_set_o,
    input  wire               held16_i,
    output reg                p_o,
    output reg                start_o,
    output reg                tile_go_o,
    output reg  [3:0]         tile_id_o,
    output reg                w_wr_o,
    output reg                b_wr_o,
    output reg  [3:0]         class_o,
    output reg  [5:0]         addr_o,
    output reg  signed [15:0] w_o,
    output reg  signed [39:0] b_o,
    input  wire               tile_done_i,
    input  wire               done_i,
    input  wire               error_i,
    input  wire [2:0]         err_code_i,
    input  wire               ovf_i,
    input  wire [3:0]         class_i,
    input  wire [419:0]       scores_i,
    output reg  [3:0]         g_o,
    output reg                pe_wr_o,
    output reg                pe_run_o,
    input  wire               pe_done_i,
    input  wire               pe_err_i,
    input  wire [15:0]        pe_cycles_i,
    input  wire [249:0]       pe_scores_i,
    // 표시
    output reg  [15:0]        view_o,
    output reg  [3:0]         cls_o,
    output reg                cls_ok_o
);
    localparam [3:0] S_IDLE = 4'd0, S_HDR = 4'd1, S_ISSUE = 4'd2, S_DATA = 4'd3, S_DONE = 4'd4,
                     S_QW = 4'd5, S_TW = 4'd6, S_KW = 4'd7, S_LOAD = 4'd8, S_SEND = 4'd9, S_ACK = 4'd10;
    localparam integer MSG_MAX = 128;

    reg [3:0] state;
    reg [7:0] opc;
    reg [7:0] hd [0:6];
    reg [3:0] need, got;
    reg [1:0] dly;
    reg [7:0] n_elem;                 // 남은 원소 수
    reg [5:0] eidx;                   // 원소 주소
    reg       hi_half;                // INT16 원소의 위 바이트를 받았음
    reg [7:0] hi_byte;
    reg       bad;                    // 데이터는 받되 결과는 ERR
    reg       eng_err;
    reg [2:0] eng_code;
    reg [7:0] msg [0:MSG_MAX-1];
    reg [6:0] msg_len, idx;
    integer   k, p;

    function [7:0] hex(input [3:0] n);
        hex = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
    endfunction

    function [3:0] plen(input [7:0] c);    // 고정 머리 바이트 수, 15 = 모르는 명령
        case (c)
            "S":     plen = 4'd0;
            "Q":     plen = 4'd4;
            "B":     plen = (STAGE >= 2) ? 4'd7 : 4'd15;
            "V":     plen = (STAGE >= 2) ? 4'd3 : 4'd15;
            "A":     plen = (STAGE >= 2) ? 4'd1 : 4'd15;
            "X":     plen = (STAGE >= 2) ? 4'd2 : 4'd15;
            "T":     plen = (STAGE >= 2) ? 4'd2 : 4'd15;
            "U":     plen = (STAGE >= 4) ? 4'd3 : 4'd15;
            "K":     plen = (STAGE >= 4) ? 4'd1 : 4'd15;
            default: plen = 4'd15;
        endcase
    endfunction

    wire is_eng   = (opc == "B" || opc == "V" || opc == "A" || opc == "X" || opc == "T");
    wire p_ok     = (hd[0] == 8'd0) || (hd[0] == 8'd1 && STAGE >= 3);
    wire g_ok     = (hd[0] == 8'd1) || (hd[0] == 8'd4) || (hd[0] == 8'd8);
    wire wide     = (opc == "V" || opc == "X") && hd[0][0];       // INT16 원소
    wire [7:0] n_hdr = (opc == "X") ? hd[1] : hd[2];
    wire fields_ok =
        (opc == "B") ? (p_ok && hd[1] < 8'd10) :
        (opc == "V") ? (p_ok && hd[1] < 8'd10 && hd[2] >= 8'd1 && hd[2] <= 8'd64) :
        (opc == "A") ? p_ok :
        (opc == "X") ? (p_ok && hd[1] == 8'd64) :
        (opc == "T") ? (p_ok && hd[1] < 8'd13) :
        (opc == "U") ? (g_ok && hd[1] < 8'd10 && hd[2] >= 8'd1 && hd[2] <= 8'd64) :
        (opc == "K") ? g_ok : 1'b1;

    // INT8 x 타일 바이트는 3-1 버퍼로 바로 흘린다
    wire stream8 = (state == S_DATA) && (opc == "X") && !hd[0][0] && !bad;
    assign s_data_o   = rx_data_i;
    assign s_valid_o  = stream8 && rx_valid_i;
    assign s_last_o   = (n_elem == 8'd1);
    assign rx_ready_o = (state == S_IDLE) || (state == S_HDR) || (state == S_DATA && (!stream8 || s_ready_i));
    wire   rx_take    = rx_valid_i && rx_ready_o;

    task put3(input [7:0] a, input [7:0] b, input [7:0] c, input [6:0] n);
        begin
            msg[0] <= a; msg[1] <= b; msg[2] <= c; msg[n - 2] <= 8'h0D; msg[n - 1] <= 8'h0A; msg_len <= n;
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE; opc <= 8'd0; need <= 4'd0; got <= 4'd0; dly <= 2'd0; n_elem <= 8'd0; eidx <= 6'd0;
            hi_half <= 1'b0; hi_byte <= 8'd0; bad <= 1'b0; eng_err <= 1'b0; eng_code <= 3'd0;
            msg_len <= 7'd0; idx <= 7'd0; tx_data_o <= 8'd0; tx_valid_o <= 1'b0;
            q_valid_o <= 1'b0; q_x_o <= 32'sd0; ack8_o <= 1'b0; x16_we_o <= 1'b0; x16_addr_o <= 6'd0;
            x16_data_o <= 16'sd0; x16_set_o <= 1'b0; p_o <= 1'b0; start_o <= 1'b0; tile_go_o <= 1'b0;
            tile_id_o <= 4'd0; w_wr_o <= 1'b0; b_wr_o <= 1'b0; class_o <= 4'd0; addr_o <= 6'd0;
            w_o <= 16'sd0; b_o <= 40'sd0; g_o <= 4'd0; pe_wr_o <= 1'b0; pe_run_o <= 1'b0;
            view_o <= 16'd0; cls_o <= 4'd0; cls_ok_o <= 1'b0;
        end else begin
            q_valid_o <= 1'b0; ack8_o <= 1'b0; x16_we_o <= 1'b0; x16_set_o <= 1'b0; start_o <= 1'b0;
            tile_go_o <= 1'b0; w_wr_o <= 1'b0; b_wr_o <= 1'b0; pe_wr_o <= 1'b0; pe_run_o <= 1'b0;
            if (error_i) begin eng_err <= 1'b1; eng_code <= err_code_i; end      // 엔진 오류는 명령 동안 모은다
            case (state)
                S_IDLE: if (rx_take && rx_data_i != 8'h0D && rx_data_i != 8'h0A) begin
                    opc <= rx_data_i; got <= 4'd0; need <= plen(rx_data_i); eng_err <= 1'b0; bad <= 1'b0; dly <= 2'd0;
                    if (plen(rx_data_i) == 4'd15) begin put3("?", 8'h0D, 8'h0A, 7'd3); state <= S_LOAD; end
                    else if (plen(rx_data_i) == 4'd0) begin put3("I", 8'h0D, 8'h0A, 7'd3); state <= S_LOAD; end
                    else state <= S_HDR;
                end
                S_HDR: if (rx_take) begin
                    hd[got] <= rx_data_i;
                    if (got + 4'd1 == need) state <= S_ISSUE;
                    else got <= got + 4'd1;
                end
                S_ISSUE: begin
                    p_o <= hd[0][0];
                    if (opc == "V" || opc == "X" || opc == "U") begin   // 데이터가 따라온다: 범위가 틀려도 받아서 버린다
                        bad <= !fields_ok; n_elem <= n_hdr; eidx <= 6'd0; hi_half <= 1'b0;
                        class_o <= hd[1][3:0]; g_o <= hd[0][3:0];
                        // INT8 x는 들고 있는 타일을 먼저 놓는다
                        if (opc == "X" && fields_ok && !hd[0][0] && held8_i) begin ack8_o <= 1'b1; state <= S_ACK; end
                        else state <= S_DATA;
                    end else if (!fields_ok) begin
                        put3("E", "R", "R", 7'd5); msg[3] <= 8'h0D; msg[4] <= 8'h0A; state <= S_LOAD;
                    end else case (opc)
                        "Q": begin q_x_o <= {hd[0], hd[1], hd[2], hd[3]}; q_valid_o <= 1'b1; state <= S_QW; end
                        "B": begin class_o <= hd[1][3:0]; b_o <= {hd[2], hd[3], hd[4], hd[5], hd[6]}; b_wr_o <= 1'b1; state <= S_DONE; end
                        "A": begin start_o <= 1'b1; state <= S_DONE; end
                        "T": begin tile_id_o <= hd[1][3:0]; tile_go_o <= 1'b1; state <= S_TW; end
                        default: begin g_o <= hd[0][3:0]; pe_run_o <= 1'b1; state <= S_KW; end   // "K"
                    endcase
                end
                S_ACK: state <= S_DATA;
                S_DATA: if (rx_take) begin
                    if (wide && !hi_half) begin
                        hi_byte <= rx_data_i; hi_half <= 1'b1;
                    end else begin
                        hi_half <= 1'b0;
                        if (!bad) begin
                            if (opc == "V") begin
                                addr_o <= eidx; w_o <= wide ? {hi_byte, rx_data_i} : {{8{rx_data_i[7]}}, rx_data_i}; w_wr_o <= 1'b1;
                            end else if (opc == "U") begin
                                addr_o <= eidx; w_o <= {{8{rx_data_i[7]}}, rx_data_i}; pe_wr_o <= 1'b1;
                            end else if (wide) begin                  // INT16 x
                                x16_addr_o <= eidx; x16_data_o <= {hi_byte, rx_data_i}; x16_we_o <= 1'b1;
                            end                                       // INT8 x는 스트림으로 이미 들어감
                        end
                        eidx <= eidx + 6'd1;
                        n_elem <= n_elem - 8'd1;
                        if (n_elem == 8'd1) begin
                            if (opc == "X" && wide && !bad) x16_set_o <= 1'b1;
                            state <= S_DONE;
                        end
                    end
                end
                S_DONE: if (dly != 2'd3) dly <= dly + 2'd1;   // 쓰기·시작 오류가 엔진에서 나올 때까지 기다린다
                else begin
                    if (bad) begin
                        put3("E", "R", "R", 7'd5); msg[3] <= 8'h0D; msg[4] <= 8'h0A;
                    end else if (eng_err || error_i) begin
                        put3("E", hex({1'b0, error_i ? err_code_i : eng_code}), 8'h0D, 7'd4); msg[3] <= 8'h0A;
                    end else begin
                        put3("O", "K", 8'h0D, 7'd4); msg[3] <= 8'h0A;
                    end
                    state <= S_LOAD;
                end
                S_QW: if (q_done_i) begin
                    msg[0] <= "Q"; msg[1] <= ":"; msg[2] <= hex(q8_i[7:4]); msg[3] <= hex(q8_i[3:0]); msg[4] <= ",";
                    for (k = 0; k < 4; k = k + 1) msg[5 + k] <= hex(q16_i[4*(3-k) +: 4]);
                    msg[9] <= " "; msg[10] <= "O"; msg[11] <= ":"; msg[12] <= hex({3'd0, q_ov8_i}); msg[13] <= hex({3'd0, q_ov16_i});
                    msg[14] <= 8'h0D; msg[15] <= 8'h0A; msg_len <= 7'd16;
                    view_o <= q16_i;
                    state <= S_LOAD;
                end
                S_TW: begin
                    if (error_i) begin
                        put3("E", hex({1'b0, err_code_i}), 8'h0D, 7'd4); msg[3] <= 8'h0A; state <= S_LOAD;
                    end else if (done_i) begin     // 마지막 타일 뒤 SCORE·FINISH가 끝남
                        msg[0] <= "C"; msg[1] <= hex(class_i); msg[2] <= ":";
                        for (p = 0; p < 10; p = p + 1) begin
                            for (k = 0; k < 11; k = k + 1)
                                msg[3 + 12*p + k] <= hex((k == 0) ? {{2{scores_i[42*p + 41]}}, scores_i[42*p + 41 -: 2]}
                                                                 : scores_i[42*p + 4*(10-k) +: 4]);
                            if (p < 9) msg[14 + 12*p] <= ",";
                        end
                        if (ovf_i) begin
                            msg[122] <= " "; msg[123] <= "V"; msg[124] <= 8'h0D; msg[125] <= 8'h0A; msg_len <= 7'd126;
                        end else begin
                            msg[122] <= 8'h0D; msg[123] <= 8'h0A; msg_len <= 7'd124;
                        end
                        view_o <= {12'd0, class_i}; cls_o <= class_i; cls_ok_o <= 1'b1;
                        state <= S_LOAD;
                    end else if (tile_done_i && tile_id_o != 4'd12) begin
                        put3("T", hex(tile_id_o), 8'h0D, 7'd4); msg[3] <= 8'h0A;
                        view_o <= {12'd0, tile_id_o};
                        state <= S_LOAD;
                    end
                end
                S_KW: if (pe_done_i) begin
                    if (pe_err_i) begin
                        put3("E", "R", "R", 7'd5); msg[3] <= 8'h0D; msg[4] <= 8'h0A;
                    end else begin
                        msg[0] <= "K"; msg[1] <= hex(g_o); msg[2] <= ":";
                        for (k = 0; k < 4; k = k + 1) msg[3 + k] <= hex(pe_cycles_i[4*(3-k) +: 4]);
                        msg[7] <= " ";
                        for (p = 0; p < 10; p = p + 1) begin
                            for (k = 0; k < 7; k = k + 1)
                                msg[8 + 8*p + k] <= hex((k == 0) ? {{3{pe_scores_i[25*p + 24]}}, pe_scores_i[25*p + 24]}
                                                                : pe_scores_i[25*p + 4*(6-k) +: 4]);
                            if (p < 9) msg[15 + 8*p] <= ",";
                        end
                        if (g_o == 4'd1) begin
                            msg[15] <= 8'h0D; msg[16] <= 8'h0A; msg_len <= 7'd17;
                        end else begin
                            msg[87] <= 8'h0D; msg[88] <= 8'h0A; msg_len <= 7'd89;
                        end
                        view_o <= pe_cycles_i;
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
