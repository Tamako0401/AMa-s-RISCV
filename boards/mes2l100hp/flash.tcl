# Write bitstream to the on-board QSPI flash (auto-load at power-up), then also
# download to SRAM so it runs right away.
# Batch script for PDS Fabric Configuration: each percent-s placeholder is
# replaced by cdt_cfg_shell -args in order (placeholders inside comments count
# too, so keep exactly 5 in the whole file).
# Usage: cdt_cfg_shell -file flash.tcl -args {<sbit> <sfc> <flash model> <sfc> <sbit>}
# NOTE: comments must stay ASCII: cdt re-encodes the file as GBK, and a Chinese
# UTF-8 trailing byte can swallow the following newline (observed: the
# cfg_jtag_flash_scan_device line vanished into the comment above it).
cfg_gen_sfc -sbit %s -sfc %s -device_name %s
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
# Erase/program the outer flash via FPGA JTAG, same as Scan Outer Flash + Program in the GUI
cfg_jtag_flash_scan_device
cfg_jtag_flash_assign_file -file %s
cfg_jtag_flash_program
cfg_assign_file -file %s
cfg_program
cfg_disconnect
