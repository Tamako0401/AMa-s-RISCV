/* bootloader 和 app 共用边界, 避免下载覆盖启动代码。 */
_rom_size = 0x10000;
_boot_size = 0x800;
_app_size = _rom_size - _boot_size;
_boot_start = _app_size;
