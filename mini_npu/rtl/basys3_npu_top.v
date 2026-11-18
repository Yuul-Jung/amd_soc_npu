// (추가) 12장 Basys3 Shell: 전원·UART·코어·Controller·FND 모듈 연결만 담당.
module basys3_npu_top(
    input wire clk,btnC,uart_rxd,
    output wire uart_txd,
    output wire [15:0] led,
    output wire [6:0] seg,
    output wire [3:0] an,
    output wire dp
);
    wire resetn;
    wire [7:0] rx_data,tx_data;
    wire rx_valid,rx_ready,tx_valid,tx_ready,fe,ov,cmd_error;
    wire start,xwe,wwe,bwe,load_ready,busy,done,error;
    wire [6:0] length;
    wire [5:0] wr_addr;
    wire [1:0] neuron,class_id;
    wire signed [15:0] wr_data;
    wire signed [39:0] wr_bias;
    wire [163:0] scores;
    npu_reset_controller rst(.clk(clk),.btnC(btnC),.resetn(resetn));
    uart_core uart(.clk(clk),.resetn(resetn),
        .uart_rxd_i(uart_rxd),.uart_txd_o(uart_txd),
        .rx_out_data(rx_data),.rx_out_valid(rx_valid),.rx_out_ready(rx_ready),
        .tx_in_data(tx_data),.tx_in_valid(tx_valid),.tx_in_ready(tx_ready),
        .rx_framing_error_o(fe),.rx_overrun_o(ov));
    uart_npu_command_controller commands(.clk(clk),.resetn(resetn),
        .rx_data_i(rx_data),.rx_valid_i(rx_valid),.rx_ready_o(rx_ready),
        .tx_data_o(tx_data),.tx_valid_o(tx_valid),.tx_ready_i(tx_ready),
        .npu_start_o(start),.npu_length_o(length),
        .x_wr_en_o(xwe),.w_wr_en_o(wwe),.b_wr_en_o(bwe),
        .wr_addr_o(wr_addr),.neuron_o(neuron),
        .wr_data_o(wr_data),.bias_data_o(wr_bias),
        .npu_load_ready_i(load_ready),
        .npu_busy_i(busy),.npu_done_i(done),.npu_error_i(error),
        .npu_class_i(class_id),.npu_scores_i(scores),
        .protocol_error_o(cmd_error));
    npu_engine4 engine(.clk(clk),.resetn(resetn),
        .start_i(start),.length_i(length),
        .x_wr_en(xwe),.w_wr_en(wwe),.b_wr_en(bwe),
        .addr_i(wr_addr),.neuron_i(neuron),.data_i(wr_data),.bias_i(wr_bias),
        .load_ready_o(load_ready),.busy_o(busy),.done_o(done),.error_o(error),
        .class_o(class_id),.scores_o(scores));
    npu_display_controller display(.clk(clk),.resetn(resetn),
        .class_i(class_id),.busy_i(busy),.done_i(done),
        .error_i(error),.protocol_error_i(cmd_error),
        .uart_framing_error_i(fe),.uart_overrun_i(ov),
        .led_o(led),.seg_o(seg),.an_o(an),.dp_o(dp));
endmodule
