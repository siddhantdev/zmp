const std = @import("std");
const ma = @cImport({
    @cInclude("miniaudio.h");
});
const sound = @import("sound.zig");
const vaxis = @import("vaxis");

const ArrayList = std.ArrayList;

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    foo: u8,
};

pub fn main() !void {
    try sound.init_engine();
    defer sound.deinit_engine();

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var files: ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".mp3") or std.mem.endsWith(u8, entry.name, ".wav"))
            try files.append(allocator, entry.name);
    }

    const list_item_style: vaxis.Style = .{ .bg = .rgbFromUint(0x000000), .fg = .rgbFromUint(0xFF0000) };
    const selected_item_style: vaxis.Style = .{ .bg = .rgbFromUint(0xFFFFFF), .fg = .rgbFromUint(0xFF0000) };

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 250 * std.time.ns_per_ms);

    var selected_index: usize = 0;
    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else if (key.matches('j', .{})) {
                    selected_index += 1;
                    if (selected_index == files.items.len) {
                        selected_index = 0;
                    }
                } else if (key.matches('k', .{})) {
                    if (selected_index > 0)
                        selected_index -= 1;
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    std.debug.assert(0 <= selected_index and selected_index < files.items.len);
                    try sound.play_file(try allocator.dupeZ(u8, files.items[selected_index]));
                }
            },
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            else => {},
        }

        const win = vx.window();
        win.clear();

        var y_offset: i17 = 1;
        const item_height = 1;
        for (files.items, 0..) |file_name, i| {
            const file_child = win.child(.{ 
                .x_off = 2,
                .y_off = y_offset,
                .width = win.width / 2,
                .height = item_height,
                .border = .{ .where = .none },
            });
            file_child.fill(vaxis.Cell {
                .style = if (i == selected_index) selected_item_style else list_item_style,
            });
            _ = file_child.print(&.{.{
                .text = file_name,
                .style = if (i == selected_index) selected_item_style else list_item_style,
            }}, .{});
            y_offset += item_height;
        }

        try vx.render(tty.writer());
    }
}
