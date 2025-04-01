#include <AppKit/AppKit.h>
#include <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(strong) NSWindow *_window;
@property(strong) NSTimer *_game_timer;

@property BOOL _should_close;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSRect frame = NSMakeRect(100, 100, 800, 600);

  self._should_close = NO;

  NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                     NSWindowStyleMaskResizable;
  self._window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:style
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];

  [self._window setTitle:@"Game Title"];
  [self._window makeKeyAndOrderFront:nil];

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
