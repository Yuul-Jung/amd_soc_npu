// (추가) uart_core 16바이트 RX/TX FIFO 적대적 경계 시험.
// Empty/Full, 동시 Push/Pop, Ready/Valid, Reset 초기화, 연속 수신 손실, Overrun, Framing, 전송 중단.
// 실제 직렬 비트파형으로 RX를 구동하고 TX 핀을 독립 uart_rx로 복조해 순서·값을 비교한다.
`timescale 1ns/1ps
module tb_uart_core_fifo;
    localparam integer CLK_HZ=1000000,BAUD=100000;
    localparam integer CPB=(CLK_HZ+BAUD/2)/BAUD; // 10 clocks/bit: 시뮬레이션 단축
    reg clk=0,resetn=0,rxd=1;
    wire txd;
    wire [7:0] rx_data;
    wire rx_valid;
    reg rx_ready=0;
    reg [7:0] tx_data=0;
    reg tx_valid=0;
    wire tx_ready;
    wire fe,ov;
    reg mon_resetn=0;
    wire [7:0] mon_data;
    wire mon_valid,mon_fe,mon_ov;
    always #5 clk=~clk;

    uart_core #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) dut(.clk(clk),.resetn(resetn),
        .uart_rxd_i(rxd),.uart_txd_o(txd),
        .rx_out_data(rx_data),.rx_out_valid(rx_valid),.rx_out_ready(rx_ready),
        .tx_in_data(tx_data),.tx_in_valid(tx_valid),.tx_in_ready(tx_ready),
        .rx_framing_error_o(fe),.rx_overrun_o(ov));
    uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) mon(.clk(clk),.resetn(mon_resetn),
        .rx_i(txd),.out_data_o(mon_data),.out_valid_o(mon_valid),
        .out_ready_i(1'b1),.framing_error_o(mon_fe),.overrun_o(mon_ov));

    // ---------------- scoreboards ----------------
    reg [7:0] txq[0:1023];
    integer tx_head=0,tx_tail=0;
    reg [7:0] rxq[0:1023];
    integer rx_head=0,rx_tail=0;
    integer tx_accepted=0,rx_delivered=0;
    // coverage
    integer cov_rx_full=0,cov_tx_full=0,cov_rx_full_pushpop=0,cov_tx_full_pushpop=0;
    integer cov_rx_pushpop=0,cov_tx_pushpop=0,cov_rx_empty_pop_attempt=0;
    integer cov_tx_stall=0,cov_rx_hold=0;
    reg [7:0] prev_rx_data;
    reg prev_rx_stall=0;
    reg [7:0] prev_tx_data;
    reg prev_tx_stall=0;

    always @(posedge clk)begin
        // TX handshake: 수락된 바이트만 기대 큐에 넣는다.
        if(tx_valid && tx_ready)begin
            txq[tx_tail%1024]=tx_data;tx_tail=tx_tail+1;tx_accepted=tx_accepted+1;
        end
        // RX handshake: 실제 수신 순서 비교
        if(rx_valid && rx_ready)begin
            if(rx_head==rx_tail)$fatal(1,"RX unexpected byte %02h",rx_data);
            if(rx_data!==rxq[rx_head%1024])
                $fatal(1,"RX order/data mismatch idx=%0d got=%02h exp=%02h",
                    rx_head,rx_data,rxq[rx_head%1024]);
            rx_head=rx_head+1;rx_delivered=rx_delivered+1;
        end
        // TX 핀 복조 비교
        if(mon_valid)begin
            if(tx_head==tx_tail)$fatal(1,"TX unexpected byte on pin %02h",mon_data);
            if(mon_data!==txq[tx_head%1024])
                $fatal(1,"TX order/data mismatch idx=%0d got=%02h exp=%02h",
                    tx_head,mon_data,txq[tx_head%1024]);
            tx_head=tx_head+1;
        end
        if(mon_fe)$fatal(1,"TX pin framing error");
        // Ready/Valid 규칙: valid && !ready 동안 rx_out_data 유지
        if(prev_rx_stall && rx_data!==prev_rx_data)$fatal(1,"RX data changed while stalled");
        prev_rx_stall=rx_valid && !rx_ready;prev_rx_data=rx_data;
        if(prev_tx_stall && (!tx_valid || tx_data!==prev_tx_data))
            $fatal(1,"TB violated TX valid/data hold");
        prev_tx_stall=tx_valid && !tx_ready;prev_tx_data=tx_data;
        // FIFO 내부 불변식
        if(resetn)begin
            if(dut.rx_count>16 || dut.tx_count>16)$fatal(1,"FIFO count overflow");
            if(dut.rx_count!=0 && dut.rx_count!=16 &&
               dut.rx_count!=((dut.rx_wptr-dut.rx_rptr)&4'hf))$fatal(1,"RX ptr/count mismatch");
            if(dut.tx_count!=0 && dut.tx_count!=16 &&
               dut.tx_count!=((dut.tx_wptr-dut.tx_rptr)&4'hf))$fatal(1,"TX ptr/count mismatch");
            if((dut.rx_count==0 || dut.rx_count==16) && dut.rx_wptr!=dut.rx_rptr)
                $fatal(1,"RX empty/full pointer mismatch");
            if((dut.tx_count==0 || dut.tx_count==16) && dut.tx_wptr!=dut.tx_rptr)
                $fatal(1,"TX empty/full pointer mismatch");
            if(rx_valid!==(dut.rx_count!=0))$fatal(1,"RX valid != !empty");
            if(dut.tx_count==16 && !dut.tx_pop && tx_ready)$fatal(1,"TX ready while full");
            if(dut.rx_count==16 && dut.rx_push && !dut.rx_pop)$fatal(1,"RX push while full");
            // coverage
            if(dut.rx_count==16)cov_rx_full=cov_rx_full+1;
            if(dut.tx_count==16)cov_tx_full=cov_tx_full+1;
            if(dut.rx_push && dut.rx_pop)cov_rx_pushpop=cov_rx_pushpop+1;
            if(dut.tx_push && dut.tx_pop)cov_tx_pushpop=cov_tx_pushpop+1;
            if(dut.rx_count==16 && dut.rx_push && dut.rx_pop)cov_rx_full_pushpop=cov_rx_full_pushpop+1;
            if(dut.tx_count==16 && dut.tx_push && dut.tx_pop)cov_tx_full_pushpop=cov_tx_full_pushpop+1;
            if(dut.rx_count==0 && rx_ready)cov_rx_empty_pop_attempt=cov_rx_empty_pop_attempt+1;
            if(tx_valid && !tx_ready)cov_tx_stall=cov_tx_stall+1;
            if(rx_valid && !rx_ready)cov_rx_hold=cov_rx_hold+1;
        end
    end

    // ---------------- serial drivers ----------------
    task automatic send_frame(input [7:0] b,input stop_bit);
        integer k;
        begin
            @(negedge clk);rxd=0;repeat(CPB)@(negedge clk);
            for(k=0;k<8;k=k+1)begin rxd=b[k];repeat(CPB)@(negedge clk);end
            rxd=stop_bit;repeat(CPB)@(negedge clk);
            rxd=1;
        end
    endtask
    task automatic send_byte(input [7:0] b);
        begin rxq[rx_tail%1024]=b;rx_tail=rx_tail+1;send_frame(b,1'b1);end
    endtask
    task automatic send_byte_dropped(input [7:0] b); // 기대 큐에 넣지 않음(overrun 대상)
        begin send_frame(b,1'b1);end
    endtask
    task automatic do_reset(input integer cycles);
        begin
            @(negedge clk);resetn=0;mon_resetn=0;rx_ready=0;tx_valid=0;
            repeat(2)@(negedge clk);
            if(tx_ready!==1'b0)$fatal(1,"tx_ready must be low in reset");
            repeat(cycles)@(negedge clk);
            if(txd!==1'b1)$fatal(1,"TXD not idle in reset");
            if(dut.rx_count!==0 || dut.tx_count!==0)$fatal(1,"FIFO count not cleared");
            if(dut.rx_wptr!==0 || dut.rx_rptr!==0 || dut.tx_wptr!==0 || dut.tx_rptr!==0)
                $fatal(1,"FIFO pointers not cleared");
            if(rx_valid!==1'b0 || fe!==1'b0 || ov!==1'b0)$fatal(1,"status not cleared");
            if(dut.rx.out_valid_o!==1'b0)$fatal(1,"PHY RX hold not cleared");
            // 스코어보드도 초기화(리셋으로 버린 데이터는 기대하지 않는다)
            tx_head=tx_tail;rx_head=rx_tail;
            resetn=1;mon_resetn=1;
            @(negedge clk);
            if(tx_ready!==1'b1)$fatal(1,"tx_ready must rise after reset");
        end
    endtask
    // TX push: negedge에서 데이터 제시, ready를 기다려 다음 posedge에서 수락.
    task automatic tx_push(input [7:0] b);
        begin
            tx_data=b;tx_valid=1;
            while(!tx_ready)@(negedge clk);
            @(negedge clk);
        end
    endtask
    task automatic wait_tx_drain;
        integer guard;
        begin
            guard=0;
            while(tx_head!=tx_tail || dut.tx_count!=0 || dut.tx.sending)begin
                @(negedge clk);guard=guard+1;
                if(guard>CPB*10*80)$fatal(1,"TX drain timeout");
            end
            repeat(CPB*2)@(negedge clk);
        end
    endtask
    task automatic wait_rx_drain;
        integer guard;
        begin
            guard=0;
            while(rx_head!=rx_tail)begin
                @(negedge clk);guard=guard+1;
                if(guard>CPB*10*80)$fatal(1,"RX drain timeout head=%0d tail=%0d",rx_head,rx_tail);
            end
        end
    endtask

    integer i,first_stall_accept,seed,t;
    reg rand_ready_en=0;
    always @(negedge clk)if(rand_ready_en)rx_ready=($random(seed)&1);

    initial begin
        seed=12345;
        // ===== T1 Reset 상태 =====
        repeat(5)@(negedge clk);
        if(tx_ready!==1'b0)$fatal(1,"T1 tx_ready high during reset");
        if(txd!==1'b1)$fatal(1,"T1 txd not idle");
        do_reset(3);
        if(rx_valid!==0)$fatal(1,"T1 rx_valid after reset");
        $display("T1_RESET_DEFAULTS_PASS");

        // ===== T2 TX Empty->Full, 정확한 용량(PHY 1 + FIFO 16), 동시 Push/Pop =====
        @(negedge clk);
        first_stall_accept=-1;
        for(i=0;i<40;i=i+1)begin
            tx_data=8'h30+i;tx_valid=1;
            if(!tx_ready && first_stall_accept<0)first_stall_accept=tx_accepted;
            while(!tx_ready)@(negedge clk);
            @(negedge clk);
        end
        tx_valid=0;
        if(first_stall_accept!=17)
            $fatal(1,"T2 TX capacity expected 17 (PHY1+FIFO16) got %0d",first_stall_accept);
        wait_tx_drain;
        if(tx_accepted!=40)$fatal(1,"T2 TX accepted count %0d",tx_accepted);
        if(cov_tx_full==0 || cov_tx_full_pushpop==0)
            $fatal(1,"T2 TX full / full push+pop not exercised");
        $display("T2_TX_FULL_CAPACITY_PASS capacity=%0d bytes=40 full_pushpop=%0d",
            first_stall_accept,cov_tx_full_pushpop);

        // ===== T3 valid=0일 때 데이터 변동은 무시 =====
        for(i=0;i<200;i=i+1)begin tx_data=$random(seed);tx_valid=0;@(negedge clk);end
        if(dut.tx_count!==0 || dut.tx.sending)$fatal(1,"T3 TX pushed without valid");
        // valid=0 상태에서 rx_ready만 들어도 Empty pop 없음
        rx_ready=1;repeat(50)@(negedge clk);rx_ready=0;
        if(dut.rx_count!==0 || dut.rx_rptr!==dut.rx_wptr)$fatal(1,"T3 RX pop on empty");
        $display("T3_NO_VALID_NO_TRANSFER_PASS");

        // ===== T4 RX Full: ready=0으로 17바이트(FIFO16+PHY1) 무손실 보관 후 순서대로 배출 =====
        rx_ready=0;
        for(i=0;i<17;i=i+1)send_byte(8'hA0+i);
        repeat(CPB*2)@(negedge clk);
        if(dut.rx_count!==16)$fatal(1,"T4 RX count %0d expected 16",dut.rx_count);
        if(dut.rx.out_valid_o!==1'b1)$fatal(1,"T4 PHY hold byte missing");
        if(ov||fe)$fatal(1,"T4 unexpected overrun/framing");
        if(rx_data!==8'hA0)$fatal(1,"T4 head data %02h",rx_data);
        rx_ready=1;wait_rx_drain;rx_ready=0;
        if(cov_rx_full_pushpop==0)$fatal(1,"T4 RX full push+pop not exercised");
        $display("T4_RX_FULL_17_NO_LOSS_PASS full_pushpop=%0d",cov_rx_full_pushpop);

        // ===== T5 RX Overrun: 18번째 바이트만 손실, 앞 17바이트 보존, ov 래치 =====
        for(i=0;i<17;i=i+1)send_byte(8'h50+i);
        send_byte_dropped(8'hEE);
        repeat(CPB*2)@(negedge clk);
        if(ov!==1'b1)$fatal(1,"T5 overrun not flagged");
        rx_ready=1;wait_rx_drain;repeat(CPB)@(negedge clk);rx_ready=0;
        if(rx_valid)$fatal(1,"T5 extra byte after drain (dropped byte leaked)");
        do_reset(4); // ov는 Reset으로만 해제
        $display("T5_RX_OVERRUN_18TH_DROPPED_PASS");

        // ===== T6 연속 수신 + 무작위 backpressure: 손실 없음 =====
        rand_ready_en=1;
        for(i=0;i<64;i=i+1)send_byte($random(seed));
        wait_rx_drain;rand_ready_en=0;rx_ready=0;
        if(ov||fe)$fatal(1,"T6 overrun/framing under random ready");
        if(cov_rx_pushpop==0)$fatal(1,"T6 RX simultaneous push/pop not exercised");
        $display("T6_RX_STREAM_RANDOM_READY_PASS bytes=64 pushpop=%0d",cov_rx_pushpop);

        // ===== T7 동시 RX 수신 + TX 송신(Full duplex) =====
        fork
            begin for(i=0;i<20;i=i+1)send_byte(8'hC0+i);end
            begin : txside
                integer m;
                @(negedge clk);
                for(m=0;m<20;m=m+1)tx_push(8'h70+m);
                tx_valid=0;
            end
            begin rx_ready=1;end
        join
        wait_rx_drain;wait_tx_drain;rx_ready=0;
        if(ov||fe)$fatal(1,"T7 full duplex error");
        $display("T7_FULL_DUPLEX_PASS rx=20 tx=20");

        // ===== T8 Framing error: stop=0 바이트는 FIFO에 넣지 않고 fe 래치 =====
        send_frame(8'h5A,1'b0);
        repeat(CPB*3)@(negedge clk);
        if(fe!==1'b1)$fatal(1,"T8 framing error not flagged");
        if(rx_valid || dut.rx_count!=0)$fatal(1,"T8 bad frame was pushed");
        send_byte(8'h3C);rx_ready=1;wait_rx_drain;rx_ready=0;
        do_reset(4);
        $display("T8_FRAMING_ERROR_PASS");

        // ===== T9 TX 전송 중 Reset: FIFO/PHY 초기화, 이후 잔류 데이터 없음 =====
        @(negedge clk);
        for(i=0;i<12;i=i+1)tx_push(8'h10+i);
        tx_valid=0;
        repeat(CPB*10+CPB*4)@(negedge clk); // 2번째 프레임 중간
        if(!dut.tx.sending || dut.tx_count==0)$fatal(1,"T9 precondition");
        do_reset(5);
        @(negedge clk);
        for(i=0;i<3;i=i+1)tx_push(8'hD0+i);
        tx_valid=0;
        wait_tx_drain;
        $display("T9_RESET_DURING_TX_FLUSH_PASS");

        // ===== T10 RX 프레임 중간 Reset + 송신 중단: 반쪽 바이트 미적재 =====
        fork
            begin : partial
                @(negedge clk);rxd=0;repeat(CPB)@(negedge clk);
                for(t=0;t<4;t=t+1)begin rxd=0;repeat(CPB)@(negedge clk);end
                rxd=1; // 송신 중단(라인 idle)
            end
            begin repeat(CPB*3)@(negedge clk);@(negedge clk);resetn=0;mon_resetn=0;end
        join
        repeat(CPB*12)@(negedge clk);
        if(dut.rx_count!==0 || dut.rx.out_valid_o!==0)$fatal(1,"T10 partial frame stored");
        resetn=1;mon_resetn=1;
        repeat(CPB*12)@(negedge clk);
        if(rx_valid || fe || ov)$fatal(1,"T10 garbage after reset");
        send_byte(8'h99);rx_ready=1;wait_rx_drain;rx_ready=0;
        $display("T10_RESET_DURING_RX_PASS");

        // ===== T11 (관측) Reset 없는 송신 중단: UART 특성상 남은 비트가 1로 읽힌다 =====
        @(negedge clk);rxd=0;repeat(CPB)@(negedge clk);
        for(t=0;t<4;t=t+1)begin rxd=0;repeat(CPB)@(negedge clk);end
        rxd=1;
        rxq[rx_tail%1024]=8'hF0;rx_tail=rx_tail+1; // 하위 4비트 0, 상위 4비트 idle=1
        repeat(CPB*8)@(negedge clk);
        rx_ready=1;wait_rx_drain;rx_ready=0;
        if(fe)$fatal(1,"T11 unexpected framing");
        $display("T11_ABORTED_FRAME_OBSERVED byte=F0 (8N1 has no truncation detection)");

        if(cov_rx_hold==0 || cov_tx_stall==0 || cov_rx_empty_pop_attempt==0)
            $fatal(1,"coverage hole hold=%0d stall=%0d empty=%0d",
                cov_rx_hold,cov_tx_stall,cov_rx_empty_pop_attempt);
        $display("COVERAGE rx_full=%0d tx_full=%0d rx_full_pushpop=%0d tx_full_pushpop=%0d rx_pushpop=%0d tx_pushpop=%0d rx_hold=%0d tx_stall=%0d",
            cov_rx_full,cov_tx_full,cov_rx_full_pushpop,cov_tx_full_pushpop,
            cov_rx_pushpop,cov_tx_pushpop,cov_rx_hold,cov_tx_stall);
        $display("UART_FIFO_ADVERSARIAL_SIM_PASS tests=11");
        $finish;
    end
    initial begin #50000000;$fatal(1,"UART FIFO TB TIMEOUT");end
endmodule
