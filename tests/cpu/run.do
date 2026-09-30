onerror {quit -code 1}
onbreak {
    if {[examine -radix unsigned /cpu_tb/test_pass] != 1} {quit -code 1}
    quit -code 0
}
run -all
if {[examine -radix unsigned /cpu_tb/test_pass] != 1} {quit -code 1}
quit -code 0
