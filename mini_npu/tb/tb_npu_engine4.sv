// (추가) 실제 DSP 등록 곱→BRAM→4PE 누적 NPU 정수 독립 검증.
`timescale 1ns/1ps
module tb_npu_engine4;
    reg clk=0,resetn=0,start=0,xwe=0,wwe=0,bwe=0;
    reg [6:0] len=2;
    reg [5:0] addr=0;
    reg [1:0] neuron=0;
    reg signed [15:0] data=0;
    reg signed [39:0] bias=0;
    wire load_ready,busy,done,error;
    wire [1:0] cls;
    wire [163:0] scores;
    integer sample,k,n;
    always #5 clk=~clk;
    npu_engine4 dut(.clk(clk),.resetn(resetn),.start_i(start),.length_i(len),
        .x_wr_en(xwe),.w_wr_en(wwe),.b_wr_en(bwe),.addr_i(addr),
        .neuron_i(neuron),.data_i(data),.bias_i(bias),
        .load_ready_o(load_ready),.busy_o(busy),.done_o(done),.error_o(error),
        .class_o(cls),.scores_o(scores));
    task automatic write_x(input [5:0] a,input signed [15:0] v);
        begin @(negedge clk);xwe=1;addr=a;data=v;
              @(negedge clk);xwe=0;end
    endtask
    task automatic write_w(input [1:0] nn,input [5:0] a,input signed [15:0] v);
        begin @(negedge clk);wwe=1;neuron=nn;addr=a;data=v;
              @(negedge clk);wwe=0;end
    endtask
    task automatic write_b(input [1:0] nn,input signed [39:0] v);
        begin @(negedge clk);bwe=1;neuron=nn;bias=v;
              @(negedge clk);bwe=0;end
    endtask
    task automatic run_npu(input [6:0] count);
        begin @(negedge clk);len=count;start=1;
              @(negedge clk);start=0;
              wait(done || error);#1;end
    endtask
    function automatic signed [40:0] exp_score(input integer s,input integer row);
        integer x0,x1,w0,w1;
        begin
            x0=(s&2)?-1:1;x1=(s&1)?-1:1;
            w0=(row&2)?-1:1;w1=(row&1)?-1:1;
            exp_score=x0*w0+x1*w1;
        end
    endfunction
    initial begin
        repeat(8)@(negedge clk);resetn=1;
        for(n=0;n<4;n=n+1)begin
            write_w(n,0,(n&2)?-16'sd1:16'sd1);
            write_w(n,1,(n&1)?-16'sd1:16'sd1);
        end
        for(sample=0;sample<4;sample=sample+1)begin
            write_x(0,(sample&2)?-16'sd1:16'sd1);
            write_x(1,(sample&1)?-16'sd1:16'sd1);
            run_npu(2);
            if(error) $fatal(1,"Unexpected NPU error sample=%0d",sample);
            if(cls!==sample[1:0])$fatal(1,"Class %0d != sample %0d",cls,sample);
            for(k=0;k<4;k=k+1)
                if($signed(scores[k*41+:41])!==exp_score(sample,k))
                    $fatal(1,"Score mismatch s=%0d lane=%0d",sample,k);
        end
        write_x(0,1);write_x(1,1);write_b(3,10);
        run_npu(2);
        if(cls!==2'd3 || $signed(scores[3*41+:41])!==41'sd8)
            $fatal(1,"Bias update ignored");
        @(negedge clk);len=3;start=1;
        @(negedge clk);start=0;
        wait(error);#1;
        $display("NPU_ENGINE_RTL_SIM_PASS samples=4 bias_update=1 invalid_len=1");
        $finish;
    end
    initial begin #1000000;$fatal(1,"Engine TB timeout");end
endmodule
