# Standalone SPI pin timing; --modelsim also runs GPIO/UART peripheral tests.
def main [--modelsim] {
    let repo = ($env.FILE_PWD | path dirname)
    cd $repo
    mkdir build/spi
    if $modelsim {
        let sources = (open --raw rtl/reusable.f | lines | where {|line|
            ($line | str trim) != "" and not ($line | str starts-with "+")
        } | each {|line| $repo | path join $line })
        let spi_tb = ($repo | path join tests/reusable/spi_tb.sv)
        let periph_tb = ($repo | path join tests/reusable/peripherals_tb.sv)
        let runner = ($repo | path join tests/reusable/run.do | str replace --all '\' '/')
        mkdir build/spi/modelsim
        cd build/spi/modelsim
        if not ("modelsim.ini" | path exists) {
            ^vmap -c
            if $env.LAST_EXIT_CODE != 0 { error make {msg: "vmap failed"} }
        }
        if not ("work" | path exists) {
            ^vlib work
            if $env.LAST_EXIT_CODE != 0 { error make {msg: "vlib failed"} }
        }
        ^vlog -sv -work work ...$sources $spi_tb $periph_tb
        if $env.LAST_EXIT_CODE != 0 { error make {msg: "ModelSim compile failed"} }
        for top in [spi_tb peripherals_tb] {
            ^vsim -c -onfinish stop -voptargs=+acc $"work.($top)" -wlf $"($top).wlf" -l $"($top).log" -do $"set test_top ($top); do {($runner)}"
            if $env.LAST_EXIT_CODE != 0 { error make {msg: $"Simulation failed: ($top)"} }
        }
    } else {
        ^iverilog -g2012 -s spi_tb -o build/spi/spi_tb.vvp rtl/perips/spi.v tests/reusable/spi_tb.sv
        if $env.LAST_EXIT_CODE != 0 { error make {msg: "SPI compile failed"} }
        ^vvp build/spi/spi_tb.vvp
        if $env.LAST_EXIT_CODE != 0 { error make {msg: "SPI simulation failed"} }
    }
}
