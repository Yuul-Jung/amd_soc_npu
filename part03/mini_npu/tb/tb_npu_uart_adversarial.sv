// (추가) 11·12장 통합 Top 적대적 UART 시험(실제 RX 핀 구동, TX 핀 복조).
// 잘못된 명령·주소·길이, CR/LF 무시, 응답 전송 중 다음 명령 수신(FIFO 버퍼링),
// 연속 명령 폭주, 응답 전송 중 Reset, 명령 중단(Timeout 부재 관측), Framing error.
`timescale 1ns/1ps
module tb_npu_uart_adversarial;
    localparam integer CPB=868;
    reg clk=0,btnC=1,uart_rxd=1;
    wire uart_txd,dp;
    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an;
    wire [7:0] byte_out;
    wire byte_valid,mfe,mov;
    always #5 clk=~clk;
    basys3_npu_top dut(.clk(clk),.btnC(btnC),.uart_rxd(uart_rxd),.uart_txd(uart_txd),
        .led(led),.seg(seg),.an(an),.dp(dp));
    uart_rx mon(.clk(clk),.resetn(!btnC),.rx_i(uart_txd),
        .out_data_o(byte_out),.out_valid_o(byte_valid),
        .out_ready_i(1'b1),.framing_error_o(mfe),.overrun_o(mov));

    // 응답 기록: kind 1=I 2=OK 3=ERR 4=C(class)
    reg [7:0] chars[0:63];
    integer nbytes=0,nresp=0;
    integer kind[0:255];
    integer cls[0:255];
    integer i,j,k,base;
    function automatic [7:0] hexchar(input [3:0] v);
        hexchar=(v<10)?("0"+v):("A"+(v-10));
    endfunction
    function automatic signed [40:0] golden(input integer s,input integer n);
        integer x0,x1,w0,w1;
        begin
            x0=(s&2)?-1:1;x1=(s&1)?-1:1;w0=(n&2)?-1:1;w1=(n&1)?-1:1;
            golden=x0*w0+x1*w1;
        end
    endfunction
    function automatic [7:0] gold_hex(input signed [40:0] val,input integer pos);
        reg [43:0] ext;
        begin
            ext={{3{val[40]}},val}; // 부호 비트만 3회 확장(44비트 = 11 hex)
            gold_hex=hexchar((ext>>((10-pos)*4))&4'hf);
        end
    endfunction
    always @(posedge clk)if(byte_valid)begin
        if(nbytes>=63)$fatal(1,"TX line overflow");
        if(byte_out!=8'h0a)begin chars[nbytes]=byte_out;nbytes=nbytes+1;end
        else begin
            if(nbytes==2 && chars[0]=="I" && chars[1]==8'h0d)kind[nresp]=1;
            else if(nbytes==3 && chars[0]=="O" && chars[1]=="K" && chars[2]==8'h0d)kind[nresp]=2;
            else if(nbytes==4 && chars[0]=="E" && chars[1]=="R" && chars[2]=="R" &&
                    chars[3]==8'h0d)kind[nresp]=3;
            else if(nbytes==51 && chars[0]=="C" && chars[2]==":" && chars[50]==8'h0d)begin
                kind[nresp]=4;cls[nresp]=chars[1]-"0";
                // 프리셋 표본(Bias=0) 점수는 실제 TX 복조 문자로 비교
                for(i=0;i<4;i=i+1)for(j=0;j<11;j=j+1)
                    if(chars[3+i*12+j]!==gold_hex(golden(cls[nresp],i),j))
                        $fatal(1,"Score mismatch resp=%0d lane=%0d",nresp,i);
            end else $fatal(1,"Malformed UART response len=%0d first=%02h",nbytes,chars[0]);
            nresp=nresp+1;nbytes=0;
        end
    end

    task automatic send_frame(input [7:0] b,input stop_bit);
        integer n;
        begin
            @(negedge clk);uart_rxd=0;repeat(CPB)@(negedge clk);
            for(n=0;n<8;n=n+1)begin uart_rxd=b[n];repeat(CPB)@(negedge clk);end
            uart_rxd=stop_bit;repeat(CPB)@(negedge clk);uart_rxd=1;
        end
    endtask
    task automatic send_byte(input [7:0] b);send_frame(b,1'b1);endtask
    task automatic wait_resp(input integer n);
        integer guard;
        begin
            guard=0;
            while(nresp<n)begin
                @(negedge clk);guard=guard+1;
                if(guard>CPB*10*400)$fatal(1,"Response timeout want=%0d have=%0d",n,nresp);
            end
        end
    endtask
    task automatic expect_kind(input integer idx,input integer kd);
        if(kind[idx]!==kd)$fatal(1,"Response %0d kind=%0d expected %0d",idx,kind[idx],kd);
    endtask
    task automatic expect_err(input integer idx);expect_kind(idx,3);endtask
    task automatic quiet(input integer frames); // frames 바이트 시간 동안 새 응답 없음
        integer before_n;
        begin
            before_n=nresp;repeat(CPB*10*frames)@(negedge clk);
            if(nresp!=before_n || nbytes!=0)$fatal(1,"Unexpected response during quiet");
        end
    endtask
    task automatic press_reset;
        begin
            @(negedge clk);btnC=1;repeat(100)@(negedge clk);btnC=0;
            nbytes=0;repeat(10)@(negedge clk);
        end
    endtask

    initial begin
        repeat(10)@(negedge clk);btnC=0;repeat(10)@(negedge clk);

        // A1 상태 질의 + CR/LF 무시
        send_byte(8'h0d);send_byte(8'h0a);send_byte("S");
        wait_resp(1);expect_kind(0,1);
        quiet(3);
        $display("A1_STATUS_CRLF_IGNORED_PASS");

        // A2 잘못된 opcode
        base=nresp;
        send_byte("Z");wait_resp(base+1);expect_err(base);
        send_byte("x");wait_resp(base+2);expect_err(base+1);
        send_byte(8'hff);wait_resp(base+3);expect_err(base+2);
        send_byte(8'h00);wait_resp(base+4);expect_err(base+3);
        $display("A2_INVALID_OPCODE_ERR_PASS count=4");

        // A3 잘못된 주소·뉴런·길이 + 경계 유효값
        base=nresp;
        send_byte("X");send_byte(64);send_byte(0);send_byte(1);wait_resp(base+1);expect_err(base);
        send_byte("X");send_byte(63);send_byte(0);send_byte(1);wait_resp(base+2);expect_kind(base+1,2);
        send_byte("W");send_byte(4);send_byte(0);send_byte(0);send_byte(1);wait_resp(base+3);expect_err(base+2);
        send_byte("W");send_byte(0);send_byte(64);send_byte(0);send_byte(1);wait_resp(base+4);expect_err(base+3);
        send_byte("W");send_byte(3);send_byte(63);send_byte(0);send_byte(1);wait_resp(base+5);expect_kind(base+4,2);
        send_byte("B");send_byte(4);for(k=0;k<5;k=k+1)send_byte(0);wait_resp(base+6);expect_err(base+5);
        send_byte("R");send_byte(0);wait_resp(base+7);expect_err(base+6);
        send_byte("R");send_byte(65);wait_resp(base+8);expect_err(base+7);
        send_byte("R");send_byte(8'h80);wait_resp(base+9);expect_err(base+8);
        send_byte("R");send_byte(64);wait_resp(base+10);expect_err(base+9); // 미적재 주소
        if(led[15]!==1'b1)$fatal(1,"Error LED15 not latched");
        $display("A3_INVALID_FIELDS_ERR_PASS err=8 ok_boundary=2");

        // A4 응답 전송 중 다음 명령 수신: '0'~'3' 연속 송신(stop-and-wait 위반) -> FIFO 보관, 순서 보존
        base=nresp;
        send_byte("0");send_byte("1");send_byte("2");send_byte("3");
        wait_resp(base+4);
        for(k=0;k<4;k=k+1)begin
            expect_kind(base+k,4);
            if(cls[base+k]!=k)$fatal(1,"A4 class order k=%0d got=%0d",k,cls[base+k]);
        end
        if(dut.ov||dut.fe)$fatal(1,"A4 overrun/framing");
        $display("A4_COMMAND_DURING_RESPONSE_PASS ordered=4");

        // A5 'S' 20개 연속 폭주: 응답 3바이트 > 입력 1바이트, FIFO 내에서 무손실
        base=nresp;
        for(k=0;k<20;k=k+1)send_byte("S");
        wait_resp(base+20);
        for(k=0;k<20;k=k+1)expect_kind(base+k,1);
        if(dut.ov)$fatal(1,"A5 overrun within FIFO capacity");
        $display("A5_BURST_20_STATUS_NO_LOSS_PASS");

        // A6 응답 송신 중 Reset: TX 즉시 idle, 잔류 응답 없음, 이후 정상
        send_byte("1");
        while(nbytes<10)@(negedge clk);
        press_reset;
        if(uart_txd!==1'b1)$fatal(1,"A6 TX not idle after reset");
        base=nresp;
        quiet(60); // 남은 42바이트가 새어 나오면 실패
        send_byte("S");wait_resp(base+1);expect_kind(base,1);
        send_byte("2");wait_resp(base+2);expect_kind(base+1,4);
        if(cls[base+1]!=2)$fatal(1,"A6 class after reset");
        if(led[15]!==1'b0)$fatal(1,"A6 error LED not cleared by reset");
        $display("A6_RESET_DURING_RESPONSE_PASS");

        // A7 명령 중단(Timeout 관측): 'B'+2바이트 후 중단 -> 응답 없음,
        //    다음 'S'는 페이로드로 소비됨(설계에 RX Timeout 없음). Reset으로만 복구.
        base=nresp;
        send_byte("B");send_byte(1);send_byte(0);
        quiet(50);
        send_byte("S");
        quiet(10);
        if(dut.commands.state!==3'd1)$fatal(1,"A7 expected controller stuck in RECV");
        press_reset;
        send_byte("S");wait_resp(base+1);expect_kind(base,1);
        $display("A7_ABORTED_COMMAND_NO_TIMEOUT_OBSERVED recovered_by_reset=1");

        // A8 Framing error: stop=0 바이트 무시, fe/LED15 래치, 명령 처리 지속
        base=nresp;
        send_frame("S",1'b0);
        quiet(3);
        if(dut.fe!==1'b1 || led[15]!==1'b1)$fatal(1,"A8 framing error not latched");
        send_byte("S");wait_resp(base+1);expect_kind(base,1);
        press_reset;
        $display("A8_FRAMING_ERROR_PASS");

        if(mfe||mov)$fatal(1,"TX monitor framing/overrun");
        $display("NPU_UART_ADVERSARIAL_SIM_PASS tests=8 responses=%0d",nresp);
        $finish;
    end
    initial begin #400000000;$fatal(1,"Adversarial TB global timeout");end
endmodule
