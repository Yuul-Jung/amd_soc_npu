// =====================================================================
// ip_std.v  —  IP 표준 공통 모듈 2/2 (C·N 공통, 표준 개정 1)
//
// 모든 표준 IP가 64 KB 창의 맨 끝 16바이트에 같은 관리 레지스터 4개를 갖게 한다.
//
//   0xFFF0  ID          읽기     IP 종류 이름 4글자 (ASCII, 첫 글자가 [31:24])
//   0xFFF4  VER         읽기     [31:24] 표준 개정 번호 (이 파일의 STD_REV)
//                                [23:16] 0
//                                [15:8]  IP 주 버전, [7:0] IP 부 버전
//   0xFFF8  IRQ_STATUS  읽기/쓰기 인터럽트 원인 비트. 1을 쓴 비트만 0으로 지워진다(W1C)
//   0xFFFC  IRQ_ENABLE  읽기/쓰기 1인 비트의 원인만 irq 출력으로 나간다
//
//   irq = |(IRQ_STATUS & IRQ_ENABLE)   (레벨, 1 = 요청)
//
// 사용자 IP는 원인이 생길 때 irq_set의 해당 비트를 1클록 1로 올린다.
// 같은 클록에 지우기(W1C)와 새 원인이 겹치면 새 원인이 이긴다(사건을 잃지 않는다).
// 인터럽트가 없는 IP는 N_IRQ = 1, irq_set = 0으로 두고 irq 출력을 쓰지 않는다.
//
// 기능 레지스터는 0x0000부터 사용자 IP가 둔다. 0xFFF0~0xFFFF는 이 모듈 몫이다.
// =====================================================================
module ip_std #(
    parameter [31:0]  IP_ID   = "TMPL",           // 4글자. Verilog 문자열은 첫 글자가 위쪽 바이트
    parameter [7:0]   IP_MAJ  = 8'd1,
    parameter [7:0]   IP_MIN  = 8'd0,
    parameter integer N_IRQ   = 1                 // 인터럽트 원인 수 1~16
) (
    input  wire                 clk,
    input  wire                 rst_n,
    // axil_slave의 사용자 쪽 신호를 그대로 받는다
    input  wire                 wr_en,
    input  wire [15:0]          wr_addr,
    input  wire [31:0]          wr_data,
    input  wire [15:0]          rd_addr,
    // 인터럽트 원인 (1클록 펄스 또는 레벨, 1인 동안 계속 세운다)
    input  wire [N_IRQ-1:0]     irq_set,
    // 읽기 결과: std_hit = 1이면 사용자 IP는 rd_data로 std_rdata를 내보낸다
    output wire                 std_hit,
    output reg  [31:0]          std_rdata,
    output wire                 irq
);

    localparam [7:0] STD_REV = 8'd1;              // 표준 개정. 공통 모듈을 고치면 올린다

    // 주소 폭은 표준으로 16비트 고정 (64 KB 창)
    localparam [15:0] A_ID     = 16'hFFF0;
    localparam [15:0] A_VER    = 16'hFFF4;
    localparam [15:0] A_STATUS = 16'hFFF8;
    localparam [15:0] A_ENABLE = 16'hFFFC;

    reg [N_IRQ-1:0] irq_status;
    reg [N_IRQ-1:0] irq_enable;

    // 상태: 지울 비트를 먼저 빼고 새 원인을 더한다 → 겹치면 새 원인이 남는다
    wire [N_IRQ-1:0] w1c = (wr_en && wr_addr == A_STATUS) ? wr_data[N_IRQ-1:0] : {N_IRQ{1'b0}};

    always @(posedge clk) begin
        if (!rst_n) begin
            irq_status <= {N_IRQ{1'b0}};
            irq_enable <= {N_IRQ{1'b0}};
        end else begin
            irq_status <= (irq_status & ~w1c) | irq_set;
            if (wr_en && wr_addr == A_ENABLE) begin
                irq_enable <= wr_data[N_IRQ-1:0];
            end
        end
    end

    assign irq = |(irq_status & irq_enable);

    // 맨 끝 16바이트(0xFFF0~0xFFFF)이면 관리 영역
    assign std_hit = (rd_addr[15:4] == 12'hFFF);

    always @(*) begin
        case (rd_addr)
            A_ID:     std_rdata = IP_ID;
            A_VER:    std_rdata = {STD_REV, 8'd0, IP_MAJ, IP_MIN};
            A_STATUS: std_rdata = {{(32-N_IRQ){1'b0}}, irq_status};
            A_ENABLE: std_rdata = {{(32-N_IRQ){1'b0}}, irq_enable};
            default:  std_rdata = 32'd0;
        endcase
    end

endmodule
