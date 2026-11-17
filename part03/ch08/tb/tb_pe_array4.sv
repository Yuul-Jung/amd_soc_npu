`timescale 1ns/1ps
module tb_pe_array4;
    parameter DW=16,AW=40;
    reg clk=0,rn=0,start=0;
    reg [8:0] len=0;
    reg [3:0] vi=0,fire;
    reg [4*DW-1:0] a=0,b=0;
    wire [3:0] ready;wire busy,done,error;
    wire [4*AW-1:0] pe;wire signed [AW+1:0] sum;
    pe_array4 #(.DATA_WIDTH(DW),.ACC_WIDTH(AW)) dut(.clk(clk),.resetn(rn),.start_i(start),.length_i(len),
      .valid_i(vi),.a_i(a),.b_i(b),.ready_o(ready),.busy_o(busy),.done_o(done),.error_o(error),
      .pe_results_o(pe),.sum_o(sum));
    always #5 clk=~clk;
    integer f,o,n,c=0,i,k,t,fields,idx[0:3],x[0:3],y[0:3];
    reg signed [DW-1:0] av[0:3][0:255],bv[0:3][0:255];
    reg signed [AW-1:0] expected[0:3];reg signed [AW+1:0] total;
    string vp,ap;
    initial begin
        if(!$value$plusargs("VECTORS=%s",vp)||!$value$plusargs("ACTUAL=%s",ap))$fatal(1,"Paths");
        f=$fopen(vp,"r");o=$fopen(ap,"w");if(!f||!o)$fatal(1,"Open");
        repeat(2)@(negedge clk);rn=1;start=1;len=4;
        @(negedge clk);start=0;vi=15;
        @(negedge clk);rn=0;
        @(posedge clk);#1;if(busy||done||ready!==0)$fatal(1,"Reset");
        @(negedge clk);rn=1;vi=0;
        while(!$feof(f))begin
            fields=$fscanf(f,"%d %d %d %d %d %d\n",n,expected[0],expected[1],expected[2],expected[3],total);
            if(fields!=6)$fatal(1,"Header");
            for(k=0;k<n;k=k+1)begin
                if($fscanf(f,"%d %d %d %d %d %d %d %d\n",x[0],y[0],x[1],y[1],x[2],y[2],x[3],y[3])!=8)$fatal(1,"Pair");
                for(i=0;i<4;i=i+1)begin av[i][k]=x[i];bv[i][k]=y[i];end
            end
            @(negedge clk);start=1;len=n;vi=0;
            @(posedge clk);#1;if(!busy||done)$fatal(1,"Start");
            for(i=0;i<4;i=i+1)idx[i]=0;
            t=0;
            while(!done)begin
                @(negedge clk);start=(t==2);vi=0;
                for(i=0;i<4;i=i+1)if(idx[i]<n && (t+i)%5!=0 && t%11!=0)begin
                    vi[i]=1;a[i*DW+:DW]=av[i][idx[i]];b[i*DW+:DW]=bv[i][idx[i]];
                end
                #1;fire=vi & ready;
                @(posedge clk);#1;
                for(i=0;i<4;i=i+1)if(fire[i])idx[i]=idx[i]+1;
                t=t+1;if(t>2000)$fatal(1,"Timeout transaction");
            end
            if(busy||error||sum!==total)$fatal(1,"Sum case=%0d",c+1);
            for(i=0;i<4;i=i+1)if(idx[i]!=n||$signed(pe[i*AW+:AW])!==expected[i])$fatal(1,"PE %0d",i);
            c=c+1;$fdisplay(o,"%0d %0d %0d %0d %0d %0d",c,
              $signed(pe[0*AW+:AW]),$signed(pe[1*AW+:AW]),$signed(pe[2*AW+:AW]),$signed(pe[3*AW+:AW]),sum);
            @(negedge clk);vi=0;start=0;
            @(posedge clk);#1;if(done||busy)$fatal(1,"Pulse");
        end
        if(!c)$fatal(1,"Empty");$fclose(o);$display("RTL_SIM_PASS PE4 INT%0d/%0d cases=%0d",DW,AW,c);$finish;
    end
    initial begin #10000000;$fatal(1,"Timeout");end
endmodule
