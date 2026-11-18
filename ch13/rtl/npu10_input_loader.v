`timescale 1ns/1ps
`default_nettype none
// 13장 입력 적재기: 8×8 특징 64원소를 순서대로 받아 04장 BRAM 버퍼(8비트×64)에 쓰고,
// 64개가 모두 들어온 뒤에만 14장이 주소로 읽을 수 있게 한다.
// 입력 계약: 원소 i = 8×8 평균 풀링 화소 (행 우선, i = 행*8 + 열),
//            값 = round(평균 화소 / 2), 범위 0~127 (INT8, 부호 비트 0).
module npu10_input_loader (
    input  wire              clk,
    input  wire              resetn,
    input  wire              load_start_i,
    input  wire              in_valid_i,
    input  wire        [7:0] in_data_i,
    input  wire              in_last_i,
    input  wire              rd_en_i,
    input  wire        [5:0] rd_addr_i,
    output wire signed [7:0] rd_data_o,
    output wire              rd_valid_o,
    output wire              loading_o,
    output wire              loaded_o,
    output reg               len_err_o,
    output reg               range_err_o,
    output reg         [6:0] count_o
);
    localparam IDLE=0, LOAD=1, DONE=2, ERR=3;
    reg [1:0] state;

    // LOAD 상태에서 받은 원소의 판정: 부호 비트, 마지막 표시 위치
    wire last_slot  = (count_o == 7'd63);
    wire bad_range  = in_data_i[7];
    wire bad_length = in_last_i != last_slot;
    wire write_fire = (state == LOAD) && in_valid_i && !load_start_i && !bad_range && !bad_length;

    assign loading_o = (state == LOAD);
    assign loaded_o  = (state == DONE);

    bram_sync_buffer #(.DATA_WIDTH(8), .ADDR_WIDTH(6)) input_ram (
        .clk(clk), .resetn(resetn),
        .wr_en(write_fire), .wr_addr(count_o[5:0]), .wr_data(in_data_i),
        .rd_en(rd_en_i && state == DONE), .rd_addr(rd_addr_i),
        .rd_data(rd_data_o), .rd_valid(rd_valid_o));

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE; count_o <= 0; len_err_o <= 0; range_err_o <= 0;
        end else if (load_start_i) begin
            // 새 샘플: 어느 상태에서든 개수·오류를 지우고 다시 받는다.
            state <= LOAD; count_o <= 0; len_err_o <= 0; range_err_o <= 0;
        end else begin
            case (state)
                IDLE: ;
                LOAD: if (in_valid_i) begin
                    if (bad_range) begin
                        range_err_o <= 1; state <= ERR;
                    end else if (bad_length) begin
                        len_err_o <= 1; state <= ERR;
                    end else begin
                        count_o <= count_o + 7'd1;
                        if (in_last_i) state <= DONE;
                    end
                end
                DONE: if (in_valid_i) begin
                    len_err_o <= 1; state <= ERR;
                end
                ERR: ;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
