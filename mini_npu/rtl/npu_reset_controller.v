// (추가) Basys3 btnC 비동기 Assertion, 동기 Release Reset.
module npu_reset_controller(
    input wire clk,btnC,
    output wire resetn
);
    reg [1:0] release_q;
    always @(posedge clk or posedge btnC)
        if(btnC)release_q<=2'b00;
        else release_q<={release_q[0],1'b1};
    assign resetn=release_q[1];
endmodule
