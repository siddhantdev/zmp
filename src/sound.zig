const std = @import("std");
const ma = @cImport({
    @cInclude("miniaudio.h");
});

var engine: ma.ma_engine = undefined;
var sound: ma.ma_sound = undefined;
var sound_init = false;

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
    var result: ma.ma_result = undefined;

    result = ma.ma_sound_init_from_file(&engine, sound_file, 0, null, null, &sound);
    if (result != ma.MA_SUCCESS) {
        return error.CouldNotLoadSound;
    }
    sound_init = true;

    _ = ma.ma_sound_start(&sound);
}

pub fn deinit_sound() void {
    if (sound_init) {
        ma.ma_sound_uninit(&sound);
        sound_init = false;
    }
}
