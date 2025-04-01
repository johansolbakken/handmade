#include "handmade.h"

#include <math.h>

internal void game_output_sound(game_sound_output_buffer *sound_buffer)
{
    // Persist the sine wave phase across calls.
    local_persist float t_sine = 0.0f;
    int16_t tone_volume = 3000;
    int tone_hz = 256;
    int wave_period = sound_buffer->samples_per_second / tone_hz;

    int16_t *sample_out = sound_buffer->samples;

    for (int sample_index = 0; sample_index < sound_buffer->sample_count; sample_index++) {
        float sine_value = sinf(t_sine);
        int16_t sample_value = (int16_t)(sine_value * tone_volume);
        // For stereo, write the same sample for both channels.
        *sample_out++ = sample_value;
        *sample_out++ = sample_value;

        t_sine += 2.0f * M_PI / (float)wave_period;
    }
}

internal void render_weird_gradient(game_offscreen_buffer *buffer, int blue_offset,
                                    int green_offset) {
  uint8 *row = (uint8 *)buffer->memory;
  for (int y = 0; y < buffer->height; y++) {
    uint32 *pixel = (uint32 *)row;

    for (int x = 0; x < buffer->width; x++) {
      uint8 blue = (x + blue_offset);
      uint8 green = (y + green_offset);
      *pixel++ = ((green << 8) | blue);
    }

    row += buffer->pitch;
  }
}

internal void game_update_and_render(game_offscreen_buffer *buffer) {
  int blue_offset = 0;
  int green_offset = 0;
  render_weird_gradient(buffer, blue_offset, green_offset);
}
