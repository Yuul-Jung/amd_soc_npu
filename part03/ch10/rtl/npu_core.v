`timescale 1ns/1ps
module npu_core #(parameter integer DATA_WIDTH=16,ACC_WIDTH=40)(
    input wire clk,resetn,start_i,
    input wire [8:0] length_i,
    input wire [4*ACC_WIDTH-1:0] biases_i,
    input wire x_wr_en,w_wr_en,
    input wire [5:0] x_wr_addr,w_wr_addr,
    input wire [1:0] w_neuron,
    input wire signed [DATA_WIDTH-1:0] x_wr_data,w_wr_data,
    output wire load_ready_o,
    output reg busy_o,done_o,error_o,
    output reg [4*DATA_WIDTH-1:0] result_o,
    output reg [3:0] overflow_o
);
    localparam IDLE=0,LAUNCH=1,READ=2,WAIT_READ=3,SEND=4,WAIT_DONE=5;
    reg [2:0] state;
    reg [8:0] length_q;
    reg [5:0] index_q;
    reg [4*ACC_WIDTH-1:0] biases_q;
    wire rd_en=state==READ;
    wire signed [DATA_WIDTH-1:0] x_data;
    wire x_valid;
    wire [4*DATA_WIDTH-1:0] w_data;
    wire [3:0] w_valid;
    wire dense_ready,dense_done,dense_error;
    wire [4*DATA_WIDTH-1:0] dense_result;
    wire [3:0] dense_overflow;
    assign load_ready_o=resetn && !busy_o;
    bram_sync_buffer #(.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(6)) inputs_mem
      (.clk(clk),.resetn(resetn),.wr_en(x_wr_en && load_ready_o),.wr_addr(x_wr_addr),.wr_data(x_wr_data),
       .rd_en(rd_en),.rd_addr(index_q),.rd_data(x_data),.rd_valid(x_valid));
    genvar g;
    generate for(g=0;g<4;g=g+1)begin: weights_mem
        bram_sync_buffer #(.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(6)) mem
          (.clk(clk),.resetn(resetn),.wr_en(w_wr_en && load_ready_o && w_neuron==g),
           .wr_addr(w_wr_addr),.wr_data(w_wr_data),.rd_en(rd_en),.rd_addr(index_q),
           .rd_data(w_data[g*DATA_WIDTH+:DATA_WIDTH]),.rd_valid(w_valid[g]));
    end endgenerate
    dense_layer4 #(.DATA_WIDTH(DATA_WIDTH),.ACC_WIDTH(ACC_WIDTH)) dense
      (.clk(clk),.resetn(resetn),.start_i(state==LAUNCH),.length_i(length_q),
       .valid_i(state==SEND),.x_i(x_data),.weights_i(w_data),.biases_i(biases_q),
       .ready_o(dense_ready),.busy_o(),.done_o(dense_done),.error_o(dense_error),
       .result_o(dense_result),.overflow_o(dense_overflow));
    always @(posedge clk)begin
        if(!resetn)begin
            state<=IDLE;busy_o<=0;done_o<=0;error_o<=0;result_o<=0;overflow_o<=0;
            index_q<=0;length_q<=0;biases_q<=0;
        end else begin
            done_o<=0;error_o<=0;
            case(state)
                IDLE: if(start_i)begin
                    if(length_i>64 || x_wr_en || w_wr_en)error_o<=1;
                    else begin
                        length_q<=length_i;biases_q<=biases_i;index_q<=0;busy_o<=1;state<=LAUNCH;
                    end
                end
                LAUNCH: if(length_q==0)state<=WAIT_DONE;else state<=READ;
                READ: state<=WAIT_READ;
                WAIT_READ: begin
                    // 메모리 출력과 Valid가 정렬된 에지를 확인한 뒤 전송한다.
                    if(x_valid && (&w_valid))state<=SEND;
                    else begin state<=IDLE;busy_o<=0;error_o<=1;end
                end
                SEND: if(dense_ready)begin
                    if({3'b0,index_q}+9'd1==length_q)state<=WAIT_DONE;
                    else begin index_q<=index_q+1'b1;state<=READ;end
                end
                WAIT_DONE: if(dense_done)begin
                    result_o<=dense_result;overflow_o<=dense_overflow;busy_o<=0;done_o<=1;state<=IDLE;
                end
                default: begin state<=IDLE;busy_o<=0;error_o<=1;end
            endcase
            if(dense_error)begin state<=IDLE;busy_o<=0;error_o<=1;end
        end
    end
endmodule
