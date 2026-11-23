// FND와 LED 표현 정책은 Top이 아닌 Controller에서 처리.
module npu_display_controller(
    input wire clk,resetn,
    input wire [1:0] class_i,
    input wire busy_i,done_i,error_i,protocol_error_i,
    input wire uart_framing_error_i,uart_overrun_i,
    output wire [15:0] led_o,
    output reg [6:0] seg_o,
    output reg [3:0] an_o,
    output wire dp_o
);
    reg done_latched,error_latched;
    reg [17:0] scan_count;
    reg [3:0] digit;
    wire [3:0] onehot=4'b0001<<class_i;
    always @(posedge clk)begin
        if(!resetn)begin
            done_latched<=0;error_latched<=0;scan_count<=0;
        end else begin
            scan_count<=scan_count+1'b1;
            if(done_i)done_latched<=1;
            if(error_i||protocol_error_i||uart_framing_error_i||uart_overrun_i)
                error_latched<=1;
        end
    end
    assign led_o[3:0]=onehot;
    assign led_o[12:4]=9'd0;
    assign led_o[13]=busy_i;
    assign led_o[14]=done_latched;
    assign led_o[15]=error_latched;
    assign dp_o=1'b1;
    always @*begin
        case(scan_count[17:16])
            2'd0:begin an_o=4'b1110;digit={2'b00,class_i};end
            2'd1:begin an_o=4'b1101;digit=0;end
            2'd2:begin an_o=4'b1011;digit=0;end
            default:begin an_o=4'b0111;digit=0;end
        endcase
        // Active low: segments {g,f,e,d,c,b,a} (seg[0] is a).
        case(digit)
            0:seg_o=7'b1000000;
            1:seg_o=7'b1111001;
            2:seg_o=7'b0100100;
            3:seg_o=7'b0110000;
            default:seg_o=7'b1111111;
        endcase
    end
endmodule
