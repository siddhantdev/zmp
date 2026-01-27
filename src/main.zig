const std = @import("std");
const ma = @cImport({
    @cInclude("miniaudio.h");
});

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

pub fn main() !void {
    var result: ma.ma_result = undefined;
    var engine: ma.ma_engine = undefined;

    result = ma.ma_engine_init(null, &engine);

    if (result != ma.MA_SUCCESS) {
        return error.CouldNotInitializeMAEngine;
    }
    defer ma.ma_engine_uninit(&engine);

    if (std.os.argv.len != 2) {
        try stdout.print("Please provide file location\n", .{});
        try stdout.flush();
        return;
    }

    const sound_file = std.os.argv[1];
    var sound: ma.ma_sound = undefined;

    result = ma.ma_sound_init_from_file(&engine, sound_file, 0, null, null, &sound);
    if (result != ma.MA_SUCCESS) {
        return error.CouldNotLoadSound;
    }
    defer ma.ma_sound_uninit(&sound);

    var song_length: f32 = 0.0;
    _ = ma.ma_sound_get_length_in_seconds(&sound, &song_length);

    _ = ma.ma_sound_start(&sound);

    std.debug.print("Playing {s} with duration: {d} seconds\n", .{sound_file, song_length});
    while (ma.ma_sound_is_playing(&sound) == 1) {}
}
