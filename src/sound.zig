const std = @import("std");
const ma = @cImport({
    @cInclude("miniaudio.h");
});

var engine: ma.ma_engine = undefined;
var sound: ma.ma_sound = undefined;
var sound_init = false;
var sound_name: [*:0]u8 = undefined;

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

pub fn play_file(sound_file: [*:0]u8) !void {
    deinit_sound();
    var result: ma.ma_result = undefined;

    result = ma.ma_sound_init_from_file(&engine, sound_file, 0, null, null, &sound);
    if (result != ma.MA_SUCCESS) {
        return error.CouldNotLoadSound;
    }
    sound_init = true;
    sound_name = sound_file;

    _ = ma.ma_sound_start(&sound);
}

pub fn deinit_sound() void {
    if (sound_init) {
        ma.ma_sound_uninit(&sound);
        sound_init = false;
        sound_name = undefined;
    }
}

pub fn get_sound_done() f32 {
    if (!sound_init) return 0;
    var done: f32 = 0;
    _ = ma.ma_sound_get_cursor_in_seconds(&sound, &done);
    return done;
}

pub fn get_sound_len() f32 {
    if (!sound_init) return 0;
    var len: f32 = 0;
    _ = ma.ma_sound_get_length_in_seconds(&sound, &len);
    return len;
}

pub fn get_sound_name() []u8 {
    return std.mem.span(sound_name);
}

pub fn is_sound_finished() bool {
    return (ma.ma_sound_at_end(&sound) == 1);
}
