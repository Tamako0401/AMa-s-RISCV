# 电脑版: make 然后 build/touhou 或 build/fruit。core/ 是板上也用的游戏逻辑, pc/ 是电脑后端 (SDL2), 素材由 tools/assets.py 生成
CFLAGS = -std=c11 -O2 -g -Wall -Wextra -Icore -Ipc -Ibuild $(shell pkg-config --cflags sdl2)
LDLIBS = $(shell pkg-config --libs sdl2)

CORE = $(wildcard core/*.c)
PC = pc/app.c pc/gfx_mem.c pc/hand_udp.c pc/render.c pc/stats.c # 两个游戏共用; pc/<游戏>_pc.c 各一个
DEPS = $(CORE) $(PC) build/assets.c $(wildcard core/*.h pc/*.h)

all: build/touhou build/fruit

build/%: pc/%_pc.c $(DEPS)
	$(CC) $(CFLAGS) -o $@ $< $(CORE) $(PC) build/assets.c $(LDLIBS)

build/assets.c build/assets.h: tools/assets.py $(wildcard assets/*.png)
	uv run tools/assets.py build

# core/ 不能依赖电脑上的东西: 单独编一遍, 只给 core/ 和生成的素材头文件
check-core: build/assets.h
	$(CC) -std=c11 -Wall -Wextra -Werror -ffreestanding -fsyntax-only -Icore -Ibuild $(CORE)

clean:
	rm -rf build

.PHONY: all check-core clean
