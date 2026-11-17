`timescale 1ns/1ps
module pe_array4 #(parameter integer DATA_WIDTH=16,ACC_WIDTH=40)(
    input wire clk,resetn,start_i,
    input wire [8:0] length_i,
    input wire [3:0] valid_i,
    input wire [4*DATA_WIDTH-1:0] a_i,b_i,
    output wire [3:0] ready_o,
    output reg busy_o,done_o,error_o,
    output wire [4*ACC_WIDTH-1:0] pe_results_o,
    output reg signed [ACC_WIDTH+1:0] sum_o
);
    wire launch=start_i && !busy_o && length_i<=256;
    wire [3:0] lane_ready,lane_done;
    wire signed [ACC_WIDTH-1:0] lane_result[0:3];
    reg signed [ACC_WIDTH-1:0] saved[0:3];
    reg [3:0] finished;
    wire signed [ACC_WIDTH+1:0] extended[0:3];
    wire signed [ACC_WIDTH+1:0] left_sum,right_sum;
    assign left_sum=extended[0]+extended[1];
    assign right_sum=extended[2]+extended[3];
    assign ready_o=lane_ready & {4{busy_o}};
    genvar g;
    generate for(g=0;g<4;g=g+1)begin: pe
        assign pe_results_o[g*ACC_WIDTH+:ACC_WIDTH]=saved[g];
        assign extended[g]={{2{saved[g][ACC_WIDTH-1]}},saved[g]};
        vector_dot_core #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH)) dot
          (.clk(clk),.resetn(resetn),.start_i(launch),.length_i(length_i),
           .valid_i(valid_i[g] && busy_o),.a_i(a_i[g*DATA_WIDTH+:DATA_WIDTH]),.b_i(b_i[g*DATA_WIDTH+:DATA_WIDTH]),
           .ready_o(lane_ready[g]),.busy_o(),.done_o(lane_done[g]),.error_o(),.result_o(lane_result[g]));
    end endgenerate
    integer i;
    always @(posedge clk)begin
        if(!resetn)begin
            busy_o<=0;done_o<=0;error_o<=0;sum_o<=0;finished<=0;
            for(i=0;i<4;i=i+1)saved[i]<=0;
        end else begin
            done_o<=0;error_o<=0;
            if(start_i && !busy_o)begin
                if(length_i>256)error_o<=1;
                else begin busy_o<=1;finished<=0;end
            end else if(busy_o)begin
                for(i=0;i<4;i=i+1)if(lane_done[i])begin saved[i]<=lane_result[i];finished[i]<=1;end
                // 서로 다른 완료 에지의 결과를 모은 후 정렬된 합을 등록한다.
                if(&finished)begin sum_o<=left_sum+right_sum;done_o<=1;busy_o<=0;end
            end
        end
    end
endmodule
