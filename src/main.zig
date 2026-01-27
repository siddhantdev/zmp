const std = @import("std");
const ma = @cImport({
    @cInclude("miniaudio.h");
});
const sound = @import("sound.zig");

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

pub fn main() !void {
    if (std.os.argv.len != 2) {
        try stdout.print("Please provide file location\n", .{});
        try stdout.flush();
        return;
    }

    try sound.init_engine();
    defer sound.deinit_engine();

    const sound_file = std.os.argv[1];
    try sound.play_file(sound_file, stdout);
    try sound.play_file(sound_file, stdout);
}
