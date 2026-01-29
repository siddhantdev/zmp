const std = @import("std");

pub fn is_audio_file(filepath: []const u8) !bool {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var buffer: [256]u8 = undefined;
    _ = try file.read(&buffer);

    // Magic Numbers obtained from https://en.wikipedia.org/wiki/List_of_file_signatures
    const magic_numbers: [3][]const u8 = .{
        &.{ 0x49, 0x44, 0x33 }, // MP3
        &.{ 0x66, 0x4C, 0x61, 0x43 }, // FLAC
        &.{ 0x52, 0x49, 0x46, 0x46 }, // WAV
    };

    for (magic_numbers) |seq| {
        if (std.mem.eql(u8, buffer[0..seq.len], seq)) {
            return true;
        }
    }

    return false;
}
