`timescale 1ns/1ps
module tb_vector_dot;
    parameter DW=16,AW=40;
    reg clk=0,rn=0,start=0,vi=0;
    reg [8:0] len=0;
    reg signed [DW-1:0] a=0,b=0;
    wire ready,busy,done,error;
    wire signed [AW-1:0] result;
    vector_dot_core #(.DATA_WIDTH(DW),.ACC_WIDTH(AW)) dut
      (.clk(clk),.resetn(rn),.start_i(start),.valid_i(vi),.length_i(len),.a_i(a),.b_i(b),
       .ready_o(ready),.busy_o(busy),.done_o(done),.error_o(error),.result_o(result));
    always #5 clk=~clk;
    integer f,o,n,x,y,c=0,k,fields;
    reg signed [AW-1:0] expected;
    string vp,ap;
    initial begin
        if(!$value$plusargs("VECTORS=%s",vp)||!$value$plusargs("ACTUAL=%s",ap))$fatal(1,"Paths");
        f=$fopen(vp,"r");o=$fopen(ap,"w");if(!f||!o)$fatal(1,"Open");
        repeat(2)@(negedge clk);rn=1;start=1;len=257;
        @(posedge clk);#1;if(!error||busy||done)$fatal(1,"Length guard");
        @(negedge clk);start=0;
        // 계류 계산을 Reset으로 취소하고 새 벡터를 시작한다.
        @(negedge clk);start=1;len=4;
        @(negedge clk);start=0;vi=1;a=3;b=4;
        @(negedge clk);rn=0;
        @(posedge clk);#1;if(busy||done||ready||result!==0)$fatal(1,"Reset cancel");
        @(negedge clk);rn=1;vi=0;
        while(!$feof(f))begin
            fields=$fscanf(f,"%d %d\n",n,expected);if(fields!=2)$fatal(1,"Header");
            @(negedge clk);start=1;len=n;vi=0;
            @(posedge clk);#1;
            if(n==0)begin if(!done||busy||result!==0)$fatal(1,"Zero");end
            else if(!busy||done||!ready)$fatal(1,"Start");
            @(negedge clk);start=0;
            for(k=0;k<n;k=k+1)begin
                if($fscanf(f,"%d %d\n",x,y)!=2)$fatal(1,"Pair");
                @(negedge clk);a=x;b=y;vi=1;start=(k==0);
                if(!ready)$fatal(1,"Ready");
                @(posedge clk);#1;if(done||!busy)$fatal(1,"Early done");
                if(k<n-1 && k%3==0)begin
                    @(negedge clk);vi=0;start=0;
                    @(posedge clk);#1;if(done||!busy)$fatal(1,"Bubble");
                end
            end
            if(n>0)begin
                @(negedge clk);vi=0;start=0;
                @(posedge clk);#1;if(!done||busy||result!==expected)$fatal(1,"Result case=%0d",c+1);
            end
            c=c+1;$fdisplay(o,"%0d %0d",c,result);
            @(negedge clk);start=0;vi=0;
            @(posedge clk);#1;if(done||busy||error)$fatal(1,"Pulse");
        end
        if(!c)$fatal(1,"Empty");$fclose(o);$display("RTL_SIM_PASS DOT INT%0d/%0d cases=%0d",DW,AW,c);$finish;
    end
    initial begin #10000000;$fatal(1,"Timeout");end
endmodule
