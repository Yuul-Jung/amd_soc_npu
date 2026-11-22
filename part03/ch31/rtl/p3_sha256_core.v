// (추가) 31장: SHA-256 압축 코어(FIPS 180-4). 반복형: 1클록에 1라운드, 블록당 64클록 + 1.
//   init = IV로 새 메시지의 첫 블록, next = 이전 결과에 이어 다음 블록. 패딩은 호출 쪽(펌웨어·TB)이 한다.
//   block[511:480] = 첫 32비트 워드(big-endian). digest[255:224] = H0. done 1클록, digest 유지.
//   HMAC-SHA-256은 이 코어를 두 번(내부·외부 해시) 쓰는 메시지 단위 구성이다(FIPS 198-1). K 표는 처음 64개 소수
//   세제곱근의 소수부로 계산해 확인했다. 교육용 구현: 부채널 대책 없음.
`timescale 1ns/1ps
module p3_sha256_core (
    input  wire         clk,
    input  wire         rst,
    input  wire         init,
    input  wire         next,
    input  wire [511:0] block,
    output reg          busy,
    output reg          done,
    output wire [255:0] digest
);
    function [31:0] kc;
        input [5:0] t;
        case (t)
            6'd0: kc = 32'h428a2f98;
            6'd1: kc = 32'h71374491;
            6'd2: kc = 32'hb5c0fbcf;
            6'd3: kc = 32'he9b5dba5;
            6'd4: kc = 32'h3956c25b;
            6'd5: kc = 32'h59f111f1;
            6'd6: kc = 32'h923f82a4;
            6'd7: kc = 32'hab1c5ed5;
            6'd8: kc = 32'hd807aa98;
            6'd9: kc = 32'h12835b01;
            6'd10: kc = 32'h243185be;
            6'd11: kc = 32'h550c7dc3;
            6'd12: kc = 32'h72be5d74;
            6'd13: kc = 32'h80deb1fe;
            6'd14: kc = 32'h9bdc06a7;
            6'd15: kc = 32'hc19bf174;
            6'd16: kc = 32'he49b69c1;
            6'd17: kc = 32'hefbe4786;
            6'd18: kc = 32'h0fc19dc6;
            6'd19: kc = 32'h240ca1cc;
            6'd20: kc = 32'h2de92c6f;
            6'd21: kc = 32'h4a7484aa;
            6'd22: kc = 32'h5cb0a9dc;
            6'd23: kc = 32'h76f988da;
            6'd24: kc = 32'h983e5152;
            6'd25: kc = 32'ha831c66d;
            6'd26: kc = 32'hb00327c8;
            6'd27: kc = 32'hbf597fc7;
            6'd28: kc = 32'hc6e00bf3;
            6'd29: kc = 32'hd5a79147;
            6'd30: kc = 32'h06ca6351;
            6'd31: kc = 32'h14292967;
            6'd32: kc = 32'h27b70a85;
            6'd33: kc = 32'h2e1b2138;
            6'd34: kc = 32'h4d2c6dfc;
            6'd35: kc = 32'h53380d13;
            6'd36: kc = 32'h650a7354;
            6'd37: kc = 32'h766a0abb;
            6'd38: kc = 32'h81c2c92e;
            6'd39: kc = 32'h92722c85;
            6'd40: kc = 32'ha2bfe8a1;
            6'd41: kc = 32'ha81a664b;
            6'd42: kc = 32'hc24b8b70;
            6'd43: kc = 32'hc76c51a3;
            6'd44: kc = 32'hd192e819;
            6'd45: kc = 32'hd6990624;
            6'd46: kc = 32'hf40e3585;
            6'd47: kc = 32'h106aa070;
            6'd48: kc = 32'h19a4c116;
            6'd49: kc = 32'h1e376c08;
            6'd50: kc = 32'h2748774c;
            6'd51: kc = 32'h34b0bcb5;
            6'd52: kc = 32'h391c0cb3;
            6'd53: kc = 32'h4ed8aa4a;
            6'd54: kc = 32'h5b9cca4f;
            6'd55: kc = 32'h682e6ff3;
            6'd56: kc = 32'h748f82ee;
            6'd57: kc = 32'h78a5636f;
            6'd58: kc = 32'h84c87814;
            6'd59: kc = 32'h8cc70208;
            6'd60: kc = 32'h90befffa;
            6'd61: kc = 32'ha4506ceb;
            6'd62: kc = 32'hbef9a3f7;
            6'd63: kc = 32'hc67178f2;
        endcase
    endfunction
    function [31:0] rotr;
        input [31:0] x;
        input integer n;
        rotr = (x >> n) | (x << (32 - n));
    endfunction

    reg [31:0] H [0:7];
    reg [31:0] a, b, c, d, e, f, g, h;
    reg [31:0] w [0:15];
    reg [6:0]  t;
    integer i;
    wire [31:0] s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    wire [31:0] ch = (e & f) ^ (~e & g);
    wire [31:0] t1 = h + s1 + ch + kc(t[5:0]) + w[0];
    wire [31:0] s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    wire [31:0] mj = (a & b) ^ (a & c) ^ (b & c);
    wire [31:0] t2 = s0 + mj;
    wire [31:0] ws0 = rotr(w[1], 7) ^ rotr(w[1], 18) ^ (w[1] >> 3);
    wire [31:0] ws1 = rotr(w[14], 17) ^ rotr(w[14], 19) ^ (w[14] >> 10);
    wire [31:0] w_new = ws1 + w[9] + ws0 + w[0];
    assign digest = {H[0], H[1], H[2], H[3], H[4], H[5], H[6], H[7]};

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0; done <= 1'b0; t <= 7'd0;
            H[0] <= 32'h6a09e667; H[1] <= 32'hbb67ae85; H[2] <= 32'h3c6ef372; H[3] <= 32'ha54ff53a;
            H[4] <= 32'h510e527f; H[5] <= 32'h9b05688c; H[6] <= 32'h1f83d9ab; H[7] <= 32'h5be0cd19;
        end else begin
            done <= 1'b0;
            if ((init || next) && !busy) begin
                if (init) begin
                    a <= 32'h6a09e667; b <= 32'hbb67ae85; c <= 32'h3c6ef372; d <= 32'ha54ff53a;
                    e <= 32'h510e527f; f <= 32'h9b05688c; g <= 32'h1f83d9ab; h <= 32'h5be0cd19;
                    H[0] <= 32'h6a09e667; H[1] <= 32'hbb67ae85; H[2] <= 32'h3c6ef372; H[3] <= 32'ha54ff53a;
                    H[4] <= 32'h510e527f; H[5] <= 32'h9b05688c; H[6] <= 32'h1f83d9ab; H[7] <= 32'h5be0cd19;
                end else begin
                    a <= H[0]; b <= H[1]; c <= H[2]; d <= H[3]; e <= H[4]; f <= H[5]; g <= H[6]; h <= H[7];
                end
                for (i = 0; i < 16; i = i + 1) w[i] <= block[511 - 32 * i -: 32];
                t <= 7'd0;
                busy <= 1'b1;
            end else if (busy && t < 7'd64) begin
                h <= g; g <= f; f <= e; e <= d + t1; d <= c; c <= b; b <= a; a <= t1 + t2;
                for (i = 0; i < 15; i = i + 1) w[i] <= w[i + 1];
                w[15] <= w_new;
                t <= t + 7'd1;
            end else if (busy) begin
                H[0] <= H[0] + a; H[1] <= H[1] + b; H[2] <= H[2] + c; H[3] <= H[3] + d;
                H[4] <= H[4] + e; H[5] <= H[5] + f; H[6] <= H[6] + g; H[7] <= H[7] + h;
                busy <= 1'b0; done <= 1'b1;
            end
        end
    end
endmodule
