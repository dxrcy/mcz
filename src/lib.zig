const connection = @import("connection.zig");
pub const Connection = connection.Connection;
pub const BlockStream = connection.BlockStream;

pub const Coordinate = struct {
    x: i32,
    y: i32,
    z: i32,
};

pub const Size = struct {
    x: u32,
    y: u32,
    z: u32,
};

pub const Block = struct {
    // Fields must be larger than `u8` to hold newer blocks
    id: u32,
    mod: u32,
};
