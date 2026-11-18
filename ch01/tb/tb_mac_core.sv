`timescale 1ns/1ps
`default_nettype none
module tb_mac_core;
    parameter integer DATA_WIDTH = 16;
    parameter integer ACC_WIDTH = 40;
    reg clk = 0;
    reg resetn = 0, clear_i = 0, valid_i = 0;
    reg signed [DATA_WIDTH-1:0] a_i = 0, b_i = 0;
    wire signed [ACC_WIDTH-1:0] acc_o;
    wire valid_o;
    mac_core #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (.*);
    always #5 clk = ~clk;

    integer vectors, actual, fields, cycle = 0;
    integer rn, cl, vi, ai, bi, expected_valid;
    reg signed [ACC_WIDTH-1:0] expected_acc;
    reg signed [ACC_WIDTH-1:0] previous_acc;
    reg previous_valid;
    longint signed model_acc = 0;
    longint signed model_product;
    reg model_valid;
    string vectors_path, actual_path;

    initial begin
        if (!$value$plusargs("VECTORS=%s", vectors_path) ||
            !$value$plusargs("ACTUAL=%s", actual_path))
            $fatal(1, "Missing VECTORS/ACTUAL path");
        vectors = $fopen(vectors_path, "r");
        actual = $fopen(actual_path, "w");
        if (!vectors || !actual) $fatal(1, "Cannot open vector/trace file");
        // 첫 상승 에지에서 동기식 Reset을 적용하여 알려진 상태를 만든다.
        @(posedge clk); #1;
        if (acc_o !== 0 || valid_o !== 0) $fatal(1, "Initial reset failed");
        while (!$feof(vectors)) begin
            fields = $fscanf(vectors, "%d %d %d %d %d %d %d\n",
                              rn, cl, vi, ai, bi, expected_acc, expected_valid);
            if (fields != 7) $fatal(1, "Malformed vector row");
            @(negedge clk);
            previous_acc = acc_o;
            previous_valid = valid_o;
            resetn = rn; clear_i = cl; valid_i = vi; a_i = ai; b_i = bi;
            #1;
            // 입력 변경만으로 출력이 변하면 동기식 타이밍 위반이다.
            if (acc_o !== previous_acc || valid_o !== previous_valid)
                $fatal(1, "Output changed before rising edge cycle=%0d", cycle+1);
            @(posedge clk); #1; // NBA 갱신 이후 같은 에지의 결과를 검사한다.
            cycle = cycle + 1;
            // Python 파일 외에도 SV의 64비트 정수 산술로 독립 계산한다.
            // 이 TB의 실행 설정은 ACC_WIDTH<=40이므로 곱과 합이 64비트에 들어간다.
            model_product = $signed(a_i);
            model_product = model_product * $signed(b_i);
            model_valid = rn && !cl && vi;
            if (!rn || cl) model_acc = 0;
            else if (vi) model_acc = model_acc + model_product;
            model_acc = $signed(model_acc[ACC_WIDTH-1:0]);
            if (expected_acc !== model_acc[ACC_WIDTH-1:0] || expected_valid[0] !== model_valid)
                $fatal(1, "SV/Python reference mismatch cycle=%0d", cycle);
            if (acc_o !== expected_acc || valid_o !== expected_valid[0])
                $fatal(1, "cycle=%0d a=%0d b=%0d expected=%0d/%0d actual=%0d/%0d",
                       cycle, a_i, b_i, expected_acc, expected_valid, acc_o, valid_o);
            $fdisplay(actual, "%0d %0d %0d", cycle, acc_o, valid_o);
        end
        if (cycle == 0) $fatal(1, "Empty vector file");
        $fclose(vectors); $fclose(actual);
        $display("RTL_SIM_PASS INT%0d/%0d cycles=%0d", DATA_WIDTH, ACC_WIDTH, cycle);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
`default_nettype wire
