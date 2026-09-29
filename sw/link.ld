OUTPUT_ARCH(riscv)  /* 告诉ld是锐克五架构 */
ENTRY(_start)       /* 指定程序入口是符号_start. (定义在启动汇编文件中). cpu上电/复位以后, PC跳转到_start开始执行. */

/* 哈佛式存储器: 指令和数据分开, 与 rtl/core/rib.v 的从设备译码一致.
 *   ROM 0x0000_0000, 64 KiB, 只读 -- 放指令和只读数据, 也是复位向量
 *   RAM 0x1000_0000, 64 KiB, 读写 -- 放已初始化/未初始化变量和栈
 * 每个设备占 addr[31:28] 一个档位(256 MiB 窗口).
 * (tests/cpu/link.ld 会把 RAM 窗口的第 0 个字留给回归测试台的"结束信箱",
 *  因此那边可用 RAM 从 +4 开始; 本文件面向实机程序, 不保留该信箱.)
 */
MEMORY              /* 声明内存 */
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K
    /* 必须和实际使用的硬件相匹配. */
}
/* 栈顶位置. 从ram结束的地方开始. */
/* 64k = 2^6 * 2^10 = 2^16. 这里是0x10000 */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);
/* 锐克5栈从高地址往下增长. 所以栈顶初始化在内存最末端 */
/* 在启动汇编文件中要把栈指针初始化到这个地址. */

SECTIONS
{
    .tohost : {
        *(.tohost)           /* 现在在0x10000000了 */
    } > RAM
    .text : {
        *(.text.init)
        *(.text .text.*)     /* 其余所有的函数代码(编译器生成的指令) */
        *(.rodata .rodata.*) /* 只读数据也放在.text 段*/
        . = ALIGN(4);        /* 当前地址对齐到4字节边界: 锐克五指令固定4字节宽. 如果不对齐会读错位 */
    } > ROM                  /* 指令放只读的 ROM */

    .data : {                /* 已经初始化的全局变量 */
        . = ALIGN(4);
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
    } > RAM

    .bss : {                 /* 没有初始化的全局变量 */
        . = ALIGN(4);
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;        /* 打两个符号, 这一段地址需要在启动汇编脚本在跳转到main之前清零. 否则不进行初始化的变量初值读出将为不可预测的值 */
    } > RAM

    _end = .;                /* .bss 结束后的地址一般是堆的起点. 从_end往上增长 */

}
