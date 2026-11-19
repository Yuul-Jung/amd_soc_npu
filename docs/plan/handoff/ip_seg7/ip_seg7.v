// =====================================================================
// ip_seg7.v  —  [06] 7세그먼트 IP (ID "SEG7", 버전 1.0, IP 표준 개정 1)
//
// L07의 axi4lite_seg7(구형)을 IP 표준으로 바꾸고, 글자 모양을 비트로 직접 정하는
// 원시 세그먼트 방식을 더했다. 0x0000 VALUE는 L07과 같은 뜻이라, SEG7_VALUE에 16진수 4자리를
// 쓰던 프로그램은 고치지 않고 그대로 돈다(MODE = 0인 리셋 상태가 L07과 같은 표시).
//
// 기능 레지스터 (오프셋, 32비트)
//   0x0000 VALUE  읽기/쓰기  [15:0] 16진수 4자리. [3:0] = 오른쪽 끝(an[0]), [15:12] = 왼쪽 끝(an[3])
//   0x0004 MODE   읽기/쓰기  [3:0]  RAW_EN  1인 자리는 VALUE 대신 RAW의 바이트를 그대로 켠다
//                            [11:8] BLANK   1인 자리는 끈다(an을 켜지 않음)
//   0x0008 RAW    읽기/쓰기  자리 n = 바이트 n ([7:0] = an[0] … [31:24] = an[3])
//                            바이트 안: [0] a, [1] b, [2] c, [3] d, [4] e, [5] f, [6] g, [7] 소수점. 1 = 켬
//   0x000C DP     읽기/쓰기  [3:0] 16진수 자리(RAW_EN = 0)의 소수점. 1 = 켬
//   0xFFF0~0xFFFC            표준 관리 영역 (ip_std.v): ID "SEG7", VER, IRQ_STATUS, IRQ_ENABLE
//
// 인터럽트 원인은 없다 (N_IRQ = 1, irq_set = 0, irq 포트 없음).
// 리셋 값은 모두 0: 0000이 보이고(L07과 같음), 소수점은 꺼짐.
// 보드 쪽 seg·dp·an은 active-low이고 seg = {g, f, e, d, c, b, a} 순서다 (L07·Basys3 XDC와 같음).
// 자리 전환은 L07과 같이 100 MHz / 2^16 ≈ 1.5 kHz, 네 자리 한 바퀴 ≈ 381 Hz.
// 공통 모듈 axil_slave.v·ip_std.v는 고치지 않고 그대로 넣는다 (IP 표준).
// =====================================================================
module ip_seg7 (
    // 보드로 나가는 7세그먼트 (L07과 같은 이름·폭이라 soc_top.v는 바뀌지 않는다)
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,

    // AXI4-Lite 슬레이브 (이름을 s_axi_*로 두면 패키저가 AXI 인터페이스로 묶는다)
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire [15:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [15:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready
);

    wire clk   = s_axi_aclk;
    wire rst_n = s_axi_aresetn;

    // ---------------- 공통 모듈 1: AXI4-Lite 핸드셰이크 ----------------
    wire        wr_en, rd_en;
    wire [15:0] wr_addr, rd_addr;
    wire [31:0] wr_data;
    wire [3:0]  wr_strb;
    reg  [31:0] rd_data;

    axil_slave #(.ADDR_W(16)) u_axil (
        .s_axi_aclk(s_axi_aclk),       .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr),   .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),     .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),   .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),     .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),   .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),     .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),   .s_axi_rready(s_axi_rready),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_strb(wr_strb),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    // ---------------- 공통 모듈 2: 표준 관리 영역 ----------------
    wire        std_hit;
    wire [31:0] std_rdata;
    wire        irq_unused;                        // 인터럽트가 없는 IP: 출력을 쓰지 않는다

    ip_std #(
        .IP_ID (32'h53454737),                     // "SEG7"
        .IP_MAJ(8'd1),
        .IP_MIN(8'd0),
        .N_IRQ (1)
    ) u_std (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr),
        .irq_set(1'b0),
        .std_hit(std_hit), .std_rdata(std_rdata),
        .irq(irq_unused)
    );

    // ---------------- 기능 레지스터 ----------------
    localparam [15:0] A_VALUE = 16'h0000;
    localparam [15:0] A_MODE  = 16'h0004;
    localparam [15:0] A_RAW   = 16'h0008;
    localparam [15:0] A_DP    = 16'h000C;

    reg [15:0] r_value;
    reg [3:0]  r_raw_en;
    reg [3:0]  r_blank;
    reg [31:0] r_raw;
    reg [3:0]  r_dp;

    // 바이트 단위 쓰기(wr_strb)를 반영하는 도우미 (ip_template.v와 같음)
    function [31:0] apply_strb(input [31:0] old_v, input [31:0] new_v, input [3:0] strb);
        integer b;
        begin
            apply_strb = old_v;
            for (b = 0; b < 4; b = b + 1)
                if (strb[b]) apply_strb[8*b +: 8] = new_v[8*b +: 8];
        end
    endfunction

    wire [31:0] mode_word  = {20'd0, r_blank, 4'd0, r_raw_en};
    wire [31:0] value_new  = apply_strb({16'd0, r_value}, wr_data, wr_strb);
    wire [31:0] mode_new   = apply_strb(mode_word, wr_data, wr_strb);
    wire [31:0] raw_new    = apply_strb(r_raw, wr_data, wr_strb);
    wire [31:0] dp_new     = apply_strb({28'd0, r_dp}, wr_data, wr_strb);

    always @(posedge clk) begin
        if (!rst_n) begin
            r_value  <= 16'd0;
            r_raw_en <= 4'd0;                      // 리셋 = L07과 같은 16진수 표시
            r_blank  <= 4'd0;
            r_raw    <= 32'd0;
            r_dp     <= 4'd0;
        end else if (wr_en) begin
            case (wr_addr)
                A_VALUE: r_value <= value_new[15:0];
                A_MODE: begin
                    r_raw_en <= mode_new[3:0];
                    r_blank  <= mode_new[11:8];
                end
                A_RAW:   r_raw   <= raw_new;
                A_DP:    r_dp    <= dp_new[3:0];
                default: ;                         // 없는 주소·관리 영역은 여기서 무시 (관리 영역은 ip_std가 받음)
            endcase
        end
    end

    // 읽기: 관리 영역이면 ip_std의 값, 아니면 기능 레지스터, 없는 주소는 0
    always @(*) begin
        if (std_hit) begin
            rd_data = std_rdata;
        end else begin
            case (rd_addr)
                A_VALUE: rd_data = {16'd0, r_value};
                A_MODE:  rd_data = mode_word;
                A_RAW:   rd_data = r_raw;
                A_DP:    rd_data = {28'd0, r_dp};
                default: rd_data = 32'd0;
            endcase
        end
    end

    // ---------------- 7세그먼트 구동 ----------------
    reg [17:0] refresh_cnt;
    always @(posedge clk) begin
        if (!rst_n)
            refresh_cnt <= 18'd0;
        else
            refresh_cnt <= refresh_cnt + 18'd1;
    end

    wire [1:0] digit_sel = refresh_cnt[17:16];     // L07과 같은 자리 전환

    // 지금 자리의 16진수, 원시 바이트, 방식, 끔, 소수점
    wire [3:0] hex_nib = r_value[4*digit_sel +: 4];
    wire [7:0] raw_byte = r_raw[8*digit_sel +: 8];
    wire       use_raw = r_raw_en[digit_sel];
    wire       blanked = r_blank[digit_sel];
    wire       dp_hex  = r_dp[digit_sel];

    // 16진수 1자리 → 켤 세그먼트 (active-high, [0] a … [6] g). L07 디코더와 같은 모양
    reg [6:0] hex_on;
    always @(*) begin
        case (hex_nib)
            4'h0: hex_on = 7'b0111111;
            4'h1: hex_on = 7'b0000110;
            4'h2: hex_on = 7'b1011011;
            4'h3: hex_on = 7'b1001111;
            4'h4: hex_on = 7'b1100110;
            4'h5: hex_on = 7'b1101101;
            4'h6: hex_on = 7'b1111101;
            4'h7: hex_on = 7'b0000111;
            4'h8: hex_on = 7'b1111111;
            4'h9: hex_on = 7'b1101111;
            4'hA: hex_on = 7'b1110111;
            4'hB: hex_on = 7'b1111100;
            4'hC: hex_on = 7'b0111001;
            4'hD: hex_on = 7'b1011110;
            4'hE: hex_on = 7'b1111001;
            default: hex_on = 7'b1110001;          // F
        endcase
    end

    wire [6:0] seg_on = use_raw ? raw_byte[6:0] : hex_on;
    wire       dp_on  = use_raw ? raw_byte[7]   : dp_hex;

    reg [3:0] an_sel;
    always @(*) begin
        case (digit_sel)
            2'd0:    an_sel = 4'b1110;
            2'd1:    an_sel = 4'b1101;
            2'd2:    an_sel = 4'b1011;
            default: an_sel = 4'b0111;
        endcase
    end

    // 보드는 active-low: 켤 비트를 뒤집는다. 끈 자리는 an을 모두 1로 (어느 자리도 켜지 않음)
    assign seg = ~seg_on;
    assign dp  = ~dp_on;
    assign an  = blanked ? 4'b1111 : an_sel;

endmodule
