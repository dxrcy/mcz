const connection = @import("connection.zig");
pub const Connection = connection.Connection;
pub const BlockStream = connection.BlockStream;

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
};

pub const Coordinate2D = struct {
    const Self = @This();

    x: i32,
    z: i32,

    pub fn add(lhs: Self, rhs: Self) Self {
        return Self{
            .x = lhs.x + rhs.x,
            .z = lhs.z + rhs.z,
        };
    }
};

pub const Size = struct {
    const Self = @This();

    x: u32,
    y: u32,
    z: u32,

    pub fn flat(self: Self) Size2D {
        return Size2D{ .x = self.x, .z = self.z };
    }
};

pub const Size2D = struct {
    x: u32,
    z: u32,
};

pub const Block = struct {
    // Fields must be larger than `u8` to hold newer blocks
    id: u32,
    mod: u32,
};
