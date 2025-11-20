const std = @import("std");
const debug = std.debug;
const assert = std.debug.assert;
const math = std.math;

const mcz = @import("mcz");
const Connection = mcz.Connection;
const Coordinate = mcz.Coordinate;

pub fn main() !void {
    var conn = try Connection.new();
    conn.init();

    try conn.postToChat("Hello!");
    try conn.doCommand("say Hello!");

    try conn.setPlayerPosition(.{ .x = 4, .y = 87, .z = 8 });

    const player = try conn.getPlayerPosition();
    const tile = player.add(.{ .x = 0, .y = -1, .z = 0 });
    debug.print("player: {f}\n", .{player});

    try conn.setBlock(tile, mcz.blocks.STONE);

    {
        const height = try conn.getHeight(player.flat());
        debug.print("height: {}\n", .{height});
    }
    {
        const block = try conn.getBlock(tile);
        debug.print("block: {f}\n", .{block});
    }

    {
        const origin = Coordinate{ .x = 0, .y = 90, .z = 0 };
        const bound = origin.add(.{ .x = 1, .y = 1, .z = -1 });

        var blocks = try conn.getBlocks(origin, bound);
        debug.print("blocks {f}:\n", .{blocks.size});
        while (try blocks.next()) |block| {
            debug.print("  - {f}\n", .{block});
        }

        var heights = try conn.getHeights(origin.flat(), bound.flat());
        debug.print("heights {f}:\n", .{heights.size});
        while (try heights.next()) |height| {
            debug.print("  - {}\n", .{height});
        }
    }

    {
        const origin = Coordinate{ .x = 3, .y = 90, .z = 0 };
        const bound = origin.add(.{ .x = 1, .y = 1, .z = -1 });

        try conn.setBlocks(origin, bound, mcz.blocks.DIRT);
    }
}
