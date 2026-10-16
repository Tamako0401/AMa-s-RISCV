    .section .text.init
    .globl _start

_start:
    /* 1. 设置栈指针 */
    la      sp, _stack_top      /* 把栈指针设置为_stack_top */

    /* 2. 把 .data 的初值从 ROM 拷到 RAM (复位后变量回到初值, 和单片机一样) */
    la      t0, _data_load      /* 源: 初值在 ROM 里的位置 (link.ld 的 LOADADDR) */
    la      t1, _data_start     /* 目的: 变量在 RAM 里的位置 */
    la      t2, _data_end
3:
    bgeu    t1, t2, 4f          /* 拷完了就跳到 4 */
    lw      t3, 0(t0)           /* 从 ROM 读一个字 (走 CPU 数据口, rib 允许数据口读 ROM) */
    sw      t3, 0(t1)           /* 写到 RAM */
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       3b
4:

    /* 3. 清零 .bss */
    la      t0, _bss_start      /* 设置两个寄存器的值为.bss起始位置 */
    la      t1, _bss_end
1:
    bge     t0, t1, 2f          /* branch if greater equal, if t0 >= t1, goto tag 2 forward 循环终止条件 */
    sw      zero, 0(t0)         /* store word, 将 0 存储到 t0+0 位置 */
    addi    t0, t0, 4           /* t0 increment by 4, 擦下一位 (一个word是4字节) */
    j       1b                  /* jump to 1 backword 无条件 */
2:

    /* 4. 进 main */
    call    main                /* 调用 C 中 main() */

    /* 5. main 返回后停住 */
halt:
    j       halt                /* 死在halt这里了 */
