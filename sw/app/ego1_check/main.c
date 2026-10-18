/* EGO1 自检: 屏幕颜色/边界、5 个按键、LED、计时、串口, 一次看全。
 * 屏幕: 上面红绿蓝三条色带, 最外圈 1 像素白框, 下面 5 个方块按十字排列对应 S4/S3/S2/S0/S1, 按下变白。
 * LED0~4 跟着 S0~S4, LED7 每秒翻转一次; 串口每秒打印一次按键状态。 */
#include "lcd.h"
#include "bsp.h"
#include "uart.h"

#ifdef BOARD_EGO1
static const uint32_t leds[] = { PIN_LD2_0, PIN_LD2_1, PIN_LD2_2, PIN_LD2_3, PIN_LD2_4, PIN_LD2_5, PIN_LD2_6, PIN_LD2_7 };
#else
static const uint32_t leds[] = { PIN_LED1, PIN_LED2, PIN_LED3, PIN_LED4, PIN_LED5, PIN_LED6, PIN_LED7, PIN_LED8 };
#endif

#ifdef BOARD_EGO1
#define KEY_UP PIN_S4
#define KEY_LEFT PIN_S3
#define KEY_START PIN_S2
#define KEY_RIGHT PIN_S0
#define KEY_DOWN PIN_S1
#else
#define KEY_UP PIN_KEY7
#define KEY_LEFT PIN_KEY5
#define KEY_START PIN_KEY2
#define KEY_RIGHT PIN_KEY8
#define KEY_DOWN PIN_KEY6
#endif

#define GRAY RGB565(48, 48, 48)

/* 方块位置按十字排列: 上 S4、左 S3、中 S2、右 S0、下 S1 */
static const struct { uint32_t pin; uint16_t x, y; } keys[] = {
    { KEY_UP,     58, 104 },
    { KEY_LEFT,   38, 124 },
    { KEY_START, 58, 124 },
    { KEY_RIGHT,  78, 124 },
    { KEY_DOWN,   58, 144 },
};

static void put_hex(uint32_t v)
{
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(CONSOLE_UART, "0123456789abcdef"[(v >> i) & 0xF]);
}

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    uart_puts(CONSOLE_UART, "EGO1 CHECK\r\n");
    for (uint32_t i = 0; i < 8; i++)
        io_dir(leds[i], IO_OUTPUT);

#ifdef BOARD_EGO1
    lcd_init_st7735(&(lcd_pins_t){ .sck = PIN_J5_1, .mosi = PIN_J5_2, .rst = PIN_J5_3,
                                   .dc = PIN_J5_4, .bl = PIN_J5_5, .cs = PIN_J5_6 });
#else
    lcd_init_st7789(&(lcd_pins_t){ .sck = PIN_J8_27, .mosi = PIN_J8_28, .cs = PIN_J8_23,
                                   .dc = PIN_J8_26, .rst = PIN_J8_25, .bl = PIN_J8_24 });
#endif
    lcd_fill(LCD_BLACK);
    lcd_fill_rect(0, 0, lcd_width(), 30, LCD_RED);
    lcd_fill_rect(0, 30, lcd_width(), 30, LCD_GREEN);
    lcd_fill_rect(0, 60, lcd_width(), 30, LCD_BLUE);
    lcd_draw_line(0, 0, lcd_width() - 1, 0, LCD_WHITE);
    lcd_draw_line(0, lcd_height() - 1, lcd_width() - 1, lcd_height() - 1, LCD_WHITE);
    lcd_draw_line(0, 0, 0, lcd_height() - 1, LCD_WHITE);
    lcd_draw_line(lcd_width() - 1, 0, lcd_width() - 1, lcd_height() - 1, LCD_WHITE);
    uart_puts(CONSOLE_UART, "LCD INIT DONE\r\n");

    uint32_t shown = ~0UL, last = bsp_cycles(), beat = 0;
    for (;;) {
        uint32_t btn = 0;
        for (uint32_t i = 0; i < 5; i++)
            btn |= (uint32_t)io_read(keys[i].pin) << i;
        if (btn != shown) {
            for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); i++)
                lcd_fill_rect(keys[i].x, keys[i].y, 12, 12, btn & (1UL << i) ? LCD_WHITE : GRAY);
            shown = btn;
        }
        uint32_t pattern = btn | (beat << 7);
        for (uint32_t i = 0; i < 8; i++)
            io_write(leds[i], (pattern >> i) & 1);
        if (bsp_cycles() - last >= SYSCLK_HZ) {
            last += SYSCLK_HZ;
            beat ^= 1;
            uart_puts(CONSOLE_UART, "btn=");
            put_hex(btn);
            uart_puts(CONSOLE_UART, "\r\n");
        }
    }
}
