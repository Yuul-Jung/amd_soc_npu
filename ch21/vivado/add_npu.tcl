# 21장: 복제한 블록 설계(soc_npu)에 20장 AXI NPU를 모듈 참조로 넣고 주소를 배정한다.
# 전제: 제1부 11장 프로젝트를 File → Project → Save As로 복제했고, 블록 설계를 soc_npu로 저장(Save Block Design As)해 연 상태.
# 실행: Vivado Tcl Console에서  source <저장소>/ch21/vivado/add_npu.tcl
# ⚠ 미검증: 이 저장소 작성 환경에는 Vivado가 없다. 셀·세그먼트 이름은 Vivado 2024.2 화면에서 대조한다.

set root [file normalize [file join [file dirname [info script]] ../..]]

# 1) NPU RTL 6개 (20장 래퍼와 그 하위 모듈). 원본 장 폴더의 파일을 그대로 참조한다 (복사·수정 금지).
set npu_files [list \
    $root/ch01/rtl/mac_core.v \
    $root/ch04/rtl/bram_sync_buffer.v \
    $root/ch07/rtl/vector_dot_core.v \
    $root/ch16/rtl/npu_argmax.v \
    $root/ch19/rtl/npu_tiled_784_npe.v \
    $root/ch20/rtl/npu_axi_lite.v]
add_files -norecurse $npu_files
update_compile_order -fileset sources_1

# 2) 모듈 참조 셀. s_axi_* 포트 이름으로 AXI4-Lite 인터페이스 s_axi, s_axi_aclk·s_axi_aresetn이 클록·리셋으로 잡힌다.
create_bd_cell -type module -reference npu_axi_lite npu_0

# 3) 연결 자동화: MicroBlaze V 주변장치 버스에 S_AXI, 클록·리셋은 기존 도메인(100 MHz, rst_clk_wiz… 또는 proc_sys_reset)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/microblaze_riscv_0 (Periph)} Slave {/npu_0/s_axi} ddr_seg {Auto} intc_ip {Auto} master_apm {0} } \
    [get_bd_intf_pins npu_0/s_axi]

# 4) 주소: 0x44A0_0000부터 64KB (기존 GPIO 0x4000_0000, INTC 0x4120_0000 등과 겹치지 않음)
assign_bd_address -offset 0x44A00000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] \
    [get_bd_addr_segs npu_0/s_axi/reg0] -force

# 5) irq_o는 이 장에서 연결하지 않는다 (22장 드라이버는 STATUS 폴링). 27장에서 INTC 입력 추가를 검토한다.

validate_bd_design
save_bd_design
make_wrapper -files [get_files soc_npu.bd] -top -import

# 6) 사용자 Top과 제약. 복제해 온 기존 제약(basys3_soc11_top.xdc)은 Sources 창에서 Disable File로 끈다 (핀 중복 방지).
add_files -norecurse $root/ch21/rtl/soc_npu_top.v
add_files -fileset constrs_1 -norecurse $root/ch21/constraints/soc_npu.xdc
set_property top soc_npu_top [current_fileset]
update_compile_order -fileset sources_1
