#ifndef GAME_MEDIA_AUDIO_H
#define GAME_MEDIA_AUDIO_H
#include "pak.h"
void media_audio_init(pak_t *pak, void (*skip)(const char *name));
#endif
