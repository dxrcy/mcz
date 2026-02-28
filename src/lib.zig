//! MCZ: A Zig rewrite of [mcpp](https://github.com/rozukke/mcpp), a library to
//! interface with Minecraft.
//!
//! Requires a server running [ELCI](https://github.com/rozukke/elci).
//!
//! Usage example:
//!
//! ```zig
//! pub fn main() !void {
//!     var conn = try mcz.Connection.new();
//!     conn.init();
//!     try conn.postToChat("Hello!");
//! }
//! ```

const std = @import("std");
const Io = std.Io;

pub const Connection = @import("Connection.zig");
pub const BlockStream = Connection.BlockStream;
pub const HeightStream = Connection.HeightStream;

pub const blocks = @import("blocks.zig");

const BLOCK_ARRAY = blk: {
    var array: [@typeInfo(blocks).@"struct".decls.len]struct { []const u8, Block } = undefined;
    for (@typeInfo(blocks).@"struct".decls, 0..) |decl, i|
        array[i] = .{ decl.name, @field(blocks, decl.name) };
    break :blk array;
};

/// A worldspace or offset coordinate in the Minecraft world.
pub const Coordinate = struct {
    x: i32,
    y: i32,
    z: i32,

    pub fn flat(coordinate: Coordinate) Coordinate2D {
        return .{ .x = coordinate.x, .z = coordinate.z };
    }

    pub fn add(lhs: Coordinate, rhs: Coordinate) Coordinate {
        return .{
            .x = lhs.x + rhs.x,
            .y = lhs.y + rhs.y,
            .z = lhs.z + rhs.z,
        };
    }

    pub fn format(coordinate: Coordinate, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{},{},{}", .{ coordinate.x, coordinate.y, coordinate.z });
    }
};

/// A worldspace or offset coordinate in the Minecraft world, with no `y`-value.
pub const Coordinate2D = struct {
    x: i32,
    z: i32,

    pub fn withHeight(coordinate: Coordinate2D, height: i32) Coordinate {
        return .{ .x = coordinate.x, .y = height, .z = coordinate.z };
    }

    pub fn add(lhs: Coordinate2D, rhs: Coordinate2D) Coordinate2D {
        return .{
            .x = lhs.x + rhs.x,
            .z = lhs.z + rhs.z,
        };
    }

    pub fn format(coordinate: Coordinate2D, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{},{}", .{ coordinate.x, coordinate.z });
    }
};

/// 3D size of a cuboid, in blocks.
pub const Size = struct {
    x: u32,
    y: u32,
    z: u32,

    pub fn flat(size: Size) Size2D {
        return Size2D{ .x = size.x, .z = size.z };
    }

    pub fn between(origin: Coordinate, bound: Coordinate) Size {
        return .{
            .x = @abs(origin.x - bound.x) + 1,
            .y = @abs(origin.y - bound.y) + 1,
            .z = @abs(origin.z - bound.z) + 1,
        };
    }

    pub fn format(size: Size, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{}x{}x{}", .{ size.x, size.y, size.z });
    }
};

/// 2D size of a rectangle, in blocks.
pub const Size2D = struct {
    x: u32,
    z: u32,

    pub fn withHeight(size: Size2D, height: u32) Size {
        return .{ .x = size.x, .y = height, .z = size.z };
    }

    pub fn between(origin: Coordinate2D, bound: Coordinate2D) Size2D {
        return .{
            .x = @abs(origin.x - bound.x) + 1,
            .z = @abs(origin.z - bound.z) + 1,
        };
    }

    pub fn format(size: Size2D, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{}x{}", .{ size.x, size.z });
    }
};

/// A Minecraft block, including `id` and `mod`.
pub const Block = struct {
    // Fields must be larger than `u8` to hold newer blocks
    /// Block identifier. Eg. 'Andesite' has id `1` (`1:5`).
    id: u32,
    /// Block modifier. Eg. 'Andesite' has modifier `5` (`1:5`).
    mod: u32,

    pub fn withMod(block: Block, mod: u32) Block {
        return .{ .id = block.id, .mod = mod };
    }

    /// Get name of block matching `id` **and** `mod`.
    ///
    /// Note that, since `mod` can either represent a "different block" (eg.
    /// stone slab vs wooden slab) or a "modified block" (eg. different
    /// rotations), this method requires that `mod` values match exactly.
    pub fn nameExact(block: Block) ?[]const u8 {
        for (BLOCK_ARRAY) |item| {
            const name, const value = item;
            if (block.id == value.id and block.mod == value.mod)
                return name;
        }
        return null;
    }

    /// Get name of block matching `id` (even if `mod` differs).
    ///
    /// If an exact name exists (matching `id` **and** mod), then that is
    /// returned.
    /// Otherwise, find the first block (in declaration order) with a matching
    /// `id`, without considering `mod`.
    pub fn nameAny(block: Block) ?[]const u8 {
        if (block.nameExact()) |name| {
            return name;
        }
        for (BLOCK_ARRAY) |item| {
            const name, const value = item;
            if (block.id == value.id)
                return name;
        }
        return null;
    }

    pub fn format(block: Block, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{}:{}", .{ block.id, block.mod });
        if (block.nameExact()) |name| {
            try writer.print(" ({s})", .{name});
        }
    }
};
