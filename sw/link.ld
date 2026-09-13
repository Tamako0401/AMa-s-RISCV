OUTPUT_ARCH(riscv)  /* 告诉ld是锐克五架构 */
ENTRY(_start)       /* 指定程序入口是符号_start。（定义在启动汇编文件中）。cpu上电/复位以后，PC跳转到_start开始执行. */

MEMORY              /* 声明内存 */
{
    RAM (rwx) : 0RIGIN = 0x80000000, LENGTH = 64K
    /*可以读写执行: 从0x0开始, 大小为64k. */
    /*必须和实际使用的硬件相匹配. */
}
/* 栈顶位置。从ram结束的地方开始. */
/* 64k = 2^6  2^10= 2^16.这里是0x10000 */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);
/* 锐克5栈从高地址往下增长. 所以栈顶初始化在内存最末端 * /
/* 在启动汇编文件中要把栈指针初始化到这个地址. */

SECTIONS
{
    .text : {
        *(.text.init)       /* 把.text.init段放在最前面*/
        *(.text .text.*)    /* 其余所有的函数代码（编译器生成的指令）*/
        *(.rodata.rodata.*) /* 只读数据也放在.text 段*/
        . = ALIGN(4);       /* 当前地址对齐到4字节边界：锐克五指令固定4字节宽。如果不对齐会读错位 */
    } > RAM
    
    .data : {               /* 已经初始化的全局变量 */
        . = ALIGN(4);
        *(.data .data.*)
        . = ALIGN(4);
    } > RAM

    .bss : {                /* 没有初始化的全局变量 */
        . = ALIGN(4);
        _bss_start =.;
        *(.bss .bss.*)
        *(COMMON)
        .= ALIGN(4);
        _bss_end = .;       /*打两个符号，这一段地址需要在启动汇编脚本在跳转到main之前清零：否则不进行初始化的变量初值读出将为不可预测的值*/
    } > RAM

    _end = .;               /*.bss结束后的地址一般是堆的起点。从_end往上增长*/

}