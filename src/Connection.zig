const Self = @This();
const Connection = Self;

const std = @import("std");
const Io = std.Io;
const net = std.net;

const lib = @import("lib.zig");
const Coordinate = lib.Coordinate;
const Coordinate2D = lib.Coordinate2D;
const Size = lib.Size;
const Size2D = lib.Size2D;
const Block = lib.Block;

const Response = @import("Response.zig");

/// Default address and port for [ELCI](https://github.com/rozukke/elci) server.
pub const DEFAULT_ADDRESS = net.Address.parseIp("127.0.0.1", 4711) catch unreachable;

const WRITE_BUFFER_SIZE = 1024;
const READ_BUFFER_SIZE = 1024;

stream: net.Stream,
writer: net.Stream.Writer,
reader: net.Stream.Reader,
write_buffer: [WRITE_BUFFER_SIZE]u8,
read_buffer: [READ_BUFFER_SIZE]u8,

pub const MessageError =
    RequestError ||
    ResponseError;

pub const RequestError =
    Io.Writer.Error;

pub const ResponseError =
    Io.Reader.Error ||
    Response.Error ||
    error{StreamTooLong};

/// Create a new connection with `DEFAULT_ADDRESS`.
///
/// **Must call `init` after creation or relocation.**
pub fn new() net.TcpConnectToAddressError!Self {
    return Self.withAddress(DEFAULT_ADDRESS);
}

/// Create a new connection with a specified server address.
///
/// **Must call `init` after creation or relocation.**
pub fn withAddress(addr: net.Address) net.TcpConnectToAddressError!Self {
    const stream = try net.tcpConnectToAddress(addr);
    return Self{
        .stream = stream,
        .writer = undefined,
        .reader = undefined,
        .write_buffer = undefined,
        .read_buffer = undefined,
    };
}

/// Initialize writer and reader with correct internal references.
pub fn init(self: *Self) void {
    self.writer = self.stream.writer(&self.write_buffer);
    self.reader = self.stream.reader(&self.read_buffer);
}

fn recvNext(self: *Self, delimiter: u8) ResponseError!Response {
    const data = try self.reader.interface().takeDelimiterInclusive(delimiter);
    return Response.new(data);
}

fn writeSanitizedString(self: *Self, string: []const u8) RequestError!void {
    // Server parses based on newlines (0x0a). All other characters,
    // including comma, semicolon, and arbitrary UTF-8 should be safe.
    for (string) |char| {
        try self.writer.interface.print("{c}", .{
            if (char == '\n') ' ' else char,
        });
    }
}

/// Sends a message to the in-game chat.
///
/// Does **not** require that a player has joined.
pub fn postToChat(
    self: *Self,
    message: []const u8,
) RequestError!void {
    try self.writer.interface.print("chat.post(", .{});
    try self.writeSanitizedString(message);
    try self.writer.interface.print(")\n", .{});
    try self.writer.interface.flush();
}

/// Performs an in-game Minecraft command.
///
/// Players have to exist on the server and should be server operators (default
/// with [ELCI](https://github.com/rozukke/elci)).
pub fn doCommand(
    self: *Self,
    command: []const u8,
) RequestError!void {
    try self.writer.interface.print("player.doCommand(", .{});
    try self.writeSanitizedString(command);
    try self.writer.interface.print(")\n", .{});
    try self.writer.interface.flush();
}

/// Returns a `Coordinate` representing player position (block position of lower
/// half of playermodel).
pub fn getPlayerPosition(
    self: *Self,
) MessageError!Coordinate {
    try self.writer.interface.print(
        "player.getPos()\n",
        .{},
    );
    try self.writer.interface.flush();

    var response = try self.recvNext('\n');
    const x = try response.next(i32, ',');
    const y = try response.next(i32, ',');
    const z = try response.next(i32, '\n');
    try response.expectEnd();

    return Coordinate{ .x = x, .y = y, .z = z };
}

/// Sets player position (block position of lower half of playermodel) to
/// specified `Coordinate`.
pub fn setPlayerPosition(
    self: *Self,
    coordinate: Coordinate,
) RequestError!void {
    try self.writer.interface.print(
        "player.setPos({},{},{})\n",
        .{ coordinate.x, coordinate.y, coordinate.z },
    );
    try self.writer.interface.flush();
}

/// Returns `Block` object from specified `Coordinate`.
pub fn getBlock(
    self: *Self,
    coordinate: Coordinate,
) MessageError!Block {
    try self.writer.interface.print(
        "world.getBlockWithData({},{},{})\n",
        .{ coordinate.x, coordinate.y, coordinate.z },
    );
    try self.writer.interface.flush();

    var response = try self.recvNext('\n');
    const id = try response.next(u32, ',');
    const mod = try response.next(u32, '\n');
    try response.expectEnd();

    return Block{ .id = id, .mod = mod };
}

/// Sets block at `Coordinate` to specified `Block`.
pub fn setBlock(
    self: *Self,
    coordinate: Coordinate,
    block: Block,
) RequestError!void {
    try self.writer.interface.print(
        "world.setBlock({},{},{},{},{})\n",
        .{
            coordinate.x, coordinate.y, coordinate.z,
            block.id,     block.mod,
        },
    );
    try self.writer.interface.flush();
}

/// Returns a collection of the `Block`s in cuboid specified by `Coordinate`s
/// `origin` and `bound` (in any order).
///
/// Streams response to avoid allocation.
///
/// Note this means all blocks have to be read before other responses can be
/// read from the server; i.e. any subsequently-called method which reads a
/// server response (eg. `getBlock`) will block until *this* response is
/// completely read (when `BlockStream.next()` yeilds `null`).
pub fn getBlocks(
    self: *Self,
    origin: Coordinate,
    bound: Coordinate,
) MessageError!BlockStream {
    try self.writer.interface.print(
        "world.getBlocksWithData({},{},{},{},{},{})\n",
        .{
            origin.x, origin.y, origin.z,
            bound.x,  bound.y,  bound.z,
        },
    );
    try self.writer.interface.flush();

    return BlockStream{
        .connection = self,
        .origin = origin,
        .size = Size.between(origin, bound),
        .index = 0,
    };
}

/// Sets a cuboid of blocks to all be the specified `Block`, with the corners of
/// the cuboid specified by `Coordinate`s `origin` and `bound` (in any order).
pub fn setBlocks(
    self: *Self,
    origin: Coordinate,
    bound: Coordinate,
    block: Block,
) RequestError!void {
    try self.writer.interface.print(
        "world.setBlocks({},{},{},{},{},{},{},{})\n",
        .{
            origin.x, origin.y,  origin.z,
            bound.x,  bound.y,   bound.z,
            block.id, block.mod,
        },
    );
    try self.writer.interface.flush();
}

/// Returns the `y`-value of the highest solid block at the specified `x` and
/// `z` coordinate
///
/// **DO NOT USE FOR LARGE AREAS, IT WILL BE VERY SLOW** -- use `getHeights`
/// instead.
pub fn getHeight(
    self: *Self,
    coordinate: Coordinate2D,
) MessageError!i32 {
    try self.writer.interface.print(
        "world.getHeight({},{})\n",
        .{ coordinate.x, coordinate.z },
    );
    try self.writer.interface.flush();

    var response = try self.recvNext('\n');
    const height = try response.next(i32, '\n');
    try response.expectEnd();

    return height;
}

/// Returns a collection of the heightss in rectangle specified by
/// `Coordinate2D`s `origin` and `bound` (in any order).
///
/// Streams response to avoid allocation.
///
/// Note this means all blocks have to be read before other responses can be
/// read from the server; i.e. any subsequently-called method which reads a
/// server response (eg. `getBlock`) will block until *this* response is
/// completely read (when `BlockStream.next()` yeilds `null`).
pub fn getHeights(
    self: *Self,
    origin: Coordinate2D,
    bound: Coordinate2D,
) RequestError!HeightStream {
    try self.writer.interface.print(
        "world.getHeights({},{},{},{})\n",
        .{
            origin.x, origin.z,
            bound.x,  bound.z,
        },
    );
    try self.writer.interface.flush();

    return HeightStream{
        .connection = self,
        .origin = origin,
        .size = Size2D.between(origin, bound),
        .index = 0,
    };
}

/// A stream of `Block`s in a cuboid, returned by `Connection.getBlocks`.
///
/// **Mutating or relocating the parent `Connection` invalidates an instance of
/// this type.**
pub const BlockStream = struct {
    connection: *Connection,
    origin: Coordinate,
    size: Size,
    index: usize,

    pub fn next(self: *BlockStream) ResponseError!?Block {
        if (self.is_at_end()) {
            return null;
        }
        self.index += 1;

        const delim: u8 = if (self.is_at_end()) '\n' else ';';

        var response = try self.connection.recvNext(delim);
        const id = try response.next(u32, ',');
        const mod = try response.next(u32, delim);
        try response.expectEnd();

        return Block{ .id = id, .mod = mod };
    }

    fn is_at_end(self: *const BlockStream) bool {
        return self.index >= (self.size.x * self.size.y * self.size.z);
    }
};

/// A stream of heights in a rectangle, returned by `Connection.getHeights`.
///
/// **Mutating or relocating the parent `Connection` invalidates an instance of
/// this type.**
pub const HeightStream = struct {
    connection: *Connection,
    origin: Coordinate2D,
    size: Size2D,
    index: usize,

    pub fn next(self: *HeightStream) ResponseError!?i32 {
        if (self.is_at_end()) {
            return null;
        }
        self.index += 1;

        const delim: u8 = if (self.is_at_end()) '\n' else ',';

        var response = try self.connection.recvNext(delim);
        const height = try response.next(i32, delim);
        try response.expectEnd();

        return height;
    }

    fn is_at_end(self: *const HeightStream) bool {
        return self.index >= (self.size.x * self.size.z);
    }
};
