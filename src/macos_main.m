#include <AppKit/AppKit.h>
#include <Cocoa/Cocoa.h>
#include <CoreGraphics/CoreGraphics.h>
#include <AudioToolbox/AudioToolbox.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <CoreFoundation/CoreFoundation.h>
#include <ctype.h>

static void check_error(OSStatus error, const char *operation) {
  if (error == noErr) return;
  char errorString[20];
  // See if the error is a 4-char-code
  *(uint32_t *)(errorString + 1) = CFSwapInt32HostToBig(error);
  if (isprint(errorString[1]) && isprint(errorString[2]) &&
      isprint(errorString[3]) && isprint(errorString[4])) {
    errorString[0] = errorString[5] = '\'';
    errorString[6] = '\0';
  } else {
    sprintf(errorString, "%d", (int)error);
  }
  fprintf(stderr, "[ERROR] %s: %s\n", operation, errorString);
}

// Wave generation functions:
static inline float sine_wave_sample(double t, double frequency) {
  return sin(2.0 * M_PI * frequency * t);
}

static inline float square_wave_sample(double t, double frequency) {
  float s = sin(2.0 * M_PI * frequency * t);
  return (s >= 0.0f) ? 1.0f : -1.0f;
}

static inline float variable_pitch_sine_sample(double t) {
  // Base frequency modulated by a slow sine function.
  double base_frequency = 440.0; // A4 note
  double modulation = 110.0;     // Frequency variation range
  double mod_rate = 0.5;         // Modulation frequency (Hz)
  double frequency = base_frequency + modulation * sin(2.0 * M_PI * mod_rate * t);
  return sin(2.0 * M_PI * frequency * t);
}

// back buffer

typedef struct game_offscreen_buffer {
  void* memory;
  int width;
  int height;
  int pitch;
  int bytes_per_pixel;
} game_offscreen_buffer;

void resize_back_buffer(game_offscreen_buffer* buffer, int width, int height) {
  if (buffer->memory) {
    free(buffer->memory);
  }

  buffer->width = width;
  buffer->height = height;
  buffer->bytes_per_pixel = 4; // RGBA
  buffer ->pitch = width * buffer->bytes_per_pixel;
  buffer->memory = malloc(width * height * buffer->bytes_per_pixel);

  memset(buffer->memory, 0, width * height *  buffer->bytes_per_pixel);
}

// audio state

typedef struct audio_state {
  AudioQueueRef queue;
  AudioQueueBufferRef buffers[3];
  double t; // running time (seconds)
  double dt; // time increment per sample (1/sample_rate)
} audio_state;

void audio_callback(void *in_user_data,
                    AudioQueueRef in_audio_queue,
                    AudioQueueBufferRef in_buffer) {
  audio_state* state = (audio_state*)in_user_data;
  int sample_count = in_buffer->mAudioDataByteSize / sizeof(float);
  float* samples = (float*)in_buffer->mAudioData;
  double t = state->t;
  double dt = state->dt;

  for (int i = 0; i < sample_count; i += 2) {
    // Using the square wave; change to sine_wave_sample or variable_pitch_sine_sample if desired.
    float sample_value = variable_pitch_sine_sample(t);
    samples[i]     = sample_value;
    samples[i + 1] = sample_value;
    t += dt;
  }
  state->t = t;

  in_buffer->mAudioDataByteSize = sample_count * sizeof(float);

  OSStatus enqueueStatus = AudioQueueEnqueueBuffer(in_audio_queue, in_buffer, 0, NULL);
  check_error(enqueueStatus, "AudioQueueEnqueueBuffer");


  // Debug print using stderr (unbuffered)
  static int callback_count = 0;
  callback_count++;
  if (callback_count % 100 == 0) {
    fprintf(stderr, "audio_callback called %d times\n", callback_count);
    fflush(stderr);
  }
}


// State

game_offscreen_buffer global_back_buffer = {0};
audio_state global_audio_state = {0};
int initial_width = 800;
int initial_height = 600;

void init_audio(void) {
  AudioStreamBasicDescription format;
  memset(&format, 0, sizeof(format));
  format.mSampleRate       = 48000;
  format.mFormatID         = kAudioFormatLinearPCM;
  format.mFormatFlags      = kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked;
  format.mBitsPerChannel   = 32;
  format.mChannelsPerFrame = 2; // Stereo
  format.mBytesPerFrame    = sizeof(float) * format.mChannelsPerFrame;
  format.mFramesPerPacket  = 1;
  format.mBytesPerPacket   = format.mBytesPerFrame;

  OSStatus status = AudioQueueNewOutput(&format, audio_callback,
                                        &global_audio_state,
                                        NULL, NULL, 0,
                                        &global_audio_state.queue);
  check_error(status, "AudioQueueNewOutput");
  if (status != noErr) return;

  global_audio_state.t  = 0;
  global_audio_state.dt = 1.0 / format.mSampleRate;

  int buffer_byte_size = (int)(format.mSampleRate * format.mBytesPerFrame * 0.1);
  for (int i = 0; i < 3; i++) {
    status = AudioQueueAllocateBuffer(global_audio_state.queue,
                                      buffer_byte_size,
                                      &global_audio_state.buffers[i]);
    check_error(status, "AudioQueueAllocateBuffer");
    if (status != noErr) return;

    // Fill the buffer manually (write your wave samples):
    float *samples = (float *)global_audio_state.buffers[i]->mAudioData;
    int sample_count = buffer_byte_size / sizeof(float);
    for (int s = 0; s < sample_count; s += 2) {
      float value = 0;
      samples[s]   = value;
      samples[s+1] = value;
      global_audio_state.t += global_audio_state.dt;
    }

    global_audio_state.buffers[i]->mAudioDataByteSize = (UInt32)(sample_count * sizeof(float));

    status = AudioQueueEnqueueBuffer(global_audio_state.queue,
                                     global_audio_state.buffers[i],
                                     0, NULL);
    check_error(status, "AudioQueueEnqueueBuffer");
  }

  status = AudioQueueStart(global_audio_state.queue, NULL);
  check_error(status, "AudioQueueStart");
  if (status != noErr) return;

  fprintf(stderr, "[INFO] Audio initialized successfully!\n");
  fflush(stderr);
}


// GameView
@interface GameView : NSView
@end

@implementation GameView
-(BOOL) acceptsFirstResponder {
  return YES;
}

-(void) keyDown:(NSEvent*) event {
  NSString* keyPressed = event.charactersIgnoringModifiers;
  NSLog(@"Key Down: %@", keyPressed);
}


- (void)keyUp:(NSEvent *)event {
  NSString *keyReleased = event.charactersIgnoringModifiers;
  NSLog(@"Key Up: %@", keyReleased);
}

- (void)mouseDown:(NSEvent *)event {
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  NSLog(@"Mouse Down at: %@", NSStringFromPoint(location));
}

- (void)mouseUp:(NSEvent *)event {
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  NSLog(@"Mouse Up at: %@", NSStringFromPoint(location));
}

- (void)mouseDragged:(NSEvent *)event {
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  NSLog(@"Mouse Dragged at: %@", NSStringFromPoint(location));
}

-(void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();

  CGContextRef context = CGBitmapContextCreate(
    global_back_buffer.memory, global_back_buffer.width,
    global_back_buffer.height,
    8, // bits per component
    global_back_buffer.pitch, color_space,
    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);

  CGImageRef image = CGBitmapContextCreateImage(context);

  CGContextRef current_context = [[NSGraphicsContext currentContext] CGContext];
  CGContextDrawImage(current_context, self.bounds, image);

  CGImageRelease(image);
  CGContextRelease(context);
  CGColorSpaceRelease(color_space);
}
@end

// AppDelegate
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(strong) NSWindow *_window;
@property(strong) NSTimer *_game_timer;

@property BOOL _should_close;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSRect frame = NSMakeRect(100, 100, initial_width, initial_height);

  self._should_close = NO;

  NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
    NSWindowStyleMaskResizable;
  self._window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:style
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];

  [self._window setTitle:@"Game Title"];

  GameView* game_view = [[GameView alloc] initWithFrame:frame];
  [self._window setContentView:game_view];
  [self._window makeFirstResponder:game_view];
  [self._window makeKeyAndOrderFront:nil];

  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp activateIgnoringOtherApps:YES];

  resize_back_buffer(&global_back_buffer, initial_width, initial_height);

  init_audio();

  self._game_timer =
    [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                     target:self
                                   selector:@selector(updateGame)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)updateGame {
  if (self._should_close) {
    [self._game_timer invalidate];
    self._game_timer = nil;
    [NSApp terminate:nil];
    return;
  }

  for (int y = 0; y < global_back_buffer.height; y++) {
    for (int x = 0; x < global_back_buffer.width; x++) {
      double r = (double) x / (double) global_back_buffer.width;
      double g = (double) y / (double) global_back_buffer.height;

      uint32_t color = 0xff000000;
      color |= (uint32_t)(255*r) << 16;
      color |= (uint32_t)(255*g) << 8;

      uint32_t* buffer = global_back_buffer.memory;
      buffer[x + y * global_back_buffer.width] = color;
    }
  }

  [[self._window contentView] setNeedsDisplay:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
  (NSApplication *)sender {
  return YES;
}

- (BOOL)windowShouldClose:(id)sender {
  self._should_close = YES;
  return YES;
}

@end

int main(void) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [app setDelegate:delegate];
    [app run];
  }

  return 0;
}
