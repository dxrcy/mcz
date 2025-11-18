const std = @import("std");
const debug = std.debug;
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
        const data = try reader.interface().takeDelimiterExclusive('\n');

        debug.print("{s}\n", .{data});

        var integers = IntegerIter(PeekCopyIter(ByteIter))
            .new(PeekCopyIter(ByteIter)
            .new(ByteIter.new(&read_buffer)));

        const x = integers.next_inner();
        debug.print("{}\n", .{x});
    }
};

fn IntegerIter(comptime T: type) type {
    assertIteratorOf(T, u8);
    return struct {
        const Self = @This();

        inner: T,

        pub fn new(inner: T) Self {
            return Self{ .inner = inner };
        }

        fn next_inner(self: *Self) i32 {
            var integer: i32 = 0;

            while (true) {
                const char = self.inner.next() orelse {
                    break;
                };
                debug.print(": {c}\n", .{char});

                if (char == '.') {
                    break;
                }

                if (!std.ascii.isDigit(char)) {
                    break;
                }

                const digit = char - '0';
                integer *= 10;
                integer += digit;
            }

            return integer;
        }
    };
}

fn PeekCopyIter(comptime T: type) type {
    const Item = getIteratorItem(T);
    return struct {
        const Self = @This();

        inner: T,
        peeked: ?Item,

        pub fn new(inner: T) Self {
            return Self{ .inner = inner, .peeked = null };
        }

        pub fn next(self: *Self) ?Item {
            if (self.peeked) |peeked| {
                self.peeked = null;
                return peeked;
            }
            return self.inner.next();
        }

        pub fn peek(self: *Self) ?Item {
            if (self.peeked) |peeked| {
                return peeked;
            }
            self.peeked = self.next();
            return self.peeked;
        }
    };
}

const ByteIter = struct {
    const Self = @This();

    buffer: []const u8,
    index: usize,

    pub fn new(slice: []const u8) Self {
        return .{
            .buffer = slice,
            .index = 0,
        };
    }

    pub fn next(self: *Self) ?u8 {
        if (self.index >= self.buffer.len) {
            return null;
        }
        const item = self.buffer[self.index];
        self.index += 1;
        return item;
    }
};

fn assertIteratorOf(comptime T: type, comptime Item: type) void {
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
