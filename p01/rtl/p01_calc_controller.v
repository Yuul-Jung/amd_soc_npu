// 1장 UART 계산기 명령 해석기. 11장과 같은 형식: 1바이트 명령 + 바이너리 페이로드(빅엔디언), stop-and-wait.
//
//   명령   페이로드                     응답
//   'M'    a_hi a_lo b_hi b_lo (signed16)  "A:" + 누산값 16진수 10자리 + " L:" + 지연 클록 1자리 + "\r\n"
//   'C'    없음                          "OK\r\n"   (누산값 0으로)
//   'S'    없음                          "I\r\n"    (준비 상태)
//   그 밖  —                             받은 바이트를 그대로 돌려준다 (1-1 에코)
//
// 지연(L)은 valid를 낸 클록부터 고른 코어의 valid가 보일 때까지의 클록 수다 (1-2 = 1, 1-3·1-4 = 2).
// STAGE = 지금까지 끝낸 서브젝트 수. STAGE 1(1-1)에서는 MAC 코어가 없으므로 'M'·'C'도 에코로 돌려준다.
// 응답을 보내는 동안에는 새 바이트를 받지 않는다 (rx_ready = 0, uart_core FIFO가 보관).
`timescale 1ns/1ps
`default_nettype none
module p01_calc_controller #(
    parameter integer ACC_WIDTH = 40,
    parameter integer STAGE     = 4
) (
    input  wire                        clk,
    input  wire                        resetn,
    // UART 수신
    input  wire [7:0]                  rx_data_i,
    input  wire                        rx_valid_i,
    output wire                        rx_ready_o,
    // UART 송신
    output reg  [7:0]                  tx_data_o,
    output reg                         tx_valid_o,
    input  wire                        tx_ready_i,
    // MAC 묶음
    output reg                         clear_o,
    output reg                         valid_o,
    output reg  signed [15:0]          a_o,
    output reg  signed [15:0]          b_o,
    input  wire signed [ACC_WIDTH-1:0] acc_i,
    input  wire                        acc_valid_i
);
    localparam [2:0] S_IDLE = 3'd0, S_ARG = 3'd1, S_WAIT = 3'd2, S_LOAD = 3'd3, S_SEND = 3'd4;
    localparam integer MSG_MAX = 18;            // "A:" 2 + 10 + " L:" 3 + 1 + "\r\n" 2
    localparam integer NIB = (ACC_WIDTH + 3) / 4;

    reg [2:0]  state;
    reg [1:0]  arg_cnt;
    reg [7:0]  arg [0:2];                       // 앞 세 바이트 (네 번째는 받는 클록에 바로 씀)
    reg [3:0]  lat;
    reg [7:0]  msg [0:MSG_MAX-1];
    reg [4:0]  msg_len, idx;
    integer    k;

    function [7:0] hex(input [3:0] n);
        hex = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});   // '0'~'9', 'A'~'F'
    endfunction

    assign rx_ready_o = (state == S_IDLE) || (state == S_ARG);
    wire rx_take = rx_valid_i && rx_ready_o;

    always @(posedge clk) begin
        if (!resetn) begin
            state      <= S_IDLE;
            arg_cnt    <= 2'd0;
            lat        <= 4'd0;
            msg_len    <= 5'd0;
            idx        <= 5'd0;
            tx_data_o  <= 8'd0;
            tx_valid_o <= 1'b0;
            clear_o    <= 1'b0;
            valid_o    <= 1'b0;
            a_o        <= 16'sd0;
            b_o        <= 16'sd0;
        end else begin
            clear_o <= 1'b0;
            valid_o <= 1'b0;
            case (state)
                S_IDLE: if (rx_take) begin
                    case ((STAGE >= 2 || rx_data_i == "S") ? rx_data_i : 8'h00)
                        "M": begin arg_cnt <= 2'd0; state <= S_ARG; end
                        "C": begin
                            clear_o <= 1'b1;
                            msg[0] <= "O"; msg[1] <= "K"; msg[2] <= 8'h0D; msg[3] <= 8'h0A;
                            msg_len <= 5'd4; state <= S_LOAD;
                        end
                        "S": begin
                            msg[0] <= "I"; msg[1] <= 8'h0D; msg[2] <= 8'h0A;
                            msg_len <= 5'd3; state <= S_LOAD;
                        end
                        default: begin                   // 1-1 에코 (STAGE 1에서는 M·C 포함)
                            msg[0] <= rx_data_i;
                            msg_len <= 5'd1; state <= S_LOAD;
                        end
                    endcase
                end
                S_ARG: if (rx_take) begin
                    if (arg_cnt == 2'd3) begin
                        a_o     <= {arg[0], arg[1]};
                        b_o     <= {arg[2], rx_data_i};
                        valid_o <= 1'b1;
                        lat     <= 4'd0;
                        state   <= S_WAIT;
                    end else begin
                        arg[arg_cnt] <= rx_data_i;
                        arg_cnt <= arg_cnt + 2'd1;
                    end
                end
                S_WAIT: begin
                    if (acc_valid_i) begin
                        msg[0] <= "A"; msg[1] <= ":";
                        for (k = 0; k < NIB; k = k + 1)
                            msg[2 + k] <= hex(acc_i[4*(NIB-1-k) +: 4]);
                        msg[2 + NIB] <= " "; msg[3 + NIB] <= "L"; msg[4 + NIB] <= ":";
                        msg[5 + NIB] <= hex(lat);
                        msg[6 + NIB] <= 8'h0D; msg[7 + NIB] <= 8'h0A;
                        msg_len <= NIB + 8;
                        state <= S_LOAD;
                    end else if (lat != 4'hF) begin
                        lat <= lat + 4'd1;
                    end
                end
                S_LOAD: begin
                    tx_data_o  <= msg[0];
                    tx_valid_o <= 1'b1;
                    idx        <= 5'd0;
                    state      <= S_SEND;
                end
                S_SEND: if (tx_valid_o && tx_ready_i) begin
                    if (idx + 5'd1 == msg_len) begin
                        tx_valid_o <= 1'b0;
                        state      <= S_IDLE;
                    end else begin
                        tx_data_o <= msg[idx + 5'd1];
                        idx       <= idx + 5'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    initial begin
        if (NIB + 8 > MSG_MAX)
            $fatal(1, "ACC_WIDTH too wide for response buffer");
    end
endmodule
`default_nettype wire
