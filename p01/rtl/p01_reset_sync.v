// 1장 리셋: btnC(Active-High)를 비동기로 걸고 동기로 푼다 (12장 npu_reset_controller와 같은 동작).
`timescale 1ns/1ps
`default_nettype none
module p01_reset_sync (
    input  wire clk,
    input  wire btnC,
    output wire resetn
);
    reg [1:0] release_q;
    always @(posedge clk or posedge btnC) begin
        if (btnC) release_q <= 2'b00;
        else      release_q <= {release_q[0], 1'b1};
    end
    assign resetn = release_q[1];
endmodule
`default_nettype wire
