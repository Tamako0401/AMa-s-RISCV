# Run from any directory: nu --no-config-file scripts/test-reusable.nu
def main [] {
    let repo = ($env.FILE_PWD | path dirname)
    cd $repo
    mkdir build/reusable
    ^iverilog -g2012 -Wall -t null -f rtl/reusable.f
    if $env.LAST_EXIT_CODE != 0 { error make {msg: "RTL elaboration failed"} }
    for name in [storage alu peripherals memory periph_bus] {
        let top = $"($name)_tb"
        let output = $"build/reusable/($top).vvp"
        ^iverilog -g2012 -s $top -o $output -f rtl/reusable.f $"tests/reusable/($top).sv"
        if $env.LAST_EXIT_CODE != 0 { error make {msg: $"Compile failed: ($top)"} }
        ^vvp $output
        if $env.LAST_EXIT_CODE != 0 { error make {msg: $"Simulation failed: ($top)"} }
    }
    ^iverilog -g2012 -s spi_tb -o build/reusable/spi_tb.vvp rtl/perips/spi.v tests/reusable/spi_tb.sv
    if $env.LAST_EXIT_CODE != 0 { error make {msg: "Compile failed: spi_tb"} }
    ^vvp build/reusable/spi_tb.vvp
    if $env.LAST_EXIT_CODE != 0 { error make {msg: "Simulation failed: spi_tb"} }
    # RIB<->AXI 桥用行为从设备模型代替厂商 IP, 因此仍可在 iverilog 下回归。
    ^iverilog -g2012 -s axi_bridge_tb -o build/reusable/axi_bridge_tb.vvp -f rtl/reusable.f tests/reusable/axi_slave_model.sv tests/reusable/axi_bridge_tb.sv
    if $env.LAST_EXIT_CODE != 0 { error make {msg: "Compile failed: axi_bridge_tb"} }
    ^vvp build/reusable/axi_bridge_tb.vvp
    if $env.LAST_EXIT_CODE != 0 { error make {msg: "Simulation failed: axi_bridge_tb"} }
}
