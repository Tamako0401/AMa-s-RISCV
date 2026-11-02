# 电脑版: make 然后 build/touhou 或 build/fruit。core/ 是板上也用的游戏逻辑, pc/ 是电脑后端 (SDL2), 素材由 tools/assets.py 生成
# 不叫 UV: uv 跑脚本时会设环境变量 UV (指向 uv 本身), 会顶掉这里
UV_RUN ?= uv run
CFLAGS = -std=c11 -O2 -g -Wall -Wextra -Icore -Ipc -Ibuild -I../sw/components/sd $(shell pkg-config --cflags sdl2)
LDLIBS = $(shell pkg-config --libs sdl2)

CORE = $(wildcard core/*.c)
PC = media_audio.c pc/audio_sdl.c pc/media_pc.c ../sw/components/sd/pak.c pc/app.c pc/gfx_mem.c pc/hand_udp.c pc/render.c pc/stats.c # 两个游戏共用; pc/<游戏>_pc.c 各一个
DEPS = media_audio.h ../sw/components/sd/pak.h $(CORE) $(PC) build/assets.c $(wildcard core/*.h pc/*.h)

all: build/touhou build/fruit

build/%: pc/%_pc.c $(DEPS)
	$(CC) $(CFLAGS) -o $@ $< $(CORE) $(PC) build/assets.c $(LDLIBS)

build/assets.c build/assets.h: tools/assets.py $(wildcard assets/*.png)
	$(UV_RUN) tools/assets.py build

# 板上 (sw/app/game) 要的: 图案编号的头文件, 和开机写进显示的素材 (调色板 + 256 色图案库)
board: build/assets.h build/display_assets.c

build/display_assets.c: tools/refmodel.py tools/assets.py $(wildcard assets/*.png)
	$(UV_RUN) tools/refmodel.py firmware -o $@

# core/ 不能依赖电脑上的东西: 单独编一遍, 只给 core/ 和生成的素材头文件
check-core: build/assets.h
	$(CC) -std=c11 -Wall -Wextra -Werror -ffreestanding -fsyntax-only -Icore -Ibuild $(CORE)

# 真实 FAT32 镜像 + C 解析器/SD协议/板上媒体代码; 需 mkfs.fat、ffmpeg、C 编译器。
check-sd:
	$(UV_RUN) tests/test_pak.py

clean:
	rm -rf build

.PHONY: all board check-core check-sd clean

build/audio_test: test/audio_test.c pc/audio_sdl.c pc/audio_sdl.h core/sound.h
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -o $@ test/audio_test.c pc/audio_sdl.c $(LDLIBS)

build/sound_test: test/sound_test.c core/sound.c core/sound.h core/mix.c core/mix.h
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -o $@ test/sound_test.c core/sound.c core/mix.c

build/mix_test: test/mix_test.c core/mix.c core/mix.h
	$(CC) $(CFLAGS) -o $@ test/mix_test.c core/mix.c

build/mix_sdl_test: test/mix_sdl_test.c pc/media_pc.c pc/audio_sdl.c core/mix.c core/sound.c media_audio.c ../sw/components/sd/pak.c build/assets.h
	$(CC) $(CFLAGS) -o $@ test/mix_sdl_test.c pc/media_pc.c pc/audio_sdl.c core/mix.c core/sound.c media_audio.c ../sw/components/sd/pak.c $(LDLIBS)

check-audio: build/audio_test build/sound_test build/mix_test build/mix_sdl_test
	./build/audio_test
	./build/sound_test
	./build/mix_test
	./build/mix_sdl_test

.PHONY: check-audio
