const std = @import("std");
const ma = @cImport({
    @cInclude("miniaudio.h");
});

var engine: ma.ma_engine = undefined;

pub fn init_engine() !void {
    var result: ma.ma_result = undefined;

    result = ma.ma_engine_init(null, &engine);

    if (result != ma.MA_SUCCESS) {
        return error.CouldNotInitializeMAEngine;
    }
}

pub fn deinit_engine() void {
    ma.ma_engine_uninit(&engine);
}

pub fn play_file(sound_file: [*:0]u8, stdout: *std.Io.Writer) !void {
    var result: ma.ma_result = undefined;
    var sound: ma.ma_sound = undefined;

    result = ma.ma_sound_init_from_file(&engine, sound_file, 0, null, null, &sound);
    if (result != ma.MA_SUCCESS) {
        return error.CouldNotLoadSound;
    }
    defer ma.ma_sound_uninit(&sound);

    var song_length: f32 = 0.0;
    _ = ma.ma_sound_get_length_in_seconds(&sound, &song_length);
    try stdout.print("Playing {s} with duration: {d} seconds\n", .{sound_file, song_length});
    try stdout.flush();

    _ = ma.ma_sound_start(&sound);

    while (ma.ma_sound_is_playing(&sound) == 1) {}
}
