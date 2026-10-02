
difftest firmware="smoke":
    {{justfile_directory()}}/scripts/difftest.bash {{firmware}}


# 如果本机不使用riscv-elf-gcc进行编译, 请设置RISCV_CC环境变量.

cc := env_var_or_default("RISCV_CC", "riscv64-elf-gcc")
sw_cflags := "-march=rv32i_zicsr -mabi=ilp32 -O2 -nostdlib -ffreestanding -Wall -Wextra"
sw_inc := "-Isw/device -Isw/drivers -Isw/bsp -Isw/components/lcd"
sw_lib := "sw/startup.S sw/drivers/spi.c sw/bsp/bsp.c sw/bsp/bsp_lcd.c sw/components/lcd/lcd.c sw/components/lcd/st7789.c sw/components/lcd/ili9341.c"


# 编译 sw/app/<name>/*.c -> build/app/<name>/<name>.elf

app name="lcd_demo" flags="":
    cd {{justfile_directory()}} && mkdir -p build/app/{{name}} && \
        {{cc}} {{sw_cflags}} {{flags}} {{sw_inc}} -T sw/link.ld {{sw_lib}} sw/app/{{name}}/*.c \
            -o build/app/{{name}}/{{name}}.elf
