#include <AppKit/AppKit.h>
#include <Cocoa/Cocoa.h>
#include <CoreGraphics/CoreGraphics.h>

typedef struct game_offscreen_buffer {
  void* memory;
  int width;
  int height;
  int pitch;
  int bytes_per_pixel;
} game_offscreen_buffer;

game_offscreen_buffer global_back_buffer = {0};
int initial_width = 800;
int initial_height = 600;

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


// GameView
@interface GameView : NSView
@end

@implementation GameView
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
  [self._window makeKeyAndOrderFront:nil];

  resize_back_buffer(&global_back_buffer, initial_width, initial_height);

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
