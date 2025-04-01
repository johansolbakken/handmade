#include <AppKit/AppKit.h>
#include <Cocoa/Cocoa.h>
#include <CoreGraphics/CoreGraphics.h>
#include <AudioToolbox/AudioToolbox.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ctype.h>

#include "handmade.c"

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

// Global or static storage for the conversion factor:
static mach_timebase_info_data_t s_timebase_info;

static void init_timebase_info(void)
{
  // Only call this once
  if (s_timebase_info.denom == 0) {
    mach_timebase_info(&s_timebase_info);
  }
}

// Returns a high-resolution timestamp (like QPC)
// in “mach absolute time” units.
uint64_t mac_get_wall_clock(void)
{
  return mach_absolute_time();
}

// Converts an elapsed time in "mach absolute time" units
// to seconds (float or double).
double mac_get_seconds_elapsed(uint64_t start, uint64_t end)
{
  init_timebase_info();

  // “mach_absolute_time()” ticks need scaling by numer/denom for nanoseconds
  // Then convert nanoseconds to seconds.
  uint64_t elapsed = (end - start);
  double elapsedNs = (double)elapsed * (double)s_timebase_info.numer
    / (double)s_timebase_info.denom;
  double elapsedSec = elapsedNs * 1.0e-9;
  return elapsedSec;
}




// back buffer

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

typedef struct macos_sound_output {
  int samples_per_second;
  int bytes_per_sample;
  int buffer_count;
  AudioQueueBufferRef buffers[3];
  int current_buffer_index;
  int buffer_size_bytes;
} macos_sound_output;

static void dummy_audio_callback(void *userData,
                                 AudioQueueRef inAQ,
                                 AudioQueueBufferRef inBuffer)
{
    // Do nothing – all audio data is pushed from updateGame.
}


static void audio_callback(void *user_data,
                           AudioQueueRef inAQ,
                           AudioQueueBufferRef inBuffer)
{
    // Our audio state (could include sample rate, current time t, dt, etc.)
    audio_state *state = (audio_state *)user_data;

    // Calculate how many frames fit in the provided buffer.
    // (Each frame = 2 channels * 2 bytes = 4 bytes for 16-bit stereo.)
    int frame_count = inBuffer->mAudioDataBytesCapacity / 4;

    // Interpret the buffer’s mAudioData as int16_t samples.
    int16_t *samples = (int16_t *)inBuffer->mAudioData;

    // Build a game_sound_output_buffer structure to pass to our sound generation function.
    game_sound_output_buffer sound_buffer = {0};
    sound_buffer.samples_per_second = 48000;  // or use a field from your state if stored there
    sound_buffer.sample_count       = frame_count;
    sound_buffer.samples            = samples;

    // Call the game’s sound-generation function.
    game_output_sound(&sound_buffer);

    // Mark how many bytes we filled (frame_count frames * 4 bytes per frame)
    inBuffer->mAudioDataByteSize = frame_count * 4;

    // Re-enqueue the buffer for the next callback.
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
}


// State

game_offscreen_buffer global_back_buffer = {0};
audio_state global_audio_state = {0};
macos_sound_output sound_output = {0};
int initial_width = 800;
int initial_height = 600;

void init_audio(void)
{
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));

    // Configure for 16-bit stereo PCM.
    format.mSampleRate       = sound_output.samples_per_second; // e.g., 48000
    format.mFormatID         = kAudioFormatLinearPCM;
    format.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBitsPerChannel   = 16;
    format.mChannelsPerFrame = 2;
    format.mBytesPerFrame    = 4;  // 2 channels * 2 bytes each
    format.mFramesPerPacket  = 1;
    format.mBytesPerPacket   = format.mBytesPerFrame;

    // Create the AudioQueue and pass our audio_callback.
    OSStatus status = AudioQueueNewOutput(&format,
                                          audio_callback,        // use our real callback
                                          &global_audio_state,   // pass audio state as userData
                                          CFRunLoopGetCurrent(), // use current run loop
                                          kCFRunLoopCommonModes,
                                          0,
                                          &global_audio_state.queue);
    check_error(status, "AudioQueueNewOutput");
    if (status != noErr) return;

    // Set initial time values (if your game_output_sound uses them)
    global_audio_state.t  = 0;
    global_audio_state.dt = 1.0 / format.mSampleRate;

    // Allocate some buffers. The AudioQueue will call our callback when it needs data.
    // For example, allocate 3 buffers each holding ~0.1 second of audio.
    float seconds_per_buffer = 0.1f;
    int frames_per_buffer = (int)(sound_output.samples_per_second * seconds_per_buffer);
    int bytes_per_buffer  = frames_per_buffer * format.mBytesPerFrame;

    // (You can store buffers here if needed, but for pull model, the callback
    // simply reuses each buffer as it is returned.)
    for (int i = 0; i < 3; i++)
    {
        status = AudioQueueAllocateBuffer(global_audio_state.queue,
                                          bytes_per_buffer,
                                          &global_audio_state.buffers[i]);
        check_error(status, "AudioQueueAllocateBuffer");
        if (status != noErr) return;

        // Prime the queue by calling our callback manually for each buffer.
        audio_callback(&global_audio_state, global_audio_state.queue, global_audio_state.buffers[i]);
    }

    status = AudioQueueStart(global_audio_state.queue, NULL);
    check_error(status, "AudioQueueStart");
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

  sound_output.samples_per_second = 48000;
  sound_output.bytes_per_sample = sizeof(int16) * 2;

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

  // Set up the back buffer for rendering.
  game_offscreen_buffer buffer = {0};
  buffer.memory = global_back_buffer.memory;
  buffer.width = global_back_buffer.width;
  buffer.height = global_back_buffer.height;
  buffer.pitch = global_back_buffer.pitch;
  buffer.bytes_per_pixel = global_back_buffer.bytes_per_pixel;

  // Update game logic and render graphics.
  // (Now game_update_and_render should only update the back buffer.)
  game_update_and_render(&buffer);

  // Request a redraw.
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
