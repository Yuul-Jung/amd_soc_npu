`timescale 1ns/1ps
`default_nettype none
module tb_dsp_multiplier;
    parameter integer A_WIDTH = 16;
    parameter integer B_WIDTH = 16;
    parameter integer ACC_WIDTH = 40;
    localparam integer MAC_WIDTH = A_WIDTH > B_WIDTH ? A_WIDTH : B_WIDTH;
    reg clk = 0;
    reg resetn = 0, clear_i = 0, valid_i = 0;
    reg signed [A_WIDTH-1:0] a_i = 0;
    reg signed [B_WIDTH-1:0] b_i = 0;
    wire signed [A_WIDTH+B_WIDTH-1:0] product_o;
    wire valid_o;
    wire signed [ACC_WIDTH-1:0] acc_o;
    wire mac_valid;
    wire signed [MAC_WIDTH-1:0] a_mac = a_i;
    wire signed [MAC_WIDTH-1:0] b_mac = b_i;
    dsp_multiplier #(.A_WIDTH(A_WIDTH), .B_WIDTH(B_WIDTH)) dut (.*);
    // 누산 로직은 복제하지 않고 P3-01 정상 모듈에 같은 입력을 연결한다.
    mac_core #(.DATA_WIDTH(MAC_WIDTH), .ACC_WIDTH(ACC_WIDTH)) mac (
        .clk(clk), .resetn(resetn), .clear_i(clear_i), .valid_i(valid_i),
        .a_i(a_mac), .b_i(b_mac), .acc_o(acc_o), .valid_o(mac_valid)
    );
    always #5 clk = ~clk;
    integer vf, af, fields, cycle = 0;
    integer rn, cl, vi, ai, bi, ev;
    reg signed [A_WIDTH+B_WIDTH-1:0] ep;
    reg signed [ACC_WIDTH-1:0] ea;
    longint signed model_product = 0, model_acc = 0, multiply_w;
    reg signed [A_WIDTH+B_WIDTH-1:0] held_product;
    reg signed [ACC_WIDTH-1:0] held_acc;
    reg held_valid, held_mac_valid;
    string vp, ap;

    initial begin
        if (ACC_WIDTH > 56 || ACC_WIDTH < 2*MAC_WIDTH)
            $fatal(1, "TB requires 2*MAC_WIDTH<=ACC_WIDTH<=56");
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap))
            $fatal(1, "Missing vector/trace argument");
        vf = $fopen(vp, "r"); af = $fopen(ap, "w");
        if (!vf || !af) $fatal(1, "Cannot open test files");
        @(posedge clk); #1;
        if (product_o !== 0 || valid_o !== 0 || acc_o !== 0 || mac_valid !== 0)
            $fatal(1, "Initial reset failed");
        while (!$feof(vf)) begin
            fields = $fscanf(vf, "%d %d %d %d %d %d %d %d\n", rn, cl, vi, ai, bi, ep, ea, ev);
            if (fields != 8) $fatal(1, "Malformed vector");
            @(negedge clk);
            held_product = product_o; held_acc = acc_o;
            held_valid = valid_o; held_mac_valid = mac_valid;
            resetn = rn; clear_i = cl; valid_i = vi; a_i = ai; b_i = bi;
            #1;
            if (product_o !== held_product || acc_o !== held_acc ||
                valid_o !== held_valid || mac_valid !== held_mac_valid)
                $fatal(1, "Output changed before rising edge cycle=%0d", cycle+1);
            @(posedge clk); #1;
            cycle = cycle + 1;
            // 64비트 정수로 먼저 확장하여 곱을 계산하고 명시적으로 누산 폭을 적용한다.
            multiply_w = $signed(a_i);
            multiply_w = multiply_w * $signed(b_i);
            if (!rn || cl) begin
                model_product = 0;
                model_acc = 0;
            end else if (vi) begin
                model_product = multiply_w;
                model_acc = model_acc + multiply_w;
                model_acc = $signed(model_acc[ACC_WIDTH-1:0]);
            end
            if (ep !== model_product[A_WIDTH+B_WIDTH-1:0] ||
                ea !== model_acc[ACC_WIDTH-1:0] || ev !== (rn && !cl && vi))
                $fatal(1, "Python/SV reference mismatch cycle=%0d", cycle);
            if (product_o !== ep || acc_o !== ea || valid_o !== ev[0] || mac_valid !== ev[0])
                $fatal(1, "DUT mismatch cycle=%0d a=%0d b=%0d product=%0d expected=%0d acc=%0d expected=%0d",
                       cycle, a_i, b_i, product_o, ep, acc_o, ea);
            $fdisplay(af, "%0d %0d %0d %0d", cycle, product_o, acc_o, valid_o);
        end
        if (!cycle) $fatal(1, "Empty test");
        $fclose(vf); $fclose(af);
        $display("RTL_SIM_PASS A=%0d B=%0d ACC=%0d cycles=%0d", A_WIDTH, B_WIDTH, ACC_WIDTH, cycle);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
`default_nettype wire
