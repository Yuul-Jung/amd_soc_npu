// (추가) UART 실핀 비트파형 8N1 입력 및 TX 재복조 자동 판정.
`timescale 1ns/1ps
module tb_uart_echo;
    localparam integer CPB=868;
    reg clk=0,resetn=0,rxd=1;
    wire txd;
    wire [7:0] decoded;
    wire decoded_valid,fe,ov;
    integer observed=0;
    always #5 clk=~clk;
    basys3_uart_echo_top dut(.clk(clk),.resetn(resetn),.uart_rxd(rxd),.uart_txd(txd));
    uart_rx monitor(.clk(clk),.resetn(resetn),.rx_i(txd),
        .out_data_o(decoded),.out_valid_o(decoded_valid),
        .out_ready_i(1'b1),.framing_error_o(fe),.overrun_o(ov));
    task automatic send_byte(input [7:0] b);
        integer k;
        begin
            @(negedge clk);rxd=0;repeat(CPB)@(negedge clk);
            for(k=0;k<8;k=k+1)begin
                rxd=b[k];repeat(CPB)@(negedge clk);
            end
            rxd=1;repeat(CPB)@(negedge clk);
        end
    endtask
    always @(posedge clk)if(decoded_valid)begin
        if(observed==0 && decoded!==8'h41)$fatal(1,"Echo A mismatch");
        if(observed==1 && decoded!==8'h35)$fatal(1,"Echo 5 mismatch");
        observed=observed+1;
    end
    initial begin
        repeat(8)@(negedge clk);resetn=1;
        send_byte("A");send_byte("5");
        wait(observed==2);
        if(fe||ov)$fatal(1,"Echo framing/overrun");
        $display("UART_ECHO_RTL_SIM_PASS decoded=2");$finish;
    end
    initial begin #2000000;$fatal(1,"UART Echo TIMEOUT");end
endmodule
