`timescale 1ns/1ps
module tb_dense_layer4;
    parameter DW=16,AW=40;
    reg clk=0,rn=0,start=0,vi=0;
    reg [8:0] len=0;
    reg signed [DW-1:0] x=0;
    reg [4*DW-1:0] weights=0;
    reg [4*AW-1:0] biases=0;
    wire ready,busy,done,error;wire [4*DW-1:0] result;wire[3:0]overflow;
    dense_layer4 #(.DATA_WIDTH(DW),.ACC_WIDTH(AW)) dut(.clk(clk),.resetn(rn),.start_i(start),.valid_i(vi),
      .length_i(len),.x_i(x),.weights_i(weights),.biases_i(biases),.ready_o(ready),.busy_o(busy),
      .done_o(done),.error_o(error),.result_o(result),.overflow_o(overflow));
    always #5 clk=~clk;
    integer f,o,n,c=0,k,i,t,xi,ws[0:3],em;
    reg signed [AW-1:0] bs[0:3];integer expected[0:3];
    string vp,ap;
    initial begin
        if(!$value$plusargs("VECTORS=%s",vp)||!$value$plusargs("ACTUAL=%s",ap))$fatal(1,"Paths");
        f=$fopen(vp,"r");o=$fopen(ap,"w");if(!f||!o)$fatal(1,"Open");
        repeat(2)@(negedge clk);rn=1;start=1;len=65;
        @(posedge clk);#1;if(!error||busy)$fatal(1,"Length guard");
        @(negedge clk);start=0;
        @(negedge clk);start=1;len=4;
        @(negedge clk);start=0;vi=1;x=3;
        @(negedge clk);rn=0;
        @(posedge clk);#1;if(busy||done||ready)$fatal(1,"Reset");
        @(negedge clk);rn=1;vi=0;
        while(!$feof(f))begin
            if($fscanf(f,"%d %d %d %d %d %d %d %d %d %d\n",n,bs[0],bs[1],bs[2],bs[3],
              expected[0],expected[1],expected[2],expected[3],em)!=10)$fatal(1,"Header");
            @(negedge clk);len=n;start=1;vi=0;
            for(i=0;i<4;i=i+1)biases[i*AW+:AW]=bs[i];
            @(posedge clk);#1;if(!busy||done)$fatal(1,"Start");
            @(negedge clk);start=0;biases=0; // 저장된 Bias가 외부 변경에 영향받지 않아야 한다.
            for(k=0;k<n;k=k+1)begin
                if($fscanf(f,"%d %d %d %d %d\n",xi,ws[0],ws[1],ws[2],ws[3])!=5)$fatal(1,"Pair");
                @(negedge clk);if(!ready)$fatal(1,"Ready");
                x=xi;vi=1;for(i=0;i<4;i=i+1)weights[i*DW+:DW]=ws[i];
                @(posedge clk);#1;if(done)$fatal(1,"Early");
                if(k%3==0 && k<n-1)begin @(negedge clk);vi=0;@(posedge clk);#1;if(done)$fatal(1,"Bubble");end
            end
            @(negedge clk);vi=0;t=0;
            while(!done)begin @(posedge clk);#1;t=t+1;if(t>20)$fatal(1,"Completion timeout");end
            if(busy||overflow!==em[3:0])$fatal(1,"Flags");
            for(i=0;i<4;i=i+1)if($signed(result[i*DW+:DW])!==expected[i])$fatal(1,"Neuron %0d case%0d",i,c+1);
            c=c+1;$fdisplay(o,"%0d %0d %0d %0d %0d %0d",c,$signed(result[0*DW+:DW]),
              $signed(result[1*DW+:DW]),$signed(result[2*DW+:DW]),$signed(result[3*DW+:DW]),overflow);
            @(negedge clk);start=0;vi=0;@(posedge clk);#1;if(done||busy)$fatal(1,"Pulse");
        end
        if(!c)$fatal(1,"Empty");$fclose(o);$display("RTL_SIM_PASS DENSE4 INT%0d/%0d cases=%0d",DW,AW,c);$finish;
    end
    initial begin #10000000;$fatal(1,"Timeout");end
endmodule
