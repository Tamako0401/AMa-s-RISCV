
compile-arch flags="":
    cd {{justfile_directory()}}/sw && riscv64-elf-gcc -march=rv32i -mabi=ilp32 -O2 -nostdlib -ffreestanding {{flags}} -T link.ld startup.S main.c -o test.elf
compile-ubuntu flags="":
    cd {{justfile_directory()}}/sw && riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2 -nostdlib -ffreestanding {{flags}} -T link.ld startup.S main.c -o test.elf


run-spike:
    cd {{justfile_directory()}}/sw && spike -d --isa=rv32i test.elf










