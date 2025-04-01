#pragma once

#include <stdint.h>

#define internal static
#define local_persist static
#define global_variable static

typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef uint64_t uint64;

typedef int8_t int8;
typedef int16_t int16;
typedef int32_t int32;
typedef int64_t int64;
typedef int32_t bool32;

typedef float real32;
typedef double real64;

typedef struct game_offscreen_buffer {
  void* memory;
  int width;
  int height;
  int pitch;
  int bytes_per_pixel;
} game_offscreen_buffer;

internal void game_update_and_render(game_offscreen_buffer *buffer);
