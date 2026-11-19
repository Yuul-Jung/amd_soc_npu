// =====================================================================
// axil_slave.v  —  IP 표준 공통 모듈 1/2 (C·N 공통, 표준 개정 1)
//
// AXI4-Lite 슬레이브 핸드셰이크만 맡는다. 레지스터는 갖지 않는다.
// 사용자 IP는 이 모듈이 내주는 간단한 신호만 보고 레지스터를 만든다.
//
//   쓰기: wr_en이 1클록 동안 1. 그 클록에 wr_addr·wr_data·wr_strb가 유효하다.
//   읽기: rd_en이 1클록 동안 1. 그 클록에 rd_addr이 유효하고,
//         사용자 IP는 rd_data를 같은 클록 안에 조합 회로로 내놓아야 한다.
//         (읽으면 지워지는 레지스터나 FIFO 꺼내기는 rd_en으로 한다)
//
// 지키는 AXI4-Lite 규칙
//   - 주소 채널과 데이터 채널이 둘 다 유효할 때 한 번에 받는다.
//   - 앞 응답(BVALID/RVALID)이 나가는 중에는 새 요청을 받지 않는다.
//   - 응답은 항상 OKAY(00). 없는 주소를 읽으면 사용자 IP가 0을 돌려준다.
//
// CPU와 무관하다. AXI4-Lite 마스터만 있으면 어떤 CPU(MicroBlaze V, PicoRV32,
// 자체 설계 CPU)에서도 그대로 쓴다. 레지스터는 32비트 단위로만 접근한다.
// =====================================================================
module axil_slave #(
    parameter integer ADDR_W = 16                 // 64 KB 창 전체 (표준)
) (
    input  wire                 s_axi_aclk,
    input  wire                 s_axi_aresetn,
    // 쓰기 주소
    input  wire [ADDR_W-1:0]    s_axi_awaddr,
    input  wire [2:0]           s_axi_awprot,
    input  wire                 s_axi_awvalid,
    output reg                  s_axi_awready,
    // 쓰기 데이터
    input  wire [31:0]          s_axi_wdata,
    input  wire [3:0]           s_axi_wstrb,
    input  wire                 s_axi_wvalid,
    output reg                  s_axi_wready,
    // 쓰기 응답
    output wire [1:0]           s_axi_bresp,
    output reg                  s_axi_bvalid,
    input  wire                 s_axi_bready,
    // 읽기 주소
    input  wire [ADDR_W-1:0]    s_axi_araddr,
    input  wire [2:0]           s_axi_arprot,
    input  wire                 s_axi_arvalid,
    output reg                  s_axi_arready,
    // 읽기 데이터
    output reg  [31:0]          s_axi_rdata,
    output wire [1:0]           s_axi_rresp,
    output reg                  s_axi_rvalid,
    input  wire                 s_axi_rready,

    // ---- 사용자 IP 쪽 ----
    output reg                  wr_en,            // 1클록 펄스
    output reg  [ADDR_W-1:0]    wr_addr,          // 하위 2비트는 항상 0
    output reg  [31:0]          wr_data,
    output reg  [3:0]           wr_strb,
    output wire                 rd_en,            // 1클록 펄스
    output reg  [ADDR_W-1:0]    rd_addr,          // 하위 2비트는 항상 0
    input  wire [31:0]          rd_data           // rd_addr에 해당하는 값 (조합 회로)
);

    assign s_axi_bresp = 2'b00;                   // OKAY
    assign s_axi_rresp = 2'b00;                   // OKAY

    // ---------------- 쓰기 ----------------
    // 받는 클록: AWREADY·WREADY를 함께 1로, 같은 클록에 wr_en을 1로.
    // 다음 클록: BVALID를 1로. BREADY를 받으면 내린다.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            wr_en         <= 1'b0;
            wr_addr       <= {ADDR_W{1'b0}};
            wr_data       <= 32'd0;
            wr_strb       <= 4'd0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            wr_en         <= 1'b0;

            if (!s_axi_awready && !s_axi_bvalid && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                wr_en         <= 1'b1;
                wr_addr       <= {s_axi_awaddr[ADDR_W-1:2], 2'b00};
                wr_data       <= s_axi_wdata;
                wr_strb       <= s_axi_wstrb;
            end

            if (s_axi_awready) begin
                s_axi_bvalid <= 1'b1;             // 받은 다음 클록에 응답
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ---------------- 읽기 ----------------
    // 받는 클록: ARREADY를 1로, 주소를 rd_addr에 잡는다.
    // 다음 클록(rd_en = 1): 사용자 IP의 rd_data를 RDATA에 잡고 RVALID를 1로.
    reg rd_stage;                                 // 1이면 이번 클록이 rd_en 클록

    assign rd_en = rd_stage;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            rd_addr       <= {ADDR_W{1'b0}};
            rd_stage      <= 1'b0;
        end else begin
            s_axi_arready <= 1'b0;
            rd_stage      <= 1'b0;

            if (!s_axi_arready && !rd_stage && !s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                rd_addr       <= {s_axi_araddr[ADDR_W-1:2], 2'b00};
                rd_stage      <= 1'b1;
            end

            if (rd_stage) begin
                s_axi_rdata  <= rd_data;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
