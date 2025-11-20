const Self = @This();

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

const WRITE_BUFFER_SIZE = 1024;
const READ_BUFFER_SIZE = 1024;

stream: net.Stream,
writer: net.Stream.Writer,
reader: net.Stream.Reader,
write_buffer: [WRITE_BUFFER_SIZE]u8,
read_buffer: [READ_BUFFER_SIZE]u8,

pub const NewError =
    net.TcpConnectToAddressError ||
    error{InvalidIPAddressFormat};

// TODO: Split into request/response
pub const RequestError =
    Io.Writer.Error ||
    Io.Reader.Error ||
    Response.Error ||
    error{StreamTooLong};

/// Must call `init` after creation, to initialize writer/reader with
/// correct internal references.
pub fn new() NewError!Self {
    const ip = "127.0.0.1";
    const port = 4711;

    const addr = try net.Address.parseIp(ip, port);
    const conn = try net.tcpConnectToAddress(addr);

    return Self{
        .stream = conn,
        .writer = undefined,
        .reader = undefined,
        .write_buffer = undefined,
        .read_buffer = undefined,
    };
}

pub fn init(self: *Self) void {
    self.writer = self.stream.writer(&self.write_buffer);
    self.reader = self.stream.reader(&self.read_buffer);
}

fn recvNext(self: *Self, delimiter: u8) RequestError!Response {
    const data = try self.reader.interface().takeDelimiterInclusive(delimiter);
    return Response.new(data);
}

pub fn postToChat(self: *Self, message: []const u8) RequestError!void {
    try self.writer.interface.print("chat.post(", .{});
    try self.writeSanitizedString(message);
    try self.writer.interface.print(")\n", .{});
    try self.writer.interface.flush();
}

pub fn doCommand(self: *Self, command: []const u8) RequestError!void {
    try self.writer.interface.print("player.doCommand(", .{});
    try self.writeSanitizedString(command);
    try self.writer.interface.print(")\n", .{});
    try self.writer.interface.flush();
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

pub fn getPlayerPosition(self: *Self) RequestError!Coordinate {
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

pub fn getBlock(self: *Self, coordinate: Coordinate) RequestError!Block {
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

pub fn getBlocks(
    self: *Self,
    origin: Coordinate,
    bound: Coordinate,
) RequestError!BlockStream {
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

pub fn getHeight(self: *Self, coordinate: Coordinate2D) RequestError!i32 {
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

pub const BlockStream = struct {
    const Connection = Self;

    connection: *Connection,
    origin: Coordinate,
    size: Size,
    index: usize,

    pub fn next(self: *BlockStream) RequestError!?Block {
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

pub const HeightStream = struct {
    const Connection = Self;

    connection: *Connection,
    origin: Coordinate2D,
    size: Size2D,
    index: usize,

    pub fn next(self: *HeightStream) RequestError!?i32 {
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
