#define NOB_IMPLEMENTATION
#include "nob.h"

#define BUILD_FOLDER "build/"
#define SRC_FOLDER   "src/"

int main(int argc, char **argv)
{
    NOB_GO_REBUILD_URSELF(argc, argv);

    if (!nob_mkdir_if_not_exists(BUILD_FOLDER)) return 1;

    Nob_Cmd cmd = {0};
    nob_cmd_append(&cmd,
                   "cc",
                   "-Wall", "-Wextra", "-Wpedantic", "-std=c99",
                   "-framework", "Cocoa",
                   "-framework", "OpenGL",
                   "-framework", "IOKit",
                   "-framework", "AudioToolbox",
                   "-framework", "CoreGraphics",
                   "-o", BUILD_FOLDER"handmade",
                   SRC_FOLDER"macos_main.m",
                   SRC_FOLDER"handmade.c");
    if (!nob_cmd_run_sync_and_reset(&cmd)) return 1;

    return 0;
}
