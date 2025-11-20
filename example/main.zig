const std = @import("std");
const debug = std.debug;
const assert = std.debug.assert;
const math = std.math;

const mcz = @import("mcz");
const Connection = mcz.Connection;

pub fn main() !void {
    var conn = try Connection.new();
    conn.init();

    try conn.postToChat("Hello!");
    try conn.doCommand("say Hello!");

    try conn.setPlayerPosition(.{
        .x = 4,
        .y = 87,
        .z = 8,
    });

    const player = try conn.getPlayerPosition();
    debug.print("player: {},{},{}\n", player);

    const tile = mcz.Coordinate{
        .x = player.x,
        .y = player.y - 1,
        .z = player.z,
    };

    try conn.setBlock(tile, .{ .id = 1, .mod = 0 });

    const height = try conn.getHeight(.{ .x = player.x, .z = player.z });
    debug.print("height: {}\n", .{height});

    const block = try conn.getBlock(tile);
    debug.print("block: {}:{}\n", block);

    var blocks = try conn.getBlocks(
        .{ .x = 0, .y = 90, .z = 0 },
        .{ .x = 1, .y = 91, .z = -1 },
    );
    debug.print("blocks:\n", .{});
    while (try blocks.next()) |b| {
        debug.print("  - {}:{}\n", b);
    }

    var heights = try conn.getHeights(
        .{ .x = 0, .z = 0 },
        .{ .x = 1, .z = -1 },
    );
    debug.print("heights:\n", .{});
    while (try heights.next()) |h| {
        debug.print("  - {}\n", .{h});
    }

    try conn.setBlocks(
        .{ .x = 3, .y = 90, .z = 0 },
        .{ .x = 4, .y = 91, .z = -1 },
        .{ .id = 3, .mod = 0 },
    );
}
