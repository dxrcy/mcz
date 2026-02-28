const Connection = @This();

const std = @import("std");
const Io = std.Io;
const net = Io.net;

const lib = @import("lib.zig");
const Coordinate = lib.Coordinate;
const Coordinate2D = lib.Coordinate2D;
const Size = lib.Size;
const Size2D = lib.Size2D;
const Block = lib.Block;

const Response = @import("Response.zig");

/// Default address and port for [ELCI](https://github.com/rozukke/elci) server.
pub const DEFAULT_ADDRESS = net.IpAddress.parseIp4("127.0.0.1", 4711) catch unreachable;

const WRITE_BUFFER_SIZE = 1024;
const READ_BUFFER_SIZE = 1024;

stream: net.Stream,
writer: net.Stream.Writer,
reader: net.Stream.Reader,
write_buffer: [WRITE_BUFFER_SIZE]u8,
read_buffer: [READ_BUFFER_SIZE]u8,
io: Io,

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
pub fn new(io: Io) net.IpAddress.ConnectError!Connection {
    return Connection.withAddress(DEFAULT_ADDRESS, io);
}

/// Create a new connection with a specified server address.
///
/// **Must call `init` after creation or relocation.**
pub fn withAddress(addr: net.IpAddress, io: Io) net.IpAddress.ConnectError!Connection {
    const stream = try addr.connect(io, .{ .mode = .stream });
    return Connection{
        .stream = stream,
        .writer = undefined,
        .reader = undefined,
        .write_buffer = undefined,
        .read_buffer = undefined,
        .io = io,
    };
}

/// Initialize writer and reader with correct internal references.
pub fn init(connection: *Connection) void {
    connection.writer = connection.stream.writer(connection.io, &connection.write_buffer);
    connection.reader = connection.stream.reader(connection.io, &connection.read_buffer);
}

fn recvNext(connection: *Connection, delimiter: u8) ResponseError!Response {
    const data = try connection.reader.interface.takeDelimiterInclusive(delimiter);
    return Response.new(data);
}

fn writeSanitizedString(connection: *Connection, string: []const u8) RequestError!void {
    // Server parses based on newlines (0x0a). All other characters,
    // including comma, semicolon, and arbitrary UTF-8 should be safe.
    for (string) |char| {
        try connection.writer.interface.print("{c}", .{
            if (char == '\n') ' ' else char,
        });
    }
}

/// Sends a message to the in-game chat.
///
/// Does **not** require that a player has joined.
pub fn postToChat(
    connection: *Connection,
    message: []const u8,
) RequestError!void {
    try connection.writer.interface.print("chat.post(", .{});
    try connection.writeSanitizedString(message);
    try connection.writer.interface.print(")\n", .{});
    try connection.writer.interface.flush();
}

/// Performs an in-game Minecraft command.
///
/// Players have to exist on the server and should be server operators (default
/// with [ELCI](https://github.com/rozukke/elci)).
pub fn doCommand(
    connection: *Connection,
    command: []const u8,
) RequestError!void {
    try connection.writer.interface.print("player.doCommand(", .{});
    try connection.writeSanitizedString(command);
    try connection.writer.interface.print(")\n", .{});
    try connection.writer.interface.flush();
}

/// Returns a `Coordinate` representing player position (block position of lower
/// half of playermodel).
pub fn getPlayerPosition(
    connection: *Connection,
) MessageError!Coordinate {
    try connection.writer.interface.print(
        "player.getPos()\n",
        .{},
    );
    try connection.writer.interface.flush();

    var response = try connection.recvNext('\n');
    const x = try response.next(i32, ',');
    const y = try response.next(i32, ',');
    const z = try response.next(i32, '\n');
    try response.expectEnd();

    return Coordinate{ .x = x, .y = y, .z = z };
}

/// Sets player position (block position of lower half of playermodel) to
/// specified `Coordinate`.
pub fn setPlayerPosition(
    connection: *Connection,
    coordinate: Coordinate,
) RequestError!void {
    try connection.writer.interface.print(
        "player.setPos({},{},{})\n",
        .{ coordinate.x, coordinate.y, coordinate.z },
    );
    try connection.writer.interface.flush();
}

/// Returns `Block` object from specified `Coordinate`.
///
/// **Do not use for large areas, it will be very slow**.
/// Use `getBlocks` instead.
pub fn getBlock(
    connection: *Connection,
    coordinate: Coordinate,
) MessageError!Block {
    try connection.writer.interface.print(
        "world.getBlockWithData({},{},{})\n",
        .{ coordinate.x, coordinate.y, coordinate.z },
    );
    try connection.writer.interface.flush();

    var response = try connection.recvNext('\n');
    const id = try response.next(u32, ',');
    const mod = try response.next(u32, '\n');
    try response.expectEnd();

    return Block{ .id = id, .mod = mod };
}

/// Sets block at `Coordinate` to specified `Block`.
pub fn setBlock(
    connection: *Connection,
    coordinate: Coordinate,
    block: Block,
) RequestError!void {
    try connection.writer.interface.print(
        "world.setBlock({},{},{},{},{})\n",
        .{
            coordinate.x, coordinate.y, coordinate.z,
            block.id,     block.mod,
        },
    );
    try connection.writer.interface.flush();
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
    connection: *Connection,
    origin: Coordinate,
    bound: Coordinate,
) MessageError!BlockStream {
    try connection.writer.interface.print(
        "world.getBlocksWithData({},{},{},{},{},{})\n",
        .{
            origin.x, origin.y, origin.z,
            bound.x,  bound.y,  bound.z,
        },
    );
    try connection.writer.interface.flush();

    return BlockStream{
        .connection = connection,
        .origin = origin,
        .size = Size.between(origin, bound),
        .index = 0,
    };
}

/// Sets a cuboid of blocks to all be the specified `Block`, with the corners of
/// the cuboid specified by `Coordinate`s `origin` and `bound` (in any order).
pub fn setBlocks(
    connection: *Connection,
    origin: Coordinate,
    bound: Coordinate,
    block: Block,
) RequestError!void {
    try connection.writer.interface.print(
        "world.setBlocks({},{},{},{},{},{},{},{})\n",
        .{
            origin.x, origin.y,  origin.z,
            bound.x,  bound.y,   bound.z,
            block.id, block.mod,
        },
    );
    try connection.writer.interface.flush();
}

/// Returns the `y`-value of the highest solid block at the specified `x` and
/// `z` coordinate
///
/// **Do not use for large areas, it will be very slow**.
/// Use `getHeights` instead.
pub fn getHeight(
    connection: *Connection,
    coordinate: Coordinate2D,
) MessageError!i32 {
    try connection.writer.interface.print(
        "world.getHeight({},{})\n",
        .{ coordinate.x, coordinate.z },
    );
    try connection.writer.interface.flush();

    var response = try connection.recvNext('\n');
    const height = try response.next(i32, '\n');
    try response.expectEnd();

    return height;
}

/// Returns a collection of the heights in rectangle specified by
/// `Coordinate2D`s `origin` and `bound` (in any order).
///
/// Streams response to avoid allocation.
///
/// Note this means all blocks have to be read before other responses can be
/// read from the server; i.e. any subsequently-called method which reads a
/// server response (eg. `getBlock`) will block until *this* response is
/// completely read (when `BlockStream.next()` yeilds `null`).
pub fn getHeights(
    connection: *Connection,
    origin: Coordinate2D,
    bound: Coordinate2D,
) RequestError!HeightStream {
    try connection.writer.interface.print(
        "world.getHeights({},{},{},{})\n",
        .{
            origin.x, origin.z,
            bound.x,  bound.z,
        },
    );
    try connection.writer.interface.flush();

    return HeightStream{
        .connection = connection,
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

    pub fn next(stream: *BlockStream) ResponseError!?Block {
        if (stream.isAtEnd()) {
            return null;
        }
        stream.index += 1;

        const delim: u8 = if (stream.isAtEnd()) '\n' else ';';

        var response = try stream.connection.recvNext(delim);
        const id = try response.next(u32, ',');
        const mod = try response.next(u32, delim);
        try response.expectEnd();

        return Block{ .id = id, .mod = mod };
    }

    fn isAtEnd(stream: *const BlockStream) bool {
        return stream.index >= (stream.size.x * stream.size.y * stream.size.z);
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

    pub fn next(stream: *HeightStream) ResponseError!?i32 {
        if (stream.isAtEnd()) {
            return null;
        }
        stream.index += 1;

        const delim: u8 = if (stream.isAtEnd()) '\n' else ',';

        var response = try stream.connection.recvNext(delim);
        const height = try response.next(i32, delim);
        try response.expectEnd();

        return height;
    }

    fn isAtEnd(stream: *const HeightStream) bool {
        return stream.index >= (stream.size.x * stream.size.z);
    }
};
