`timescale 1ns/1ps
module tb_fixed_quantizer;
    parameter IW=32,OW=8,S=8;
    reg clk=0,rn=0,vi=0;
    reg signed [IW-1:0] x=0;
    wire signed [OW-1:0] q[0:3];
    wire ov[0:3],v[0:3];
    genvar g;
    generate for(g=0;g<4;g=g+1) begin: modes
        fixed_quantizer #(.IN_WIDTH(IW),.OUT_WIDTH(OW),.SHIFT(S),.ROUND(g/2),.SATURATE(g%2)) dut
          (.clk(clk),.resetn(rn),.valid_i(vi),.x_i(x),.q_o(q[g]),.valid_o(v[g]),.overflow_o(ov[g]));
    end endgenerate
    always #5 clk=~clk;
    integer f,o,n,c=0,r,valid_in,xi,eq[0:3],eo[0:3],ev,i;
    reg signed [OW-1:0] held[0:3];
    reg hv[0:3],ho[0:3];
    string vp,ap;
    initial begin
        if(!$value$plusargs("VECTORS=%s",vp)||!$value$plusargs("ACTUAL=%s",ap)) $fatal(1,"Missing paths");
        f=$fopen(vp,"r"); o=$fopen(ap,"w"); if(!f||!o) $fatal(1,"Open failed");
        @(posedge clk); #1;
        while(!$feof(f)) begin
            n=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d\n",
              r,valid_in,xi,eq[0],eo[0],eq[1],eo[1],eq[2],eo[2],eq[3],eo[3],ev);
            if(n!=12) $fatal(1,"Bad row");
            @(negedge clk);
            for(i=0;i<4;i=i+1) begin held[i]=q[i]; hv[i]=v[i]; ho[i]=ov[i]; end
            rn=r; vi=valid_in; x=xi; #1;
            for(i=0;i<4;i=i+1) if(q[i]!==held[i]||v[i]!==hv[i]||ov[i]!==ho[i]) $fatal(1,"Async output");
            @(posedge clk); #1; c=c+1;
            for(i=0;i<4;i=i+1) if($signed(q[i])!==eq[i]||ov[i]!==eo[i][0]||v[i]!==ev[0])
                $fatal(1,"Mismatch cycle=%0d mode=%0d",c,i);
            $fdisplay(o,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",c,
              q[0],ov[0],q[1],ov[1],q[2],ov[2],q[3],ov[3],v[0]);
        end
        if(!c) $fatal(1,"Empty");
        $fclose(o); $display("RTL_SIM_PASS FIXED IW=%0d OW=%0d SHIFT=%0d cycles=%0d",IW,OW,S,c); $finish;
    end
    initial begin #10000000; $fatal(1,"Timeout"); end
endmodule
