// 1장 MAC 묶음: 1-2·1-3·1-4 서브젝트의 세 코어에 같은 입력을 넣고, sw로 고른 코어의 결과만 내보낸다.
// STAGE = 지금까지 끝낸 서브젝트 수 (1~4). 아직 만들지 않은 코어는 넣지 않고, 그 sw 값은 앞 코어로 대신한다.
//   sel 0 = 1-2  mac_core                  지연 1클록
//   sel 1 = 1-3 dsp_multiplier + 누산 지연 2클록 (곱 레지스터 1 + 누산 레지스터 1)
//   sel 2·3 = 1-4 mac_pipeline_core 지연 2클록
// 세 코어가 같은 입력을 늘 함께 받으므로 누산값은 항상 같다. sw를 바꿔도 값은 그대로이고 지연만 달라진다.
`timescale 1ns/1ps
`default_nettype none
module p01_mac_bank #(
    parameter integer DATA_WIDTH = 16,
    parameter integer ACC_WIDTH  = 40,
    parameter integer STAGE      = 4
) (
    input  wire                         clk,
    input  wire                         resetn,
    input  wire                         clear_i,
    input  wire                         valid_i,
    input  wire signed [DATA_WIDTH-1:0] a_i,
    input  wire signed [DATA_WIDTH-1:0] b_i,
    input  wire [1:0]                   sel_i,      // 보드 스위치 (비동기 입력)
    output reg  signed [ACC_WIDTH-1:0]  acc_o,
    output reg                          valid_o,
    output wire [1:0]                   sel_o       // 동기화한 선택값
);
    localparam integer PRODUCT_WIDTH = 2 * DATA_WIDTH;

    // 스위치 2FF 동기화
    reg [1:0] sel_meta, sel_sync;
    always @(posedge clk) begin
        if (!resetn) begin
            sel_meta <= 2'd0;
            sel_sync <= 2'd0;
        end else begin
            sel_meta <= sel_i;
            sel_sync <= sel_meta;
        end
    end
    assign sel_o = sel_sync;

    // 1-2: mac_core
    wire signed [ACC_WIDTH-1:0] acc_mac;
    wire                        valid_mac;
    generate if (STAGE >= 2) begin : g_mac
        mac_core #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_mac (
            .clk(clk), .resetn(resetn), .clear_i(clear_i), .valid_i(valid_i),
            .a_i(a_i), .b_i(b_i), .acc_o(acc_mac), .valid_o(valid_mac));
    end else begin : g_no_mac
        assign acc_mac = {ACC_WIDTH{1'b0}};
        assign valid_mac = 1'b0;
    end endgenerate

    // 1-3: dsp_multiplier + 누산 레지스터
    wire signed [ACC_WIDTH-1:0] acc_dsp;
    wire                        valid_dsp;
    generate if (STAGE >= 3) begin : g_dsp
        wire signed [PRODUCT_WIDTH-1:0] prod_dsp;
        wire                            prod_valid_dsp;
        dsp_multiplier #(.A_WIDTH(DATA_WIDTH), .B_WIDTH(DATA_WIDTH)) u_dsp (
            .clk(clk), .resetn(resetn), .clear_i(clear_i), .valid_i(valid_i),
            .a_i(a_i), .b_i(b_i), .product_o(prod_dsp), .valid_o(prod_valid_dsp));

        reg signed [ACC_WIDTH-1:0] acc_q;
        reg                        valid_q;
        wire signed [ACC_WIDTH-1:0] prod_ext = {{(ACC_WIDTH-PRODUCT_WIDTH){prod_dsp[PRODUCT_WIDTH-1]}}, prod_dsp};
        always @(posedge clk) begin
            if (!resetn || clear_i) begin
                acc_q   <= {ACC_WIDTH{1'b0}};
                valid_q <= 1'b0;
            end else begin
                valid_q <= prod_valid_dsp;
                if (prod_valid_dsp)
                    acc_q <= acc_q + prod_ext;
            end
        end
        assign acc_dsp = acc_q;
        assign valid_dsp = valid_q;
    end else begin : g_no_dsp
        assign acc_dsp = acc_mac;              // 아직 없음: 1-2 코어로 대신
        assign valid_dsp = valid_mac;
    end endgenerate

    // 1-4: mac_pipeline_core
    wire signed [ACC_WIDTH-1:0] acc_pipe;
    wire                        valid_pipe;
    generate if (STAGE >= 4) begin : g_pipe
        mac_pipeline_core #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_pipe (
            .clk(clk), .resetn(resetn), .clear_i(clear_i), .valid_i(valid_i),
            .a_i(a_i), .b_i(b_i), .acc_o(acc_pipe), .valid_o(valid_pipe));
    end else begin : g_no_pipe
        assign acc_pipe = acc_dsp;             // 아직 없음: 앞 코어로 대신
        assign valid_pipe = valid_dsp;
    end endgenerate

    // 고른 코어의 결과
    always @(*) begin
        case (sel_sync)
            2'd0:    begin acc_o = acc_mac;  valid_o = valid_mac;  end
            2'd1:    begin acc_o = acc_dsp;  valid_o = valid_dsp;  end
            default: begin acc_o = acc_pipe; valid_o = valid_pipe; end
        endcase
    end
    initial begin
        if (STAGE < 1 || STAGE > 4)
            $fatal(1, "STAGE must be 1..4");
    end
endmodule
`default_nettype wire
