# 电脑版: make 然后 build/touhou 或 build/fruit。core/ 是板上也用的游戏逻辑, pc/ 是电脑后端 (SDL2), 素材由 tools/assets.py 生成
UV ?= uv run
CFLAGS = -std=c11 -O2 -g -Wall -Wextra -Icore -Ipc -Ibuild -I../sw/components/sd $(shell pkg-config --cflags sdl2)
LDLIBS = $(shell pkg-config --libs sdl2)

CORE = $(wildcard core/*.c)
PC = pc/media_pc.c ../sw/components/sd/pak.c pc/app.c pc/gfx_mem.c pc/hand_udp.c pc/render.c pc/stats.c # 两个游戏共用; pc/<游戏>_pc.c 各一个
DEPS = ../sw/components/sd/pak.h $(CORE) $(PC) build/assets.c $(wildcard core/*.h pc/*.h)

all: build/touhou build/fruit

build/%: pc/%_pc.c $(DEPS)
	$(CC) $(CFLAGS) -o $@ $< $(CORE) $(PC) build/assets.c $(LDLIBS)

build/assets.c build/assets.h: tools/assets.py $(wildcard assets/*.png)
	$(UV) tools/assets.py build

# 板上 (sw/app/game) 要的: 图案编号的头文件, 和开机写进显示的素材 (调色板 + 256 色图案库)
board: build/assets.h build/display_assets.c

build/display_assets.c: tools/refmodel.py tools/assets.py $(wildcard assets/*.png)
	$(UV) tools/refmodel.py firmware -o $@

# core/ 不能依赖电脑上的东西: 单独编一遍, 只给 core/ 和生成的素材头文件
check-core: build/assets.h
	$(CC) -std=c11 -Wall -Wextra -Werror -ffreestanding -fsyntax-only -Icore -Ibuild $(CORE)

# 真实 FAT32 镜像 + C 解析器/SD协议/板上媒体代码; 需 mkfs.fat、ffmpeg、C 编译器。
check-sd:
	$(UV) tests/test_pak.py

clean:
	rm -rf build

.PHONY: all board check-core check-sd clean
