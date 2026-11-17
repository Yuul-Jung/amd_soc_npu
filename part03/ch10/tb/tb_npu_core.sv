`timescale 1ns/1ps
module tb_npu_core;
    parameter DW=16,AW=40;
    reg clk=0,rn=0,start=0,xwe=0,wwe=0;
    reg[8:0]len=0;reg[5:0]xa=0,wa=0;reg[1:0]neuron=0;
    reg signed[DW-1:0]xd=0,wd=0;
    reg[4*AW-1:0]biases=0;
    wire ready,busy,done,error;wire[4*DW-1:0]result;wire[3:0]overflow;
    npu_core #(.DATA_WIDTH(DW),.ACC_WIDTH(AW)) dut(.clk(clk),.resetn(rn),.start_i(start),.length_i(len),
      .biases_i(biases),.x_wr_en(xwe),.w_wr_en(wwe),.x_wr_addr(xa),.w_wr_addr(wa),.w_neuron(neuron),
      .x_wr_data(xd),.w_wr_data(wd),.load_ready_o(ready),.busy_o(busy),.done_o(done),.error_o(error),
      .result_o(result),.overflow_o(overflow));
    always #5 clk=~clk;
    integer f,o,n,c=0,k,i,t,run,xi,ws[0:3],expected[0:3],em;
    reg signed[AW-1:0]bs[0:3];
    reg signed[DW-1:0]xm[0:63],wm[0:3][0:63];
    string vp,ap;
    initial begin
        if(!$value$plusargs("VECTORS=%s",vp)||!$value$plusargs("ACTUAL=%s",ap))$fatal(1,"Paths");
        f=$fopen(vp,"r");o=$fopen(ap,"w");if(!f||!o)$fatal(1,"Open");
        repeat(2)@(negedge clk);rn=1;start=1;len=65;
        @(posedge clk);#1;if(!error||busy)$fatal(1,"Length guard");
        @(negedge clk);start=0;
        while(!$feof(f))begin
            if($fscanf(f,"%d %d %d %d %d %d %d %d %d %d\n",n,bs[0],bs[1],bs[2],bs[3],
              expected[0],expected[1],expected[2],expected[3],em)!=10)$fatal(1,"Header");
            for(k=0;k<n;k=k+1)begin
                if($fscanf(f,"%d %d %d %d %d\n",xi,ws[0],ws[1],ws[2],ws[3])!=5)$fatal(1,"Data");
                xm[k]=xi;for(i=0;i<4;i=i+1)wm[i][k]=ws[i];
            end
            // 역순 주소로 적재하여 전송 순서와 메모리 주소 순서를 분리한다.
            for(k=n-1;k>=0;k=k-1)for(i=0;i<4;i=i+1)begin
                @(negedge clk);if(!ready)$fatal(1,"Load ready");
                xwe=(i==0);xa=k;xd=xm[k];wwe=1;wa=k;wd=wm[i][k];neuron=i;
                @(posedge clk);#1;
            end
            @(negedge clk);xwe=0;wwe=0;
            for(run=1;run<=2;run=run+1)begin
                if(run==2)begin
                    // 계산을 시작해 중간에 취소한 뒤 재적재 없이 다시 실행한다.
                    @(negedge clk);start=1;len=n;biases=0;
                    @(negedge clk);start=0;
                    repeat(3)@(negedge clk);rn=0;
                    @(posedge clk);#1;if(busy||done||ready||result!==0)$fatal(1,"Reset cancel");
                    @(negedge clk);rn=1;
                end
                @(negedge clk);start=1;len=n;
                for(i=0;i<4;i=i+1)biases[i*AW+:AW]=bs[i];
                @(posedge clk);#1;if(!busy||done||ready)$fatal(1,"Start");
                @(negedge clk);start=0;biases=0;t=0;
                while(!done)begin
                    @(negedge clk);
                    // busy 중 주소0 오염 요청은 차단되어야 한다.
                    xwe=(t==2);wwe=(t==2);start=(t==2);xa=0;wa=0;xd=99;wd=99;neuron=0;
                    @(posedge clk);#1;t=t+1;
                    if(error)$fatal(1,"Core error state=%0d",dut.state);
                    if(t>1000)$fatal(1,"Timeout inference");
                end
                if(busy||!ready||overflow!==em[3:0])$fatal(1,"Flags");
                for(i=0;i<4;i=i+1)if($signed(result[i*DW+:DW])!==expected[i])$fatal(1,"Result dataset=%0d neuron=%0d",c+1,i);
                $fdisplay(o,"%0d %0d %0d %0d %0d %0d %0d",c+1,run,$signed(result[0*DW+:DW]),
                  $signed(result[1*DW+:DW]),$signed(result[2*DW+:DW]),$signed(result[3*DW+:DW]),overflow);
                @(negedge clk);start=0;xwe=0;wwe=0;
                @(posedge clk);#1;if(done||busy)$fatal(1,"Done pulse");
            end
            c=c+1;
        end
        if(!c)$fatal(1,"Empty");$fclose(o);$display("RTL_SIM_PASS NPU INT%0d/%0d datasets=%0d inferences=%0d",DW,AW,c,2*c);$finish;
    end
    initial begin #10000000;$fatal(1,"Timeout");end
endmodule
