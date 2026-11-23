// 리셋 동기화기 단위 시험: resetn은 clk 상승 에지에서만 바뀌고(비동기 변화 없음), btnC를 클록과 무관한 시점에
// 눌러도 2~3클록 뒤 걸리고 2~3클록 뒤 풀린다. p01_reset_sync와 npu_reset_controller를 같은 자극으로 본다.
`timescale 1ns/1ps
module tb_p01_reset_sync;
    reg clk=0, btnC=0;
    wire rn_a, rn_b;
    always #5 clk=~clk;
    p01_reset_sync       a(.clk(clk),.btnC(btnC),.resetn(rn_a));
    npu_reset_controller b(.clk(clk),.btnC(btnC),.resetn(rn_b));
    integer async_changes=0, k;
    // resetn이 바뀐 시각이 clk 상승 에지(10 ns 격자의 5 ns 지점)가 아니면 비동기 변화다.
    always @(rn_a or rn_b) if($time>0 && ($time%10)!=5) async_changes=async_changes+1;
    task automatic press(input integer t_on, input integer width);
        integer n;
        begin
            #(t_on) btnC=1;
            #1 if(rn_a!==1'b1) $fatal(1,"resetn changed asynchronously on press");
            n=0; while(rn_a!==1'b0 && n<5) begin @(posedge clk); #1 n=n+1; end
            if(rn_a!==1'b0 || n<2 || n>3) $fatal(1,"assert latency=%0d (want 2~3)",n);
            #(width) btnC=0;
            n=0; while(rn_a!==1'b1 && n<5) begin @(posedge clk); #1 n=n+1; end
            if(rn_a!==1'b1 || n<2 || n>3) $fatal(1,"release latency=%0d (want 2~3)",n);
        end
    endtask
    initial begin
        #1 if(rn_a!==1'b0 || rn_b!==1'b0) $fatal(1,"power-up: resetn must start low");
        repeat(4) @(posedge clk); #1
        if(rn_a!==1'b1) $fatal(1,"power-up release failed");
        for(k=0;k<10;k=k+1) press(13+k*3, 37+k*7);    // 클록과 어긋난 시점·길이
        repeat(4) @(posedge clk);
        if(rn_a!==rn_b) $fatal(1,"two reset modules differ");
        if(async_changes!=0) $fatal(1,"async resetn changes=%0d",async_changes);
        $display("RESET_SYNC_PASS presses=10 async_changes=0");
        $finish;
    end
    always @(posedge clk) if(rn_a!==rn_b && $time>20) $fatal(1,"modules differ at %0t",$time);
endmodule
