// 장 Top 공용 리셋: btnC(Active-High)를 2단 동기화해 동기 resetn을 만든다 (12장 npu_reset_controller와 같은 동작).
// (변경 2026-11-22) 비동기 assert 제거 — 비동기 clear되는 플립플롭 출력이 RAMB18 제어 핀으로 들어가면
// 버튼을 누르는 순간 BRAM 내용이 깨질 수 있다 (Vivado DRC REQP-1840). 모든 플립플롭이 clk에만 반응한다.
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
