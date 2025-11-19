const std = @import("std");
const net = std.net;

const lib = @import("lib.zig");
const Coordinate = lib.Coordinate;
const Size = lib.Size;
const Block = lib.Block;

const IntegerIter = @import("response.zig").IntegerIter;

pub const Connection = struct {
    const Self = @This();

    const WRITE_BUFFER_SIZE = 1024;
    const READ_BUFFER_SIZE = 1024;

    stream: net.Stream,
    writer: net.Stream.Writer,
    reader: net.Stream.Reader,
    write_buffer: [WRITE_BUFFER_SIZE]u8,
    read_buffer: [READ_BUFFER_SIZE]u8,

    // TODO: Add explicit error variants to function returns

    /// Must call `init` after creation, to initialize writer/reader with
    /// correct internal references.
    pub fn new() !Self {
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

    pub fn postToChat(self: *Self, message: []const u8) !void {
        // FIXME: Sanitize message
        try self.writer.interface.print("chat.post({s})\n", .{message});
        try self.writer.interface.flush();
    }

    pub fn getPlayerPosition(self: *Self) !Coordinate {
        try self.writer.interface.print("player.getPos()\n", .{});
        try self.writer.interface.flush();

        const data = try self.reader.interface().takeDelimiterInclusive('\n');
        var integers = IntegerIter.new(data);

        const x = try integers.next(i32, ',');
        const y = try integers.next(i32, ',');
        const z = try integers.next(i32, '\n');
        return Coordinate{ .x = x, .y = y, .z = z };
    }

    pub fn setPlayerPosition(self: *Self, coordinate: Coordinate) !void {
        try self.writer.interface.print(
            "player.setPos({},{},{})\n",
            .{ coordinate.x, coordinate.y, coordinate.z },
        );
        try self.writer.interface.flush();
    }

    pub fn getBlock(self: *Self, coordinate: Coordinate) !Block {
        try self.writer.interface.print(
            "world.getBlockWithData({},{},{})\n",
            .{ coordinate.x, coordinate.y, coordinate.z },
        );
        try self.writer.interface.flush();

        const data = try self.reader.interface().takeDelimiterInclusive('\n');
        var integers = IntegerIter.new(data);

        const id = try integers.next(u32, ',');
        const mod = try integers.next(u32, '\n');
        return Block{ .id = id, .mod = mod };
    }

    pub fn setBlock(self: *Self, coordinate: Coordinate, block: Block) !void {
        try self.writer.interface.print(
            "world.setBlock({},{},{},{},{})\n",
            .{ coordinate.x, coordinate.y, coordinate.z, block.id, block.mod },
        );
        try self.writer.interface.flush();
    }

    pub fn getBlocks(
        self: *Self,
        origin: Coordinate,
        bound: Coordinate,
    ) !BlockStream {
        try self.writer.interface.print(
            "world.getBlocksWithData({},{},{},{},{},{})\n",
            .{
                origin.x, origin.y, origin.z,
                bound.x,  bound.y,  bound.z,
            },
        );
        try self.writer.interface.flush();

        const size = Size{
            .x = (@abs(origin.x - bound.x) + 1),
            .y = (@abs(origin.y - bound.y) + 1),
            .z = (@abs(origin.z - bound.z) + 1),
        };

        return BlockStream{
            .connection = self,
            .origin = origin,
            .size = size,
            .index = 0,
        };
    }

    pub fn setBlocks(
        self: *Self,
        origin: Coordinate,
        bound: Coordinate,
        block: Block,
    ) !void {
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

    // TODO: Create `Coordinate2D` struct
    pub fn getHeight(self: *Self, coordinate: Coordinate) !i32 {
        try self.writer.interface.print(
            "world.getHeight({},{})\n",
            .{ coordinate.x, coordinate.z },
        );
        try self.writer.interface.flush();

        const data = try self.reader.interface().takeDelimiterInclusive('\n');
        var integers = IntegerIter.new(data);

        const height = try integers.next(i32, '\n');
        return height;
    }

    pub fn getHeights(
        self: *Self,
        origin: Coordinate,
        bound: Coordinate,
    ) !HeightStream {
        try self.writer.interface.print(
            "world.getHeights({},{},{},{})\n",
            .{
                origin.x, origin.z,
                bound.x,  bound.z,
            },
        );
        try self.writer.interface.flush();

        // TODO: Create `Size2D` struct
        const size = Size{
            .x = (@abs(origin.x - bound.x) + 1),
            .y = 1,
            .z = (@abs(origin.z - bound.z) + 1),
        };

        return HeightStream{
            .connection = self,
            .origin = origin,
            .size = size,
            .index = 0,
        };
    }
};

pub const BlockStream = struct {
    const Self = @This();

    connection: *Connection,
    origin: Coordinate,
    size: Size,
    index: usize,

    pub fn next(self: *Self) !?Block {
        if (self.is_at_end()) {
            return null;
        }
        self.index += 1;

        const delim: u8 = if (self.is_at_end()) '\n' else ';';

        const data = try self.connection.reader.interface().takeDelimiterInclusive(delim);
        var integers = IntegerIter.new(data);

        const id = try integers.next(u32, ',');
        const mod = try integers.next(u32, delim);

        return Block{ .id = id, .mod = mod };
    }

    fn is_at_end(self: *const Self) bool {
        const length = self.size.x * self.size.y * self.size.z;
        return self.index >= length;
    }
};

pub const HeightStream = struct {
    const Self = @This();

    connection: *Connection,
    origin: Coordinate,
    size: Size,
    index: usize,

    pub fn next(self: *Self) !?i32 {
        if (self.is_at_end()) {
            return null;
        }
        self.index += 1;

        const delim: u8 = if (self.is_at_end()) '\n' else ',';

        const data = try self.connection.reader.interface().takeDelimiterInclusive(delim);
        var integers = IntegerIter.new(data);

        const height = try integers.next(i32, delim);
        return height;
    }

    fn is_at_end(self: *const Self) bool {
        const length = self.size.x * self.size.y * self.size.z;
        return self.index >= length;
    }
};
