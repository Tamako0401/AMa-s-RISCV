# 把位流下载到 FPGA 的 SRAM (断电丢失)。PDS Fabric Configuration 的批处理脚本,
# 百分号 s 占位符由 cdt_cfg_shell -args 依次替换 (注释里也算, 所以这里不写出来)。
# 用法: cdt_cfg_shell -file program.tcl -args {<位流>}
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
cfg_assign_file -file %s
cfg_program
cfg_disconnect
