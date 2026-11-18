`timescale 1ns/1ps
module vector_dot_core #(parameter integer DATA_WIDTH=16,ACC_WIDTH=40,MAX_LEN=256)(
    input wire clk,resetn,start_i,valid_i,
    input wire [8:0] length_i,
    input wire signed [DATA_WIDTH-1:0] a_i,b_i,
    output wire ready_o,
    output reg busy_o,done_o,error_o,
    output reg signed [ACC_WIDTH-1:0] result_o
);
    reg [8:0] accepted,length_q;
    wire signed [ACC_WIDTH-1:0] acc;
    wire mac_valid;
    wire launch=start_i && !busy_o;
    assign ready_o=busy_o && accepted<length_q;
    // 정상 MAC을 그대로 사용하고 트랜잭션 경계에서만 Clear한다.
    mac_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH)) mac
      (.clk(clk),.resetn(resetn),.clear_i(launch),.valid_i(valid_i && ready_o),
       .a_i(a_i),.b_i(b_i),.acc_o(acc),.valid_o(mac_valid));
    always @(posedge clk) begin
        if(!resetn) begin
            busy_o<=0;done_o<=0;error_o<=0;result_o<=0;accepted<=0;length_q<=0;
        end else begin
            done_o<=0;error_o<=0;
            if(launch) begin
                accepted<=0;length_q<=length_i;
                if(length_i>MAX_LEN) error_o<=1;
                else if(length_i==0) begin result_o<=0;done_o<=1;end
                else busy_o<=1;
            end else if(busy_o) begin
                if(valid_i && ready_o) accepted<=accepted+1'b1;
                // MAC 출력은 직전 에지에 등록되었으므로 마지막 수락 다음 에지에 읽는다.
                if(mac_valid && accepted==length_q) begin
                    result_o<=acc;done_o<=1;busy_o<=0;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(MAX_LEN<1 || MAX_LEN>256) $fatal(1,"MAX_LEN range");
    // synthesis translate_on
endmodule
