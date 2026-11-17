`timescale 1ns/1ps
module tb_precision_compare;
    reg clk=0,rn=0,vi=0;
    reg signed [31:0] x=0;
    wire signed [7:0] q8[0:1]; wire signed [15:0] q16[0:1];
    wire o8[0:1],o16[0:1],v[0:1];
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: policies
        precision_compare #(.SATURATE(g)) dut(.clk(clk),.resetn(rn),.valid_i(vi),.x_i(x),
          .q8_o(q8[g]),.q16_o(q16[g]),.overflow8_o(o8[g]),.overflow16_o(o16[g]),.valid_o(v[g]));
    end endgenerate
    always #5 clk=~clk;
    integer f,o,n,c=0,r,vin,xi,e[0:7],ev,i;
    string vp,ap;
    initial begin
        if(!$value$plusargs("VECTORS=%s",vp)||!$value$plusargs("ACTUAL=%s",ap)) $fatal(1,"Paths");
        f=$fopen(vp,"r");o=$fopen(ap,"w"); if(!f||!o) $fatal(1,"Open");
        @(posedge clk);#1;
        while(!$feof(f)) begin
            n=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d\n",r,vin,xi,
              e[0],e[1],e[2],e[3],e[4],e[5],e[6],e[7],ev);
            if(n!=12) $fatal(1,"Row");
            @(negedge clk);rn=r;vi=vin;x=xi;
            @(posedge clk);#1;c=c+1;
            for(i=0;i<2;i=i+1) if($signed(q8[i])!==e[4*i]||$signed(q16[i])!==e[4*i+1]||
              o8[i]!==e[4*i+2][0]||o16[i]!==e[4*i+3][0]||v[i]!==ev[0])
              $fatal(1,"Mismatch cycle=%0d mode=%0d x=%0d q=%0d/%0d expected=%0d/%0d flags=%b/%b v=%b expectedv=%0d",
                c,i,x,q8[i],q16[i],e[4*i],e[4*i+1],o8[i],o16[i],v[i],ev);
            $fdisplay(o,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",c,
              q8[0],q16[0],o8[0],o16[0],q8[1],q16[1],o8[1],o16[1],v[0]);
        end
        if(!c) $fatal(1,"Empty");
        $fclose(o);$display("RTL_SIM_PASS PRECISION cycles=%0d",c);$finish;
    end
    initial begin #10000000;$fatal(1,"Timeout");end
endmodule
