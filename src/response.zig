const std = @import("std");
const assert = std.debug.assert;
const math = std.math;

pub const IntegerIter = struct {
    const Self = @This();

    buffer: []const u8,
    index: usize,

    /// Requires that slice is properly terminated with appropriate delimiter.
    pub fn new(slice: []const u8) Self {
        return Self{
            .buffer = slice,
            .index = 0,
        };
    }

    const Error = error{
        Fail,
        UnexpectedEof,
        UnexpectedChar,
        MalformedValue,
        Overflow,
    };

    /// Does not consume / increase index.
    fn nextByte(self: *const Self) Error!u8 {
        if (self.index >= self.buffer.len) {
            return Error.UnexpectedEof;
        }
        return self.buffer[self.index];
    }

    /// Asserts not at EOF.
    fn advanceByte(self: *Self) void {
        _ = self.nextByte() catch unreachable;
        self.index += 1;
    }

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
                self.buffer[self.index..][0..4],
                "Fail",
            )) {
                return Error.Fail;
            }

            // Empty, not including sign character
            return Error.MalformedValue;
        }

        var value = try math.mul(Intermediate(Int), result.value, sign);

        // Decimal point and following digits
        if (try self.nextByte() == '.') {
            self.advanceByte();
            const is_integer = try self.take_digits_post_decimal();
            // Ensure number is always rounded down, NOT truncated
            // Without this, `-1.3` would become `-1` (instead of `-2`)
            if (!is_integer and sign < 0) {
                value = try math.sub(Intermediate(Int), value, 1);
            }
        }

        const delim = try self.nextByte();
        self.advanceByte();
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
            const char = try self.nextByte();

            const digit: Int = switch (char) {
                '0'...'9' => @intCast(char - '0'),
                else => break,
            };

            self.advanceByte();

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
            switch (try self.nextByte()) {
                '0' => {},
                '1'...'9' => is_integer = false,
                else => break,
            }
            self.advanceByte();
        }
        return is_integer;
    }

    fn take_sign_char(self: *Self) Error!enum { negative, positive, none } {
        switch (try self.nextByte()) {
            '-' => {
                self.advanceByte();
                return .negative;
            },
            '+' => {
                self.advanceByte();
                return .positive;
            },
            else => {
                return .none;
            },
        }
    }
};
