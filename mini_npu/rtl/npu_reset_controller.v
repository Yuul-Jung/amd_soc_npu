// Basys3 btnC → 동기 Reset (Active-Low resetn).
// btnC를 플립플롭 2단으로 동기화한 뒤 resetn을 만든다. 모든 플립플롭이 clk에만 반응한다.
// 리셋이 비동기로 바뀌면 그 신호를 받는 RAMB18의 EN·WE·RST 핀이 setup/hold를 어겨 BRAM 내용이 깨질 수 있으므로
// (Vivado DRC REQP-1840), 걸 때도 풀 때도 클록에 맞춘다.
//   · 전원 인가 직후: 초기값으로 resetn=0, btnC가 0이면 3클록 뒤 해제
//   · btnC를 1클록(10 ns) 이상 누르면 2~3클록 뒤 resetn=0, 떼면 2~3클록 뒤 resetn=1
module npu_reset_controller(
    input wire clk,btnC,
    output wire resetn
);
    (* ASYNC_REG="TRUE" *) reg [1:0] sync_q=2'b11;
    reg resetn_q=1'b0;
    always @(posedge clk)begin
        sync_q<={sync_q[0],btnC};
        resetn_q<=~sync_q[1];
    end
    assign resetn=resetn_q;
endmodule
