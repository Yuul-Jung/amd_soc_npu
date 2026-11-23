// UART 명령·모델 적재·추론 결과 직렬화 Controller.
// 단일 문자 '0'~'3'은 2원소 고정 표본. 2-7 바이너리 명령은 아래 README 참조.
// 요청/응답은 stop-and-wait: ACK 또는 결과 LF까지 다음 명령 송신 금지.
module uart_npu_command_controller(
    input wire clk,resetn,
    input wire [7:0] rx_data_i,
    input wire rx_valid_i,
    output wire rx_ready_o,
    output wire [7:0] tx_data_o,
    output wire tx_valid_o,
    input wire tx_ready_i,
    output wire npu_start_o,
    output wire [6:0] npu_length_o,
    output wire x_wr_en_o,w_wr_en_o,b_wr_en_o,
    output reg [5:0] wr_addr_o,
    output reg [1:0] neuron_o,
    output reg signed [15:0] wr_data_o,
    output reg signed [39:0] bias_data_o,
    input wire npu_load_ready_i,
    input wire npu_busy_i,npu_done_i,npu_error_i,
    input wire [1:0] npu_class_i,
    input wire [163:0] npu_scores_i,
    output reg protocol_error_o
);
    localparam [2:0] IDLE=0,RECV=1,APPLY=2,PRESET=3,RUN=4,WAIT_NPU=5,SEND=6;
    reg [2:0] state;
    reg [7:0] opcode;
    reg [7:0] payload[0:5];
    reg [2:0] recv_index,expected_bytes;
    reg [1:0] sample_id;
    reg [3:0] preset_index;
    reg [6:0] run_length;
    reg [7:0] response[0:63];
    reg [5:0] send_length,send_index;
    integer i,j;

    assign rx_ready_o=resetn&&(state==IDLE||state==RECV);
    assign tx_valid_o=(state==SEND)&&(send_index<send_length);
    assign tx_data_o=response[send_index];
    assign npu_start_o=(state==RUN);
    assign npu_length_o=run_length;

    // 필드 형식 거부. 주소 0~63, 뉴런 0~3, 길이 1~64.
    wire accepted_fields =
        (opcode=="X" && payload[0]<64) ||
        (opcode=="W" && payload[0]<4 && payload[1]<64) ||
        (opcode=="B" && payload[0]<4) ||
        (opcode=="R" && payload[0]>=1 && payload[0]<=64);

    assign x_wr_en_o=(state==PRESET && preset_index<2 && npu_load_ready_i) ||
        (state==APPLY && opcode=="X" && accepted_fields && npu_load_ready_i);
    assign w_wr_en_o=(state==PRESET && preset_index>=2 && preset_index<10 &&
                      npu_load_ready_i) ||
        (state==APPLY && opcode=="W" && accepted_fields && npu_load_ready_i);
    assign b_wr_en_o=(state==PRESET && preset_index>=10 && npu_load_ready_i) ||
        (state==APPLY && opcode=="B" && accepted_fields && npu_load_ready_i);

    always @*begin
        wr_addr_o=0;neuron_o=0;wr_data_o=0;bias_data_o=0;
        if(state==PRESET)begin
            if(preset_index<2)begin
                wr_addr_o={2'b00,preset_index};
                // X0=(+1,+1), X1=(+1,-1), X2=(-1,+1), X3=(-1,-1)
                wr_data_o=((preset_index==0 && sample_id[1]) ||
                    (preset_index==1 && sample_id[0])) ? -16'sd1 : 16'sd1;
            end else if(preset_index<10)begin
                neuron_o=(preset_index-2)>>1;
                wr_addr_o=(preset_index-2)&1;
                wr_data_o=((neuron_o[1] && wr_addr_o==0) ||
                    (neuron_o[0] && wr_addr_o==1)) ? -16'sd1 : 16'sd1;
            end else neuron_o=preset_index-10;
        end else if(state==APPLY)begin
            case(opcode)
                "X":begin wr_addr_o=payload[0][5:0];wr_data_o={payload[1],payload[2]};end
                "W":begin neuron_o=payload[0][1:0];wr_addr_o=payload[1][5:0];
                    wr_data_o={payload[2],payload[3]};end
                "B":begin neuron_o=payload[0][1:0];
                    bias_data_o={payload[1],payload[2],payload[3],payload[4],payload[5]};end
                default:begin end
            endcase
        end
    end

    function [7:0] hexdigit(input [3:0] n);
        begin
            hexdigit=(n<10) ? (8'h30+n) : (8'h41+(n-10));
        end
    endfunction
    function [7:0] score_hex(input [40:0] score,input integer position);
        reg [43:0] ext;
        reg [3:0] nib;
        begin
            ext={{3{score[40]}},score};
            nib=(ext>>((10-position)*4)) & 4'hf;
            score_hex=hexdigit(nib);
        end
    endfunction

    always @(posedge clk)begin
        if(!resetn)begin
            state<=IDLE;opcode<=0;recv_index<=0;expected_bytes<=0;
            sample_id<=0;preset_index<=0;run_length<=2;
            send_length<=0;send_index<=0;protocol_error_o<=0;
        end else begin
            protocol_error_o<=0;
            case(state)
                IDLE:if(rx_valid_i && rx_ready_o)begin
                    if(rx_data_i>="0" && rx_data_i<="3")begin
                        sample_id<=rx_data_i[1:0];preset_index<=0;run_length<=2;
                        state<=PRESET;
                    end else if(rx_data_i=="X"||rx_data_i=="W"||
                        rx_data_i=="B"||rx_data_i=="R")begin
                        opcode<=rx_data_i;recv_index<=0;
                        case(rx_data_i)
                            "X":expected_bytes<=3;
                            "W":expected_bytes<=4;
                            "B":expected_bytes<=6;
                            default:expected_bytes<=1;
                        endcase
                        state<=RECV;
                    end else if(rx_data_i=="S")begin
                        response[0]<="I";response[1]<=8'h0d;response[2]<=8'h0a;
                        send_index<=0;send_length<=3;state<=SEND;
                    end else if(rx_data_i!=8'h0d && rx_data_i!=8'h0a)begin
                        protocol_error_o<=1;
                        response[0]<="E";response[1]<="R";response[2]<="R";
                        response[3]<=8'h0d;response[4]<=8'h0a;
                        send_index<=0;send_length<=5;state<=SEND;
                    end
                end
                RECV:if(rx_valid_i && rx_ready_o)begin
                    payload[recv_index]<=rx_data_i;
                    if(recv_index+3'd1==expected_bytes)state<=APPLY;
                    else recv_index<=recv_index+1'b1;
                end
                APPLY:begin
                    if(!accepted_fields || !npu_load_ready_i)begin
                        protocol_error_o<=1;
                        response[0]<="E";response[1]<="R";response[2]<="R";
                        response[3]<=8'h0d;response[4]<=8'h0a;
                        send_index<=0;send_length<=5;state<=SEND;
                    end else if(opcode=="R")begin
                        run_length<=payload[0][6:0];state<=RUN;
                    end else begin
                        response[0]<="O";response[1]<="K";
                        response[2]<=8'h0d;response[3]<=8'h0a;
                        send_index<=0;send_length<=4;state<=SEND;
                    end
                end
                PRESET:if(npu_load_ready_i)begin
                    if(preset_index==13)state<=RUN;
                    else preset_index<=preset_index+1'b1;
                end
                RUN:state<=WAIT_NPU;
                WAIT_NPU:begin
                    if(npu_error_i)begin
                        protocol_error_o<=1;
                        response[0]<="E";response[1]<="R";response[2]<="R";
                        response[3]<=8'h0d;response[4]<=8'h0a;
                        send_index<=0;send_length<=5;state<=SEND;
                    end else if(npu_done_i)begin
                        // Cx: + 4 signed 41bit scores each in 11 hex chars + CRLF.
                        response[0]<="C";response[1]<=8'h30+{6'b0,npu_class_i};
                        response[2]<=":";
                        for(i=0;i<4;i=i+1)begin
                            for(j=0;j<11;j=j+1)
                                response[3+i*12+j]<=score_hex(
                                    npu_scores_i[i*41+:41],j);
                            if(i<3)response[14+i*12]<=",";
                        end
                        response[50]<=8'h0d;response[51]<=8'h0a;
                        send_index<=0;send_length<=52;state<=SEND;
                    end
                end
                SEND:if(tx_valid_o && tx_ready_i)begin
                    if(send_index+6'd1==send_length)begin
                        send_index<=0;state<=IDLE;
                    end else send_index<=send_index+1'b1;
                end
                default:begin state<=IDLE;protocol_error_o<=1;end
            endcase
        end
    end
endmodule
