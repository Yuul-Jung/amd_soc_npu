// 장 Top 공용 리셋: btnC(Active-High)를 2단 동기화해 동기 resetn을 만든다 (npu_reset_controller와 같은 동작).
// 모든 플립플롭이 clk에만 반응한다. 리셋이 비동기로 바뀌면 그 신호를 받는 BRAM 제어 핀이 setup/hold를 어겨
// 내용이 깨질 수 있으므로(Vivado DRC REQP-1840), 걸 때도 풀 때도 클록에 맞춘다.
`timescale 1ns/1ps
`default_nettype none
module p01_reset_sync (
    input  wire clk,
    input  wire btnC,
    output wire resetn
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_q = 2'b11;
    reg resetn_q = 1'b0;
    always @(posedge clk) begin
        sync_q   <= {sync_q[0], btnC};
        resetn_q <= ~sync_q[1];
    end
    assign resetn = resetn_q;
endmodule
`default_nettype wire
