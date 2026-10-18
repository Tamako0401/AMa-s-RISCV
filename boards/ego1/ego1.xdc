set_property PACKAGE_PIN P17 [get_ports clk]
set_property PACKAGE_PIN P15 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports {clk rst_n}]
create_clock -name sys_clk -period 10.000 [get_ports clk]
