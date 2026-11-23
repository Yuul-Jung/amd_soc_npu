`timescale 1ns/1ps
module fixed_quantizer #(
    parameter integer IN_WIDTH=32, OUT_WIDTH=8, SHIFT=8, ROUND=1, SATURATE=1
) (
    input wire clk, resetn, valid_i,
    input wire signed [IN_WIDTH-1:0] x_i,
    output reg signed [OUT_WIDTH-1:0] q_o,
    output reg valid_o, overflow_o
);
    wire signed [63:0] wide, rounded, scaled, lower, upper;
    wire ov;
    // 입력이 초기 0에서 변하지 않아도 조합 계산을 시작하는 연속 할당이다.
    assign wide = $signed(x_i);
    assign lower = -(64'sd1 <<< (OUT_WIDTH-1));
    assign upper = (64'sd1 <<< (OUT_WIDTH-1))-1;
    // 음수는 크기를 반올림한 뒤 부호를 복원하여 tie-away 규칙을 적용한다.
    assign rounded = (ROUND && SHIFT>0) ?
      (wide<0 ? -(((-wide)+(64'sd1 <<< (SHIFT-1))) >>> SHIFT) :
                 (wide+(64'sd1 <<< (SHIFT-1))) >>> SHIFT) : wide >>> SHIFT;
    assign ov = rounded<lower || rounded>upper;
    assign scaled = (SATURATE && rounded<lower) ? lower :
                    (SATURATE && rounded>upper) ? upper : rounded;
    always @(posedge clk) begin
        if(!resetn) begin q_o<=0; valid_o<=0; overflow_o<=0; end
        else begin
            valid_o<=valid_i;
            if(valid_i) begin q_o<=scaled[OUT_WIDTH-1:0]; overflow_o<=ov; end
        end
    end
    // synthesis translate_off
    initial if(IN_WIDTH<2 || IN_WIDTH>48 || OUT_WIDTH<2 || OUT_WIDTH>32 || SHIFT<0 || SHIFT>30)
        $fatal(1,"Unsupported quantizer parameters");
    // synthesis translate_on
endmodule
