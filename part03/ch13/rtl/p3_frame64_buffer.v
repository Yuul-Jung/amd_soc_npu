`timescale 1ns/1ps
// 8×8(64원소) signed INT8 입력 프레임 수신 버퍼.
// 바이트 스트림(valid/ready/last)을 행 우선 순서(addr=row*8+col)로 저장한다.
// 정확히 64번째 바이트에 last가 있어야 유효 프레임. 짧은/긴 프레임은 버리고 오류 펄스를 낸다.
// 유효 프레임은 frame_ack_i까지 유지되며, 그동안 s_ready_o=0(Busy)으로 다음 입력을 막는다.
module p3_frame64_buffer(
    input wire clk,
    input wire resetn,
    input wire [7:0] s_data_i,
    input wire s_valid_i,
    input wire s_last_i,
    output wire s_ready_o,
    output wire frame_valid_o,
    input wire frame_ack_i,
    input wire rd_en_i,
    input wire [5:0] rd_addr_i,
    output reg signed [7:0] rd_data_o,
    output reg rd_valid_o,
    output reg err_short_o,
    output reg err_long_o
);
    localparam [1:0] FILL=2'd0, DROP=2'd1, FULL=2'd2;
    reg [1:0] state;
    reg [5:0] count_q;
    reg signed [7:0] mem [0:63];

    assign s_ready_o = resetn && (state != FULL);
    assign frame_valid_o = (state == FULL);
    wire accept = s_valid_i && s_ready_o;

    // 저장 배열은 Reset 없이 동기 쓰기·동기 읽기(1클록 지연)로 메모리 추론을 허용한다.
    always @(posedge clk) begin
        if (accept && state == FILL)
            mem[count_q] <= s_data_i;
        if (rd_en_i)
            rd_data_o <= mem[rd_addr_i];
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state <= FILL;
            count_q <= 6'd0;
            rd_valid_o <= 1'b0;
            err_short_o <= 1'b0;
            err_long_o <= 1'b0;
        end else begin
            err_short_o <= 1'b0;
            err_long_o <= 1'b0;
            // 읽기 데이터는 유효 프레임 보관 중 요청한 경우에만 유효로 표시한다.
            rd_valid_o <= rd_en_i && (state == FULL);
            case (state)
                FILL: if (accept) begin
                    if (s_last_i) begin
                        count_q <= 6'd0;
                        if (count_q == 6'd63)
                            state <= FULL;
                        else
                            err_short_o <= 1'b1;
                    end else if (count_q == 6'd63) begin
                        // 64번째에 last가 없으면 긴 프레임: 다음 last까지 버리고 재동기화.
                        count_q <= 6'd0;
                        err_long_o <= 1'b1;
                        state <= DROP;
                    end else begin
                        count_q <= count_q + 6'd1;
                    end
                end
                DROP: if (accept && s_last_i)
                    state <= FILL;
                FULL: if (frame_ack_i)
                    state <= FILL;
                default: state <= FILL;
            endcase
        end
    end
endmodule
