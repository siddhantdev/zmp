const std = @import("std");
const ma = @cImport({
    @cInclude("miniaudio.h");
});
const util = @import("util.zig");
const sound = @import("sound.zig");
const vaxis = @import("vaxis");

const ArrayList = std.ArrayList;

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

const bg_color: vaxis.Color = .rgbFromUint(0x1F1F1F);
const text_color: vaxis.Color = .rgbFromUint(0xEEEEEE);
const bg_style: vaxis.Style = .{ .bg = bg_color };
const list_item_style: vaxis.Style = .{ .bg = bg_color, .fg = text_color };
const header_item_style: vaxis.Style = .{ .bg = bg_color, .fg = text_color, .bold = true };
const selected_item_style: vaxis.Style = .{ .bg = text_color, .fg = bg_color };

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    none,
};

const CursorState = enum {
    FilesCursor,
    QueueCursor,
};

pub fn main() !void {
    try sound.init_engine();
    defer sound.deinit_engine();
    defer sound.deinit_sound();

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
        if (entry.kind == .file and try util.is_audio_file(entry.name))
            try files.append(allocator, entry.name);
    }

    var queue: ArrayList([]const u8) = .empty;
    defer queue.deinit(allocator);

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

    var selected_index_files: usize = 0;
    var selected_index_queue: usize = 0;
    var currently_playing_index: usize = 0;
    var cursor_state: CursorState = .FilesCursor;
    while (true) {
        const event = if (loop.tryEvent()) |evt| evt else .none;
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
                    break;
                } else if (key.matches('l', .{}) and cursor_state == .FilesCursor) {
                    try queue.append(allocator, files.items[selected_index_files]);
                } else if (key.matches('l', .{ .shift = true })) {
                    cursor_state = if (cursor_state == .FilesCursor) .QueueCursor else .FilesCursor;
                } else if (key.matches('h', .{ .shift = true })) {
                    cursor_state = if (cursor_state == .FilesCursor) .QueueCursor else .FilesCursor;
                } else if (key.matches('j', .{})) {
                    if (cursor_state == .FilesCursor) {
                        selected_index_files += 1;
                        if (selected_index_files == files.items.len) {
                            selected_index_files = 0;
                        }
                    } else {
                        selected_index_queue += 1;
                        if (selected_index_queue == queue.items.len) {
                            selected_index_queue = 0;
                        }
                    }
                } else if (key.matches('k', .{})) {
                    if (cursor_state == .FilesCursor) {
                        if (selected_index_files > 0) {
                            selected_index_files -= 1;
                        } else {
                            selected_index_files = files.items.len - 1;
                        }
                    } else {
                        if (selected_index_queue > 0) {
                            selected_index_queue -= 1;
                        } else {
                            selected_index_queue = queue.items.len - 1;
                        }
                    }
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    if (cursor_state == .FilesCursor) {
                        std.debug.assert(0 <= selected_index_files and selected_index_files < files.items.len);
                        try sound.play_file(try allocator.dupeZ(u8, files.items[selected_index_files]));
                        try queue.append(allocator, files.items[selected_index_files]);
                        currently_playing_index = queue.items.len - 1;
                    } else {
                        std.debug.assert(0 <= selected_index_queue and selected_index_queue < queue.items.len);
                        try sound.play_file(try allocator.dupeZ(u8, queue.items[selected_index_queue]));
                        currently_playing_index = selected_index_queue;
                    }
                } else if (key.matches('x', .{}) and cursor_state == .QueueCursor and selected_index_queue != currently_playing_index) {
                    _ = queue.orderedRemove(selected_index_queue);
                    if (selected_index_queue < currently_playing_index) {
                        currently_playing_index -= 1;
                    }
                    if (selected_index_queue >= queue.items.len) {
                        selected_index_queue = queue.items.len - 1;
                    }
                }
            },
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            else => {},
        }

        const win = vx.window();
        win.clear();

        win.fill(vaxis.Cell{
            .style = bg_style,
        });

        const col_width = (win.width - 6) / 4;
        const file_header_child = win.child(.{
            .x_off = 3,
            .y_off = 2,
            .height = 1,
            .width = col_width,
        });
        file_header_child.fill(.{ .style = bg_style });
        _ = file_header_child.printSegment(.{
            .text = "Files",
            .style = header_item_style,
        }, .{ .col_offset = col_width / 2 - 2 });

        renderList(
            win,
            files,
            file_header_child.x_off,
            col_width,
            .{
                .active = (cursor_state == .FilesCursor),
                .index = selected_index_files,
                .list_type = .FilesCursor,
                .playing_index = null,
            },
        );

        const queue_header_child = win.child(.{
            .x_off = 3 + col_width,
            .y_off = 2,
            .height = 1,
            .width = col_width,
        });
        queue_header_child.fill(.{ .style = bg_style });
        _ = queue_header_child.printSegment(.{
            .text = "Queue",
            .style = header_item_style,
        }, .{ .col_offset = col_width / 2 - 2 });

        renderList(
            win,
            queue,
            queue_header_child.x_off + 1,
            col_width,
            .{
                .active = (cursor_state == .QueueCursor),
                .index = selected_index_queue,
                .list_type = .QueueCursor,
                .playing_index = currently_playing_index,
            },
        );

        const player_header_child = win.child(.{
            .x_off = 3 + 2 * col_width,
            .y_off = 2,
            .height = 1,
            .width = col_width * 2,
        });
        player_header_child.fill(.{ .style = bg_style });
        _ = player_header_child.printSegment(.{
            .text = "Player",
            .style = header_item_style,
        }, .{ .col_offset = col_width - 3 });

        if (sound.is_sound_finished() and currently_playing_index < queue.items.len - 1) {
            currently_playing_index += 1;
            try sound.play_file(try allocator.dupeZ(u8, queue.items[currently_playing_index]));
        }

        var total_len_s = sound.get_sound_len();

        if (total_len_s > 0) {
            var duration_finished_s = sound.get_sound_done();
            const duration_ratio = duration_finished_s / total_len_s;

            const duration_finished_m = @floor(duration_finished_s / 60);
            duration_finished_s = @rem(duration_finished_s, 60);

            const total_len_m = @floor(total_len_s / 60);
            total_len_s = @rem(total_len_s, 60);

            const duration_finished_text = try std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2.0}", .{ duration_finished_m, duration_finished_s });
            const total_duration_text = try std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2.0}", .{ total_len_m, total_len_s });

            const bar_width: f32 = @floatFromInt(col_width * 2 - 20);
            const done_width: u16 = @intFromFloat(duration_ratio * bar_width);
            const bar_child = win.child(.{
                .x_off = 3 + 2 * col_width + 2 + @as(i17, @intCast(duration_finished_text.len)),
                .y_off = win.height - 6,
                .height = 1,
                .width = @intFromFloat(bar_width),
            });
            bar_child.fill(.{ .style = selected_item_style });

            const done_text_child = win.child(.{
                .x_off = 3 + 2 * col_width + 1,
                .y_off = bar_child.y_off,
                .height = 1,
            });
            _ = done_text_child.printSegment(.{
                .text = duration_finished_text,
                .style = list_item_style,
            }, .{});

            const total_text_child = win.child(.{
                .x_off = bar_child.x_off + bar_child.width + 1,
                .y_off = bar_child.y_off,
                .height = 1,
            });
            _ = total_text_child.printSegment(.{
                .text = total_duration_text,
                .style = list_item_style,
            }, .{});

            const done_bar_child = win.child(.{
                .x_off = bar_child.x_off,
                .y_off = bar_child.y_off,
                .height = 1,
                .width = done_width,
            });
            done_bar_child.fill(.{ .style = .{ .bg = .rgbFromUint(0xFF5F5F) } });

            const name = sound.get_sound_name();
            const name_child = win.child(.{
                .x_off = player_header_child.x_off + (player_header_child.width - @as(u16, @intCast(name.len))) / 2,
                .y_off = bar_child.y_off - 2,
                .height = 1,
            });
            _ = name_child.printSegment(.{
                .text = name,
                .style = list_item_style,
            }, .{});
        }

        try vx.render(tty.writer());
    }
}

const RenderListOpts = struct {
    index: usize,
    active: bool,
    list_type: CursorState,
    playing_index: ?usize,

    pub fn init(
        index: usize,
        active: bool,
        list_type: CursorState,
        playing_index: ?usize,
    ) RenderListOpts {
        return RenderListOpts{
            .index = index,
            .active = active,
            .list_type = list_type,
            .playing_index = playing_index,
        };
    }
};

fn renderList(
    win: vaxis.Window,
    list: std.ArrayList([]const u8),
    x_off: i17,
    width: u16,
    opts: RenderListOpts,
) void {
    var y_offset: i17 = 3;
    const item_height = 1;

    for (list.items, 0..) |item, i| {
        const item_child = win.child(.{
            .x_off = x_off,
            .y_off = y_offset,
            .width = width,
            .height = item_height,
            .border = .{ .where = .none },
        });

        const style = if (opts.active and i == opts.index) selected_item_style else list_item_style;

        item_child.fill(vaxis.Cell{
            .style = style,
        });
        _ = item_child.printSegment(.{
            .text = item,
            .style = style,
        }, .{});

        if (opts.list_type == .QueueCursor and i == opts.playing_index.?) {
            _ = item_child.printSegment(.{
                .text = "<",
                .style = style,
            }, .{ .col_offset = item_child.width - 2 });
        }

        y_offset += item_height;
    }
}
