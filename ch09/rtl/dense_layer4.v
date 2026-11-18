`timescale 1ns/1ps
module dense_layer4 #(parameter integer DATA_WIDTH=16,ACC_WIDTH=40,SHIFT=0)(
    input wire clk,resetn,start_i,valid_i,
    input wire [8:0] length_i,
    input wire signed [DATA_WIDTH-1:0] x_i,
    input wire [4*DATA_WIDTH-1:0] weights_i,
    input wire [4*ACC_WIDTH-1:0] biases_i,
    output wire ready_o,
    output reg busy_o,done_o,error_o,
    output reg [4*DATA_WIDTH-1:0] result_o,
    output reg [3:0] overflow_o
);
    wire launch=start_i && !busy_o && length_i<=64;
    reg [4*ACC_WIDTH-1:0] biases_q;
    wire [3:0] ready_pe;
    wire pe_done;
    wire [4*ACC_WIDTH-1:0] pe_result;
    wire [4*DATA_WIDTH-1:0] quantized;
    wire [3:0] qv,qov;
    assign ready_o=busy_o && (&ready_pe);
    pe_array4 #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH)) pe
      (.clk(clk),.resetn(resetn),.start_i(launch),.length_i(length_i),
       .valid_i({4{valid_i && ready_o}}),.a_i({4{x_i}}),.b_i(weights_i),
       .ready_o(ready_pe),.busy_o(),.done_o(pe_done),.error_o(),.pe_results_o(pe_result),.sum_o());
    genvar g;
    generate for(g=0;g<4;g=g+1)begin: neurons
        wire signed [ACC_WIDTH-1:0] dot_value=pe_result[g*ACC_WIDTH+:ACC_WIDTH];
        wire signed [ACC_WIDTH-1:0] bias_value=biases_q[g*ACC_WIDTH+:ACC_WIDTH];
        wire signed [ACC_WIDTH:0] biased={dot_value[ACC_WIDTH-1],dot_value}+{bias_value[ACC_WIDTH-1],bias_value};
        wire signed [ACC_WIDTH:0] activated=biased<0 ? 0 : biased;
        fixed_quantizer #(.IN_WIDTH(ACC_WIDTH+1),.OUT_WIDTH(DATA_WIDTH),.SHIFT(SHIFT),.ROUND(1),.SATURATE(1)) q
          (.clk(clk),.resetn(resetn),.valid_i(pe_done && busy_o),.x_i(activated),
           .q_o(quantized[g*DATA_WIDTH+:DATA_WIDTH]),.valid_o(qv[g]),.overflow_o(qov[g]));
    end endgenerate
    always @(posedge clk)begin
        if(!resetn)begin busy_o<=0;done_o<=0;error_o<=0;result_o<=0;overflow_o<=0;biases_q<=0;end
        else begin
            done_o<=0;error_o<=0;
            if(start_i && !busy_o)begin
                if(length_i>64)error_o<=1;
                else begin busy_o<=1;biases_q<=biases_i;end
            end else if(busy_o && (&qv))begin
                result_o<=quantized;overflow_o<=qov;busy_o<=0;done_o<=1;
            end
        end
    end
endmodule
