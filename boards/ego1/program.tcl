# 把位流下载到 JTAG 链上的第一块 xc7a35t (SRAM 配置, 断电丢失)
# 用法: vivado -mode batch -source program.tcl -tclargs <位流>
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE [file normalize [lindex $argv 0]] $dev
program_hw_devices $dev
puts "DONE PROGRAMMED: [get_property REGISTER.IR.BIT5_DONE $dev]"
close_hw_target
# 关掉 hw_server, 否则它会一直占着 3121 和 3001
disconnect_hw_server
close_hw_manager
