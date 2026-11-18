`timescale 1ns/1ps
`default_nettype none
module tb_mac_pipeline_core;
    parameter integer DATA_WIDTH = 16;
    parameter integer ACC_WIDTH = 40;
    reg clk = 0;
    reg resetn = 0, clear_i = 0, valid_i = 0;
    reg signed [DATA_WIDTH-1:0] a_i = 0, b_i = 0;
    wire signed [ACC_WIDTH-1:0] acc_o;
    wire valid_o;
    mac_pipeline_core #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (.*);
    always #5 clk = ~clk;
    integer vf, af, fields, cycle = 0;
    integer rn, cl, vi, ai, bi, expected_pv, expected_v;
    reg signed [2*DATA_WIDTH-1:0] expected_product;
    reg signed [ACC_WIDTH-1:0] expected_acc;
    longint signed previous_product = 0, model_acc = 0, multiply_w;
    reg previous_valid = 0, model_valid;
    reg signed [ACC_WIDTH-1:0] held_acc;
    reg signed [2*DATA_WIDTH-1:0] held_product;
    reg held_valid, held_pv;
    string vp, ap;

    initial begin
        if (DATA_WIDTH > 16 || ACC_WIDTH > 40 || ACC_WIDTH < 2*DATA_WIDTH)
            $fatal(1, "Unsupported TB width");
        if (!$value$plusargs("VECTORS=%s", vp) || !$value$plusargs("ACTUAL=%s", ap))
            $fatal(1, "Missing vector/trace argument");
        vf = $fopen(vp, "r"); af = $fopen(ap, "w");
        if (!vf || !af) $fatal(1, "Cannot open test files");
        @(posedge clk); #1;
        if (acc_o !== 0 || valid_o !== 0 || dut.product_q !== 0 || dut.product_valid_q !== 0)
            $fatal(1, "Initial reset failed");
        while (!$feof(vf)) begin
            fields = $fscanf(vf, "%d %d %d %d %d %d %d %d %d\n",
                             rn, cl, vi, ai, bi, expected_product, expected_pv, expected_acc, expected_v);
            if (fields != 9) $fatal(1, "Malformed vector");
            @(negedge clk);
            held_acc = acc_o; held_valid = valid_o;
            held_product = dut.product_q; held_pv = dut.product_valid_q;
            resetn = rn; clear_i = cl; valid_i = vi; a_i = ai; b_i = bi;
            #1;
            if (acc_o !== held_acc || valid_o !== held_valid ||
                dut.product_q !== held_product || dut.product_valid_q !== held_pv)
                $fatal(1, "Output changed before rising edge cycle=%0d", cycle+1);
            @(posedge clk); #1;
            cycle = cycle + 1;
            // 현재 valid_i가 아니라 이전 에지의 곱 유효 상태로 누산 여부를 결정한다.
            model_valid = rn && !cl && previous_valid;
            if (!rn || cl) begin
                model_acc = 0;
                previous_product = 0;
                previous_valid = 0;
            end else begin
                if (previous_valid) begin
                    model_acc = model_acc + previous_product;
                    model_acc = $signed(model_acc[ACC_WIDTH-1:0]);
                end
                previous_valid = vi;
                if (vi) begin
                    multiply_w = $signed(a_i);
                    previous_product = multiply_w * $signed(b_i);
                end
            end
            if (expected_acc !== model_acc[ACC_WIDTH-1:0] || expected_v[0] !== model_valid ||
                expected_product !== previous_product[2*DATA_WIDTH-1:0] || expected_pv[0] !== previous_valid)
                $fatal(1, "Python/SV reference mismatch cycle=%0d", cycle);
            if (acc_o !== expected_acc || valid_o !== model_valid ||
                dut.product_q !== expected_product || dut.product_valid_q !== previous_valid)
                $fatal(1, "DUT mismatch cycle=%0d acc=%0d expected=%0d valid=%0d expected=%0d",
                       cycle, acc_o, expected_acc, valid_o, model_valid);
            $fdisplay(af, "%0d %0d %0d %0d %0d", cycle, dut.product_q,
                      dut.product_valid_q, acc_o, valid_o);
        end
        if (!cycle || previous_valid) $fatal(1, "Empty test or pipeline not drained");
        $fclose(vf); $fclose(af);
        $display("RTL_SIM_PASS INT%0d/%0d cycles=%0d", DATA_WIDTH, ACC_WIDTH, cycle);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
`default_nettype wire
