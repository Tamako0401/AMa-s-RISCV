# Invoke from any directory. See docs/cpu-baseline.md for prerequisites.
def main [--quick, --vcd, --modelsim] {
    let repo = ($env.FILE_PWD | path dirname)
    cd $repo
    let args = ([
        (if $quick { "--quick" } else { null })
        (if $vcd { "--vcd" } else { null })
        (if $modelsim { "--modelsim" } else { null })
    ] | compact)
    ^python scripts/test-cpu.py ...$args
    if $env.LAST_EXIT_CODE != 0 { error make {msg: "CPU regression failed"} }
}
