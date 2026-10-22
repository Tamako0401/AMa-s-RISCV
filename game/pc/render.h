#ifndef RENDER_H
#define RENDER_H

#include <SDL.h>
#include <stdint.h>

void render_init(SDL_Renderer *r);
void render_camera(const uint8_t *bgr); /* 摄像头小窗换一帧 (160x120, BGR) */
void render_frame(const char *shot); /* 照 gfx_mem 画一帧并显示; shot 不为 NULL 时顺便存成 BMP */

#endif
