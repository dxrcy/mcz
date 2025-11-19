const std = @import("std");
const debug = std.debug;
const math = std.math;
const net = std.net;
const assert = std.debug.assert;

pub fn main() !void {
    var conn = try Connection.new();
    conn.init();

    try conn.setPlayerPosition(.{ .x = 4, .y = 27, .z = 8 });

    const player = try conn.getPlayerPosition();
    debug.print("{}, {}, {}\n", player);

    const tile = Coordinate{
        .x = player.x,
        .y = player.y - 1,
        .z = player.z,
    };

    try conn.setBlock(tile, .{ .id = 1, .mod = 0 });

    const block = try conn.getBlock(tile);
    debug.print("{}:{}\n", block);

    var blocks = try conn.getBlocks(
        .{ .x = 0, .y = 30, .z = 0 },
        .{ .x = 1, .y = 31, .z = -1 },
    );
    while (try blocks.next()) |b| {
        debug.print("  - {}:{}\n", b);
    }
}

const Coordinate = struct {
    x: i32,
    y: i32,
    z: i32,
};

const Block = struct {
    // Fields must be larger than `u8` to hold newer blocks
    id: u32,
    mod: u32,
};

const Connection = struct {
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

    fn getPlayerPosition(self: *Self) !Coordinate {
        try self.writer.interface.writeAll("player.getPos()\n");
        try self.writer.interface.flush();

        const data = try self.reader.interface().takeDelimiterInclusive('\n');
        var integers = IntegerIter.new(data);

        const x = try integers.next(i32, ',');
        const y = try integers.next(i32, ',');
        const z = try integers.next(i32, '\n');
        return Coordinate{ .x = x, .y = y, .z = z };
    }

    fn setPlayerPosition(self: *Self, coordinate: Coordinate) !void {
        try self.writer.interface.print(
            "player.setPos({},{},{})\n",
            .{ coordinate.x, coordinate.y, coordinate.z },
        );
        try self.writer.interface.flush();
    }

    fn getBlock(self: *Self, coordinate: Coordinate) !Block {
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

    fn setBlock(self: *Self, coordinate: Coordinate, block: Block) !void {
        try self.writer.interface.print(
            "world.setBlock({},{},{},{},{})\n",
            .{ coordinate.x, coordinate.y, coordinate.z, block.id, block.mod },
        );
        try self.writer.interface.flush();
    }

    fn getBlocks(
        self: *Self,
        corner_a: Coordinate,
        corner_b: Coordinate,
    ) !BlockStream {
        try self.writer.interface.print(
            "world.getBlocksWithData({},{},{},{},{},{})\n",
            .{
                corner_a.x, corner_a.y, corner_a.z,
                corner_b.x, corner_b.y, corner_b.z,
            },
        );
        try self.writer.interface.flush();

        const length = (@abs(corner_a.x - corner_b.x) + 1) *
            (@abs(corner_a.y - corner_b.y) + 1) *
            (@abs(corner_a.z - corner_b.z) + 1);

        return BlockStream{
            .connection = self,
            .origin = corner_a,
            .length = @intCast(length),
            .index = 0,
        };
    }

    const BlockStream = struct {
        connection: *Connection,
        origin: Coordinate,
        // TODO: Create `Size` struct
        length: usize,
        index: usize,

        pub fn next(self: *BlockStream) !?Block {
            if (self.index >= self.length) {
                return null;
            }
            self.index += 1;

            const is_last = self.index >= self.length;
            const delim: u8 = if (is_last) '\n' else ';';

            const data = try self.connection.reader.interface().takeDelimiterInclusive(delim);

            var integers = IntegerIter.new(data);

            const id = try integers.next(u32, ',');
            const mod = try integers.next(u32, delim);

            return Block{ .id = id, .mod = mod };
        }
    };
};

const IntegerIter = struct {
    const Self = @This();

    bytes: ByteIter,

    pub fn new(slice: []const u8) Self {
        return Self{ .bytes = ByteIter.new(slice) };
    }

    const Error = error{
        Fail,
        UnexpectedEof,
        UnexpectedChar,
        MalformedValue,
        Overflow,
    };

    pub fn next(
        self: *Self,
        comptime Int: type,
        expected_delim: u8,
    ) Error!Int {
        if (@typeInfo(Int) != .int) {
            @compileError("parameter must be an integer");
        }

        const sign: Intermediate(Int) = switch (try self.take_sign_char()) {
            .negative => -1,
            .positive, .none => 1,
        };

        const result = try self.take_digits_pre_decimal(Int);

        if (result.length == 0) {
            // TODO: Move elsewhere?
            if (std.mem.eql(
                u8,
                self.bytes.buffer[self.bytes.index..][0..4],
                "Fail",
            )) {
                return Error.Fail;
            }

            // Empty, not including sign character
            return Error.MalformedValue;
        }

        var value = try math.mul(Intermediate(Int), result.value, sign);

        // Decimal point and following digits
        if (try self.bytes.peek() == '.') {
            self.bytes.discardNext();
            const is_integer = try self.take_digits_post_decimal();
            // Ensure number is always rounded down, NOT truncated
            // Without this, `-1.3` would become `-1` (instead of `-2`)
            if (!is_integer and sign < 0) {
                value = try math.sub(Intermediate(Int), value, 1);
            }
        }

        const delim = try self.bytes.next();
        if (delim != expected_delim) {
            return Error.UnexpectedChar;
        }

        return math.cast(Int, value) orelse Error.Overflow;
    }

    /// If `Int` is unsigned, return a larger signed integer with a sign bit.
    fn Intermediate(comptime Int: type) type {
        const info = @typeInfo(Int).int;
        if (info.signedness == .signed) {
            return Int;
        }
        return @Type(std.builtin.Type{ .int = .{
            .bits = info.bits + 1,
            .signedness = .signed,
        } });
    }

    /// Parses base-10 integer.
    /// Stops before first non-digit character, including decimal point.
    fn take_digits_pre_decimal(self: *Self, comptime Int: type) Error!struct {
        value: Intermediate(Int),
        length: usize,
    } {
        var value: Intermediate(Int) = 0;
        var length: usize = 0;

        while (true) : (length += 1) {
            const char = try self.bytes.peek();

            const digit: Int = switch (char) {
                '0'...'9' => @intCast(char - '0'),
                else => break,
            };

            self.bytes.discardNext();

            value = try math.mul(Intermediate(Int), value, 10);
            value = try math.add(Intermediate(Int), value, digit);
        }

        return .{ .value = value, .length = length };
    }

    /// Returns `true` if any digits are non-zero, i.e. value is not an integer.
    /// Stops before first non-digit character.
    fn take_digits_post_decimal(self: *Self) Error!bool {
        var is_integer = true;
        while (true) {
            switch (try self.bytes.peek()) {
                '0' => {},
                '1'...'9' => is_integer = false,
                else => break,
            }
            self.bytes.discardNext();
        }
        return is_integer;
    }

    fn take_sign_char(self: *Self) Error!enum { negative, positive, none } {
        switch (try self.bytes.peek()) {
            '-' => {
                self.bytes.discardNext();
                return .negative;
            },
            '+' => {
                self.bytes.discardNext();
                return .positive;
            },
            else => {
                return .none;
            },
        }
    }
};

const ByteIter = struct {
    const Self = @This();

    buffer: []const u8,
    index: usize,

    // Responses must be properly terminated with '\n'.
    const Error = error{UnexpectedEof};

    pub fn new(slice: []const u8) Self {
        return .{
            .buffer = slice,
            .index = 0,
        };
    }

    pub fn next(self: *Self) Error!u8 {
        if (self.index >= self.buffer.len) {
            return Error.UnexpectedEof;
        }
        const item = self.buffer[self.index];
        self.index += 1;
        return item;
    }

    pub fn peek(self: *const Self) Error!u8 {
        if (self.index >= self.buffer.len) {
            return Error.UnexpectedEof;
        }
        return self.buffer[self.index];
    }

    /// Asserts not at EOF.
    pub fn discardNext(self: *Self) void {
        _ = self.next() catch unreachable;
    }
};
