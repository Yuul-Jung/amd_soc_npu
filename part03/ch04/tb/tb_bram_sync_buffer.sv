`timescale 1ns/1ps
module tb_bram_sync_buffer;
    parameter W=16, A=8;
    reg clk=0, resetn=0;
    reg wr[0:1], rd[0:1];
    reg [A-1:0] wa[0:1], ra[0:1];
    reg signed [W-1:0] wd[0:1];
    wire signed [W-1:0] data[0:1];
    wire valid[0:1];
    reg written[0:1][0:(1<<A)-1];
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: buffers
        bram_sync_buffer #(.DATA_WIDTH(W),.ADDR_WIDTH(A)) dut
          (.clk(clk),.resetn(resetn),.wr_en(wr[g]),.rd_en(rd[g]),
           .wr_addr(wa[g]),.rd_addr(ra[g]),.wr_data(wd[g]),.rd_data(data[g]),.rd_valid(valid[g]));
    end endgenerate
    always #5 clk=~clk;
    integer f,o,n,c=0,i,j;
    integer rn,w0,wa0,wd0,r0,ra0,w1,wa1,wd1,r1,ra1,e0,v0,e1,v1;
    reg signed [W-1:0] held[0:1];
    reg hv[0:1];
    string vp,ap;
    // 금지 입력을 시험 환경에서 검출하고 RTL 충돌 동작을 명세로 확정하지 않는다.
    always @(posedge clk) if(resetn) begin
        for(integer k=0;k<2;k=k+1) begin
            if(wr[k] && rd[k] && wa[k]==ra[k]) $fatal(1,"COLLISION");
            if(rd[k] && !written[k][ra[k]]) $fatal(1,"UNINITIALIZED_READ");
            if(wr[k]) written[k][wa[k]]=1;
        end
    end
    initial begin
        for(i=0;i<2;i=i+1) begin
            wr[i]=0; rd[i]=0; wa[i]=0; ra[i]=0; wd[i]=0;
            for(j=0;j<(1<<A);j=j+1) written[i][j]=0;
        end
        if($test$plusargs("COLLISION_TEST")) begin
            @(negedge clk); resetn=1; wr[0]=1; rd[0]=1;
            #20; $fatal(1,"Missing collision guard");
        end else if($test$plusargs("UNINITIALIZED_TEST")) begin
            @(negedge clk); resetn=1; rd[0]=1;
            #20; $fatal(1,"Missing uninitialized guard");
        end else begin
            if(!$value$plusargs("VECTORS=%s",vp)||!$value$plusargs("ACTUAL=%s",ap)) $fatal(1,"Missing paths");
            f=$fopen(vp,"r"); o=$fopen(ap,"w"); if(!f||!o) $fatal(1,"Open failed");
            @(posedge clk); #1;
            while(!$feof(f)) begin
                n=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                  rn,w0,wa0,wd0,r0,ra0,w1,wa1,wd1,r1,ra1,e0,v0,e1,v1);
                if(n!=15) $fatal(1,"Bad row");
                @(negedge clk);
                for(i=0;i<2;i=i+1) begin held[i]=data[i]; hv[i]=valid[i]; end
                resetn=rn; wr[0]=w0; wa[0]=wa0; wd[0]=wd0; rd[0]=r0; ra[0]=ra0;
                wr[1]=w1; wa[1]=wa1; wd[1]=wd1; rd[1]=r1; ra[1]=ra1;
                #1;
                for(i=0;i<2;i=i+1) if(data[i]!==held[i]||valid[i]!==hv[i]) $fatal(1,"Async output");
                @(posedge clk); #1; c=c+1;
                if($signed(data[0])!==e0||valid[0]!==v0[0]||$signed(data[1])!==e1||valid[1]!==v1[0])
                    $fatal(1,"Mismatch cycle=%0d",c);
                $fdisplay(o,"%0d %0d %0d %0d %0d",c,data[0],valid[0],data[1],valid[1]);
            end
            if(c==0) $fatal(1,"Empty");
            $fclose(o); $display("RTL_SIM_PASS BRAM W=%0d A=%0d cycles=%0d",W,A,c); $finish;
        end
    end
    initial begin #10000000; $fatal(1,"Timeout"); end
endmodule
