const std = @import("std");
const debug = std.debug;
const assert = std.debug.assert;
const math = std.math;

const mcz = @import("lib.zig");
const Connection = mcz.Connection;

pub fn main() !void {
    var conn = try Connection.new();
    conn.init();

    try conn.setPlayerPosition(.{ .x = 4, .y = 27, .z = 8 });

    const player = try conn.getPlayerPosition();
    debug.print("{}, {}, {}\n", player);

    const tile = mcz.Coordinate{
        .x = player.x,
        .y = player.y - 1,
        .z = player.z,
    };

    try conn.setBlock(tile, .{ .id = 1, .mod = 0 });

    const height = try conn.getHeight(player);
    debug.print("{}\n", .{height});

    const block = try conn.getBlock(tile);
    debug.print("{}:{}\n", block);

    var blocks = try conn.getBlocks(
        .{ .x = 0, .y = 30, .z = 0 },
        .{ .x = 1, .y = 31, .z = -1 },
    );
    while (try blocks.next()) |b| {
        debug.print("  - {}:{}\n", b);
    }

    try conn.setBlocks(
        .{ .x = 3, .y = 30, .z = 0 },
        .{ .x = 4, .y = 31, .z = -1 },
        .{ .id = 3, .mod = 0 },
    );
}
