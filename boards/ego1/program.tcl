# 把位流下载到指定器件。给了 flash 型号就先写进板上 SPI flash, 再从 flash 启动 (断电不丢);
# 不给只下载到 SRAM (断电丢失)。
# 用法: vivado -mode batch -source program.tcl -tclargs <位流> <part> [<flash 型号>]
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
# 硬件管理器的 PART 只有芯片型号, board.toml 还带封装和速度等级。
set devices {}
foreach device [get_hw_devices] {
    if {[string match "[get_property PART $device]*" [lindex $argv 1]]} {
        lappend devices $device
    }
}
set dev [lindex $devices 0]
current_hw_device $dev
set bit [file normalize [lindex $argv 0]]
if {$argc > 2} {
    set mcs [file rootname $bit].mcs
    write_cfgmem -force -format mcs -size 4 -interface SPIx1 -loadbit "up 0x0 $bit" -file $mcs
    create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts [lindex $argv 2]] 0]
    set mem [get_property PROGRAM.HW_CFGMEM $dev]
    set_property PROGRAM.FILES [list $mcs] $mem
    set_property PROGRAM.ADDRESS_RANGE use_file $mem
    set_property PROGRAM.BLANK_CHECK 0 $mem
    set_property PROGRAM.ERASE 1 $mem
    set_property PROGRAM.CFG_PROGRAM 1 $mem
    set_property PROGRAM.VERIFY 1 $mem
    # 写 flash 要先往 FPGA 里下载一个 Vivado 自带的桥接位流
    create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
    program_hw_devices $dev
    program_hw_cfgmem -hw_cfgmem $mem
    boot_hw_device $dev
    refresh_hw_device $dev
} else {
    set_property PROGRAM.FILE $bit $dev
    program_hw_devices $dev
}
puts "DONE PROGRAMMED: [get_property REGISTER.IR.BIT5_DONE $dev]"
close_hw_target
# 关掉 hw_server, 否则它会一直占着 3121 和 3001
disconnect_hw_server
close_hw_manager
