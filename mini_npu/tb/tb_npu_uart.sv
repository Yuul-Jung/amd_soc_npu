// CPU/AXI 없이 실제 UART RX 핀→BRAM→DSP 4PE→UART TX 핀 파형 검증.
`timescale 1ns/1ps
module tb_npu_uart;
    localparam integer CPB=868;
    reg clk=0,btnC=1,uart_rxd=1;
    wire uart_txd,dp;
    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an;
    wire [7:0] byte_out;
    wire byte_valid,fe,ov;
    integer c_count=0,ack_count=0,err_count=0,nbytes=0;
    integer k,i,j;
    reg [7:0] chars[0:63];
    reg [8*256-1:0] csvpath;
    integer csv_file;
    always #5 clk=~clk;
    basys3_npu_top dut(.clk(clk),.btnC(btnC),
        .uart_rxd(uart_rxd),.uart_txd(uart_txd),
        .led(led),.seg(seg),.an(an),.dp(dp));
    uart_rx tx_monitor(.clk(clk),.resetn(!btnC),.rx_i(uart_txd),
        .out_data_o(byte_out),.out_valid_o(byte_valid),
        .out_ready_i(1'b1),.framing_error_o(fe),.overrun_o(ov));

    task automatic send_byte(input [7:0] b);
        integer bitno;
        begin
            @(negedge clk);uart_rxd=0;repeat(CPB)@(negedge clk);
            for(bitno=0;bitno<8;bitno=bitno+1)begin
                uart_rxd=b[bitno];repeat(CPB)@(negedge clk);
            end
            uart_rxd=1;repeat(CPB)@(negedge clk);
        end
    endtask
    // Bias 변경 뒤 재분류가 몇 번째 응답인가 (전체 5, +SHORT 1). golden()이 쓰므로 함수보다 먼저 선언한다
    // (xvlog는 선언 전 사용을 오류로 본다: VRFC 10-3380).
    integer edit_idx=5;
    function automatic [7:0] hexchar(input [3:0] value);
        begin
            if(value<10)hexchar="0"+value;
            else hexchar="A"+(value-10);
        end
    endfunction
    function automatic signed [40:0] golden(input integer s,input integer n);
        integer x0,x1,w0,w1;
        begin
            x0=(s&2)?-1:1; x1=(s&1)?-1:1;
            w0=(n&2)?-1:1; w1=(n&1)?-1:1;
            golden=x0*w0+x1*w1;
            if(c_count==edit_idx && n==3)golden=golden+10;
        end
    endfunction
    function automatic [7:0] gold_hex(input signed [40:0] val,input integer pos);
        reg [43:0] ext;
        begin
            ext={{3{val[40]}},val};
            gold_hex=hexchar((ext>>((10-pos)*4))&4'hf);
        end
    endfunction
    // 실제 TX 라인에서 복조한 ASCII HEX를 signed 41-bit 값으로 변환.
    // CSV에 골든값을 복사하면 UART 검증 증거가 되지 않으므로 디코딩값을 기록.
    function automatic signed [40:0] decoded_score(input integer lane);
        integer p;
        reg [7:0] ch;
        reg [3:0] hex;
        reg [43:0] packed_hex;
        begin
            packed_hex=44'd0;
            for(p=0;p<11;p=p+1)begin
                ch=chars[3+lane*12+p];
                if(ch>="0" && ch<="9")hex=ch-"0";
                else if(ch>="A" && ch<="F")hex=ch-"A"+10;
                else $fatal(1,"Non-hex RTL UART output");
                packed_hex=(packed_hex<<4)|hex;
            end
            decoded_score=$signed(packed_hex[40:0]);
        end
    endfunction

    integer scenario,exp_cls;
    // +SHORT: 배선 후 타이밍 시뮬레이션용 짧은 시나리오(분류 1 · Bias 변경 뒤 재분류 1 · ERR 1).
    // 같은 넷리스트·같은 UART 경로를 쓰고 응답 수만 6 → 2로 줄인다 (UART 송신 시간이 대부분).
    reg short_mode=1'b0;
    reg signed [40:0] exp_score;
    always @(posedge clk)if(byte_valid)begin
        if(nbytes>=63)$fatal(1,"TX line overflow");
        if(byte_out!=8'h0a)begin
            chars[nbytes]=byte_out;nbytes=nbytes+1;
        end else begin
            if(nbytes==51 && chars[0]=="C")begin
                scenario=(c_count<4 && c_count!=edit_idx)?c_count:0;
                exp_cls=(c_count==edit_idx)?3:scenario;
                if(chars[1]!==("0"+exp_cls))$fatal(1,"UART CLASS mismatch");
                if(chars[2]!==":")$fatal(1,"Bad UART result header");
                // 응답 점수 구분자와 CR도 실제 비트 복조값으로 검증.
                if(chars[14]!=="," || chars[26]!=="," || chars[38]!=="," ||
                   chars[50]!==8'h0d)$fatal(1,"UART score separators or CR mismatch");
                for(i=0;i<4;i=i+1)begin
                    exp_score=golden(scenario,i);
                    for(j=0;j<11;j=j+1)
                        if(chars[3+i*12+j]!==gold_hex(exp_score,j))
                            $fatal(1,"UART SCORE mismatch case=%0d lane=%0d hex=%0d",c_count,i,j);
                end
                if(led[exp_cls]!==1'b1)$fatal(1,"LED class mismatch");
                // 예상값이 아니라 TX 비트파형에서 실제 수신한 4개 점수 기록.
                $fdisplay(csv_file,"%0d,%0d,%0d,%0d,%0d,%0d",(c_count==edit_idx)?5:c_count,exp_cls,
                    decoded_score(0),decoded_score(1),
                    decoded_score(2),decoded_score(3));
                c_count=c_count+1;
            end else if(nbytes==3 && chars[0]=="O" && chars[1]=="K")begin
                ack_count=ack_count+1;
            end else if(nbytes==4 && chars[0]=="E" && chars[1]=="R" && chars[2]=="R")begin
                err_count=err_count+1;
            end else $fatal(1,"Unexpected UART response len=%0d",nbytes+1);
            nbytes=0;
        end
    end
    initial begin
        csvpath="part03/mini_npu/outputs/predictions.csv";
        if($value$plusargs("CSV=%s",csvpath))begin end
        csv_file=$fopen(csvpath,"w");
        if(csv_file==0)$fatal(1,"Cannot open CSV file");
        $fdisplay(csv_file,"scenario,class,score0,score1,score2,score3");
        short_mode=$test$plusargs("SHORT");
        edit_idx=short_mode?1:5;
        repeat(10)@(negedge clk);btnC=0;
        for(k=0;k<(short_mode?1:4);k=k+1)begin
            send_byte("0"+k);
            wait(c_count==k+1);
        end
        if(!short_mode)begin send_byte("0");wait(c_count==5);end
        // 2-7: Bias3=+10으로 실제 모델 데이터를 변경한 뒤 재추론.
        send_byte("B");send_byte(8'h03);
        send_byte(0);send_byte(0);send_byte(0);send_byte(0);send_byte(10);
        wait(ack_count==1);
        send_byte("R");send_byte(8'h02);
        wait(c_count==edit_idx+1);
        // 미적재 3번째 입력을 요청하면 ERR를 반환해야 한다.
        send_byte("R");send_byte(8'h03);
        wait(err_count==1);
        if(fe||ov)$fatal(1,"UART line framing/overrun");
        $fclose(csv_file);
        $display("INTEGRATED_UART_RTL_SIM_PASS classes=%0d model_edit=1 invalid_length=1%s",c_count,short_mode?" scenario=short":"");
        $finish;
    end
    initial begin #100000000;$fatal(1,"UART NPU end-to-end timeout");end
endmodule
