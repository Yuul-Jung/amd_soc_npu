// (추가) 31장: AES-128 코어 시험. FIPS 197 부록 C.1·B, SP 800-38A F.5.1 CTR 키스트림 블록, 무작위 200개(Python 정본)
`timescale 1ns/1ps
module tb_p3_aes128;
    reg clk = 0, rst = 1, start = 0;
    reg [127:0] key, blk, exp;
    wire busy, done;
    wire [127:0] res;
    always #5 clk = ~clk;
    p3_aes128_enc dut(.clk(clk), .rst(rst), .start(start), .key(key), .block(blk), .busy(busy), .done(done), .result(res));
    reg [8*256-1:0] vpath;
    integer f, r, n = 0, errors = 0, cyc, max_cyc = 0;
    initial begin
        if (!$value$plusargs("VEC=%s", vpath)) $fatal(1, "+VEC required");
        f = $fopen(vpath, "r");
        repeat (3) @(posedge clk);
        rst = 0;
        while (!$feof(f)) begin
            r = $fscanf(f, "%h %h %h\n", key, blk, exp);
            if (r == 3) begin
                @(negedge clk); start = 1; @(negedge clk); start = 0;
                cyc = 1;
                while (!done) begin @(posedge clk); #1; cyc = cyc + 1; end
                if (cyc > max_cyc) max_cyc = cyc;
                if (res !== exp) begin
                    errors = errors + 1;
                    if (errors <= 5) $display("MISMATCH n=%0d key=%h pt=%h got %h exp %h", n, key, blk, res, exp);
                end
                n = n + 1;
            end
        end
        if (errors == 0 && n >= 6) $display("RTL_SIM_PASS AES128 blocks=%0d kat=6 cycles_per_block=%0d", n, max_cyc);
        else $display("RTL_SIM_FAIL AES128 blocks=%0d errors=%0d", n, errors);
        $finish;
    end
endmodule
