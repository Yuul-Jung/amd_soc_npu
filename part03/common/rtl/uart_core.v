// (추가) 8N1 물리 UART + Byte Stream 인터페이스.
module uart_core #(
    parameter integer CLK_HZ=100000000,BAUD=115200
)(
    input wire clk,resetn,uart_rxd_i,
    output wire uart_txd_o,
    output wire [7:0] rx_out_data,
    output wire rx_out_valid,
    input wire rx_out_ready,
    input wire [7:0] tx_in_data,
    input wire tx_in_valid,
    output wire tx_in_ready,
    output wire rx_framing_error_o,rx_overrun_o
);
    uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) rx(
        .clk(clk),.resetn(resetn),.rx_i(uart_rxd_i),
        .out_data_o(rx_out_data),.out_valid_o(rx_out_valid),.out_ready_i(rx_out_ready),
        .framing_error_o(rx_framing_error_o),.overrun_o(rx_overrun_o));
    uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) tx(
        .clk(clk),.resetn(resetn),.in_data_i(tx_in_data),
        .in_valid_i(tx_in_valid),.in_ready_o(tx_in_ready),.tx_o(uart_txd_o));
endmodule
