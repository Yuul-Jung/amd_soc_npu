// (추가) 31장: SHA-256 압축 코어 시험. FIPS 180-4 예제("abc", 448비트), RFC 4231 HMAC 1·2의 내부·외부 해시 메시지,
//   빈 메시지·경계 길이·무작위 메시지(Python이 패딩한 블록). 메시지마다 init → next … 순서로 넣고 최종 digest 대조.
`timescale 1ns/1ps
module tb_p3_sha256;
    reg clk = 0, rst = 1, init = 0, next = 0;
    reg [511:0] blk;
    wire busy, done;
    wire [255:0] dg;
    always #5 clk = ~clk;
    p3_sha256_core dut(.clk(clk), .rst(rst), .init(init), .next(next), .block(blk), .busy(busy), .done(done), .digest(dg));
    reg [8*256-1:0] vpath;
    reg [8*8-1:0] tag;
    reg [255:0] exp;
    integer f, r, nb, k, n = 0, blocks = 0, errors = 0, cyc;
    initial begin
        if (!$value$plusargs("VEC=%s", vpath)) $fatal(1, "+VEC required");
        f = $fopen(vpath, "r");
        repeat (3) @(posedge clk);
        rst = 0;
        while (!$feof(f)) begin
            r = $fscanf(f, "%s %d %h\n", tag, nb, exp);
            if (r == 3) begin
                for (k = 0; k < nb; k = k + 1) begin
                    r = $fscanf(f, "%h\n", blk);
                    @(negedge clk); init = (k == 0); next = (k != 0); @(negedge clk); init = 0; next = 0;
                    cyc = 1;
                    while (!done) begin @(posedge clk); #1; cyc = cyc + 1; end
                    blocks = blocks + 1;
                end
                if (dg !== exp) begin
                    errors = errors + 1;
                    if (errors <= 5) $display("MISMATCH msg=%0d blocks=%0d got %h exp %h", n, nb, dg, exp);
                end
                n = n + 1;
            end
        end
        if (errors == 0 && n > 5) $display("RTL_SIM_PASS SHA256 messages=%0d blocks=%0d cycles_per_block=%0d", n, blocks, cyc);
        else $display("RTL_SIM_FAIL SHA256 messages=%0d errors=%0d", n, errors);
        $finish;
    end
endmodule
