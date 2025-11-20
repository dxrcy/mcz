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

/// A worldspace or offset coordinate in the Minecraft world.
pub const Coordinate = struct {
    const Self = @This();

    x: i32,
    y: i32,
    z: i32,

    pub fn flat(self: Self) Coordinate2D {
        return Coordinate2D{ .x = self.x, .z = self.z };
    }

    pub fn add(lhs: Self, rhs: Self) Self {
        return Self{
            .x = lhs.x + rhs.x,
            .y = lhs.y + rhs.y,
            .z = lhs.z + rhs.z,
        };
    }

    pub fn format(self: Self, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{},{},{}", .{ self.x, self.y, self.z });
    }
};

/// A worldspace or offset coordinate in the Minecraft world, with no `y`-value.
pub const Coordinate2D = struct {
    const Self = @This();

    x: i32,
    z: i32,

    pub fn with_height(self: Self, height: i32) Coordinate {
        return Coordinate{ .x = self.x, .y = height, .z = self.z };
    }

    pub fn add(lhs: Self, rhs: Self) Self {
        return Self{
            .x = lhs.x + rhs.x,
            .z = lhs.z + rhs.z,
        };
    }

    pub fn format(self: Self, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{},{}", .{ self.x, self.z });
    }
};

/// 3D size of a cuboid, in blocks.
pub const Size = struct {
    const Self = @This();

    x: u32,
    y: u32,
    z: u32,

    pub fn flat(self: Self) Size2D {
        return Size2D{ .x = self.x, .z = self.z };
    }

    pub fn between(origin: Coordinate, bound: Coordinate) Self {
        return Self{
            .x = @abs(origin.x - bound.x) + 1,
            .y = @abs(origin.y - bound.y) + 1,
            .z = @abs(origin.z - bound.z) + 1,
        };
    }

    pub fn format(self: Self, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{}x{}x{}", .{ self.x, self.y, self.z });
    }
};

/// 2D size of a rectangle, in blocks.
pub const Size2D = struct {
    const Self = @This();

    x: u32,
    z: u32,

    pub fn with_height(self: Self, height: u32) Size {
        return Size{ .x = self.x, .y = height, .z = self.z };
    }

    pub fn between(origin: Coordinate2D, bound: Coordinate2D) Self {
        return Self{
            .x = @abs(origin.x - bound.x) + 1,
            .z = @abs(origin.z - bound.z) + 1,
        };
    }

    pub fn format(self: Self, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{}x{}", .{ self.x, self.z });
    }
};

/// A Minecraft block, including `id` and `mod`.
pub const Block = struct {
    const Self = @This();

    // Fields must be larger than `u8` to hold newer blocks
    /// Block identifier. Eg. 'Andesite' has id `1` (`1:5`).
    id: u32,
    /// Block modifier. Eg. 'Andesite' has modifier `5` (`1:5`).
    mod: u32,

    pub fn with_mod(self: Self, mod: u32) Self {
        return Self{ .id = self.id, .mod = mod };
    }

    /// Get name of block matching `id` **and** `mod`.
    ///
    /// Note that, since `mod` can either represent a "different block" (eg.
    /// stone slab vs wooden slab) or a "modified block" (eg. different
    /// rotations), this method requires that `mod` values match exactly.
    pub fn name_exact(self: Self) ?[]const u8 {
        inline for (@typeInfo(blocks).@"struct".decls) |decl| {
            const block = @field(blocks, decl.name);
            if (self.id == block.id and self.mod == block.mod) {
                return decl.name;
            }
        }
        return null;
    }

    /// Get name of block matching `id` (even if `mod` differs).
    ///
    /// If an exact name exists (matching `id` **and** mod), then that is
    /// returned.
    /// Otherwise, find the first block (in declaration order) with a matching
    /// `id`, without considering `mod`.
    pub fn name_any(self: Self) ?[]const u8 {
        if (self.name_exact()) |name| {
            return name;
        }
        inline for (@typeInfo(blocks).@"struct".decls) |decl| {
            const block = @field(blocks, decl.name);
            if (self.id == block.id) {
                return decl.name;
            }
        }
        return null;
    }

    pub fn format(self: Self, writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{}:{}", .{ self.id, self.mod });
        if (self.name_exact()) |name| {
            try writer.print(" ({s})", .{name});
        }
    }
};
