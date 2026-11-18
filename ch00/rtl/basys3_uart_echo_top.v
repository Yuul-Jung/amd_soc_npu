// (추가) Shell top: no logic except instances and wires.
module basys3_uart_echo_top(
    input wire clk,resetn,uart_rxd,
    output wire uart_txd
);
    wire [7:0] rx_data,tx_data;
    wire rx_valid,rx_ready,tx_valid,tx_ready;
    wire framing_error,overrun;
    uart_core uart(.clk(clk),.resetn(resetn),.uart_rxd_i(uart_rxd),
        .uart_txd_o(uart_txd),.rx_out_data(rx_data),
        .rx_out_valid(rx_valid),.rx_out_ready(rx_ready),
        .tx_in_data(tx_data),.tx_in_valid(tx_valid),.tx_in_ready(tx_ready),
        .rx_framing_error_o(framing_error),.rx_overrun_o(overrun));
    uart_echo_controller controller(.rx_data_i(rx_data),
        .rx_valid_i(rx_valid),.rx_ready_o(rx_ready),
        .tx_data_o(tx_data),.tx_valid_o(tx_valid),.tx_ready_i(tx_ready));
endmodule
