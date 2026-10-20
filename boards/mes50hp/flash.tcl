# 把位流写进板上 QSPI flash (上电自动加载), 再下载到 SRAM 让它马上运行。
# PDS Fabric Configuration 的批处理脚本, 百分号 s 占位符由 cdt_cfg_shell -args 依次替换 (注释里也算)。
# 用法: cdt_cfg_shell -file flash.tcl -args {<位流> <sfc 文件> <flash 型号> <sfc 文件> <位流>}
cfg_gen_sfc -sbit %s -sfc %s -device_name %s
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
# 经 FPGA 的 JTAG 写 flash, 和 Fabric Configuration 界面里 Scan Outer Flash → Program 一样
cfg_jtag_flash_scan_device
cfg_jtag_flash_assign_file -file %s
cfg_jtag_flash_program
cfg_assign_file -file %s
cfg_program
cfg_disconnect
