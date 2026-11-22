# (추가) 20장: p3_npu_axi_lite를 Vivado IP(component.xml)로 패키징한다.
# Vivado가 원본을 IP 폴더 src/로 복사하므로 IP 폴더는 저장소에 두지 않는 빌드 산출물이다(정본은 각 장 rtl/).
# 사용: vivado -mode batch -source package_ip.tcl -tclargs <part03 경로> <임시 프로젝트 폴더> <IP 출력 폴더>
set part03 [file normalize [lindex $argv 0]]
set work [lindex $argv 1]
set ipdir [file normalize [lindex $argv 2]]
create_project -force p3_npu_ip $work -part xc7a35tcpg236-1
add_files -norecurse [list \
  $part03/ch02/rtl/dsp_multiplier.v $part03/mini_npu/rtl/npu_dsp_mac_lane.v \
  $part03/ch04/rtl/bram_sync_buffer.v $part03/ch14/rtl/p3_group10_core.v \
  $part03/ch17/rtl/p3_tile784_10.v $part03/ch20/rtl/p3_npu_axi_lite.v]
set_property top p3_npu_axi_lite [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $ipdir -vendor user.org -library p3 -taxonomy /UserIP -import_files false
set core [ipx::current_core]
set_property name p3_npu_axi_lite $core
set_property display_name "P3 NPU AXI4-Lite (784x10 tile NPU)" $core
set_property description "Part03 ch20 AXI4-Lite control/status slave around ch17 tile controller" $core
set_property version 1.0 $core
set_property core_revision 1 $core
# 인터럽트 출력을 interrupt 인터페이스로 묶는다(레벨, 높음 활성)
ipx::infer_bus_interface irq_o xilinx.com:signal:interrupt_rtl:1.0 $core
set_property value LEVEL_HIGH [ipx::add_bus_parameter SENSITIVITY [ipx::get_bus_interfaces irq_o -of_objects $core]]
ipx::associate_bus_interfaces -busif s_axi -clock s_axi_aclk $core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
foreach bi [ipx::get_bus_interfaces -of_objects $core] { puts "BUSIF [get_property name $bi] [get_property bus_type_vlnv $bi]" }
foreach mm [ipx::get_memory_maps -of_objects $core] {
  foreach ab [ipx::get_address_blocks -of_objects $mm] { puts "ADDRBLOCK [get_property name $ab] range=[get_property range $ab]" }
}
puts "IP_PACKAGE_DONE"
