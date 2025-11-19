const std = @import("std");
const debug = std.debug;
const math = std.math;
const net = std.net;
const Thread = std.Thread;

pub fn main() !void {
    const conn = try Connection.new();
    try conn.getPlayerPosition();
}

const Connection = struct {
    stream: net.Stream,

    const Self = @This();

    pub fn new() !Self {
        const ip = "127.0.0.1";
        const port = 4711;
        const addr = try net.Address.parseIp(ip, port);

        const conn = try net.tcpConnectToAddress(addr);

        return Self{ .stream = conn };
    }

    fn getPlayerPosition(self: *const Self) !void {
        const WRITE_BUFFER_SIZE = "player.getPos()\n".len;
        const READ_BUFFER_SIZE = "12345.123456890,12345.123456890,12345.123456890\n".len * 2;

        var write_buffer: [WRITE_BUFFER_SIZE]u8 = undefined;
        var read_buffer: [READ_BUFFER_SIZE]u8 = undefined;

        var writer = self.stream.writer(&write_buffer);
        try writer.interface.writeAll("player.getPos()\n");
        try writer.interface.flush();

        var reader = self.stream.reader(&read_buffer);
        const data = try reader.interface().takeDelimiterInclusive('\n');

        debug.print("{s}\n", .{data});

        var integers = IntegerIter.new(data);

        const x = try integers.next(i32, ',');
        const y = try integers.next(i32, ',');
        const z = try integers.next(i32, '\n');
        debug.print("{}, {}, {}\n", .{ x, y, z });
    }
};

const IntegerIter = struct {
    const Self = @This();

    // TODO: Rename ?
    inner: ByteIter,

    pub fn new(slice: []const u8) Self {
        return Self{ .inner = ByteIter.new(slice) };
    }

    const Error = error{
        UnexpectedEof,
        UnexpectedChar,
        IncorrectTerminator,
        EmptyInteger,
        Overflow,
    };

    pub fn next(
        self: *Self,
        comptime Int: type,
        expected_terminator: u8,
    ) Error!Int {

        // TODO: Static assert `Int` is sensible

        debug.print("NEXT\n", .{});

        const sign: Int = switch (try self.take_sign_char()) {
            .negative => -1,
            .positive, .none => 1,
        };

        const result = try self.take_digits_pre_decimal(Int);
        if (result.length == 0) {
            return Error.EmptyInteger; // Not including sign character
        }

        var value = try math.mul(Int, result.value, sign);

        // Decimal point and following digits
        if (try self.inner.peek() == '.') {
            self.inner.discardNext();
            const is_integer = try self.take_digits_post_decimal();
            // Ensure number is always rounded down, NOT truncated
            // Without this, `-1.3` would become `-1` (instead of `-2`)
            if (!is_integer and sign < 0) {
                value = try math.sub(Int, value, 1);
            }
        }

        const terminator = try self.inner.next();
        if (terminator != expected_terminator) {
            return Error.IncorrectTerminator;
        }

        return value;
    }

    /// Parses base-10 integer.
    /// Stops before first non-digit character, including decimal point.
    fn take_digits_pre_decimal(self: *Self, comptime Int: type) Error!struct {
        value: Int,
        length: usize,
    } {
        var value: Int = 0;
        var length: usize = 0;

        while (true) : (length += 1) {
            const char = try self.inner.peek();

            const digit: Int = switch (char) {
                '0'...'9' => @intCast(char - '0'),
                else => break,
            };

            self.inner.discardNext();

            value = try math.mul(Int, value, 10);
            value = try math.add(Int, value, digit);
        }

        return .{ .value = value, .length = length };
    }

    /// Returns `true` if any digits are non-zero, i.e. value is not an integer.
    /// Stops before first non-digit character.
    fn take_digits_post_decimal(self: *Self) Error!bool {
        var is_integer = true;
        while (true) {
            switch (try self.inner.peek()) {
                '0' => {},
                '1'...'9' => is_integer = false,
                else => break,
            }
            self.inner.discardNext();
        }
        return is_integer;
    }

    fn take_sign_char(self: *Self) Error!enum { negative, positive, none } {
        switch (try self.inner.peek()) {
            '-' => {
                self.inner.discardNext();
                return .negative;
            },
            '+' => {
                self.inner.discardNext();
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
        debug.print(": {c}\n", .{item});
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

fn requireIteratorOf(comptime T: type, comptime Item: type) void {
    if (getIteratorItem(T) != Item) {
        @compileError("iterator item type does not match");
    }
}

fn getIteratorItem(comptime T: type) type {
    if (@typeInfo(T) != .@"struct") {
        @compileError("iterator type is not a struct");
    }
    if (!@hasDecl(T, "next")) {
        @compileError("iterator type does not contain `next` declaration");
    }
    const next = switch (@typeInfo(@TypeOf(T.next))) {
        .@"fn" => |next| next,
        else => @compileError("iterator `next` is not a function"),
    };
    const optional = switch (@typeInfo(next.return_type orelse void)) {
        .optional => |optional| optional,
        else => @compileError("iterator `next` function does not return an optional"),
    };
    return optional.child;
}
