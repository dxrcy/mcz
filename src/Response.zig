const Response = @This();

const std = @import("std");
const assert = std.debug.assert;
const math = std.math;

buffer: []const u8,
index: usize,

pub const Error = error{
    Fail,
    UnexpectedEof,
    UnexpectedChar,
    MalformedValue,
    Overflow,
};

/// Requires that slice is properly terminated with appropriate delimiter.
pub fn new(slice: []const u8) Response {
    return .{ .buffer = slice, .index = 0 };
}

/// Does not consume / increase index.
fn nextByte(response: *const Response) Error!u8 {
    if (response.index >= response.buffer.len)
        return Error.UnexpectedEof;
    return response.buffer[response.index];
}

/// Asserts not at EOF.
fn advanceByte(response: *Response) void {
    _ = response.nextByte() catch
        unreachable;
    response.index += 1;
}

pub fn expectEnd(response: *Response) Error!void {
    if (response.index < response.buffer.len)
        return Error.UnexpectedChar;
}

pub fn next(
    response: *Response,
    comptime Int: type,
    expected_delim: u8,
) Error!Int {
    if (@typeInfo(Int) != .int)
        @compileError("parameter must be an integer");

    const sign: Intermediate(Int) = switch (try response.takeSignChar()) {
        .negative => -1,
        .positive, .none => 1,
    };

    const result = try response.takeDigitsPreDecimal(Int);

    if (result.length == 0) {
        // TODO: Move elsewhere?
        if (std.mem.eql(
            u8,
            response.buffer[response.index..][0..4],
            "Fail",
        )) {
            return Error.Fail;
        }

        // Empty, not including sign character
        return Error.MalformedValue;
    }

    var value = try math.mul(Intermediate(Int), result.value, sign);

    // Decimal point and following digits
    if (try response.nextByte() == '.') {
        response.advanceByte();
        const is_integer = try response.takeDigitsPostDecimal();
        // Ensure number is always rounded down, NOT truncated
        // Without this, `-1.3` would become `-1` (instead of `-2`)
        if (!is_integer and sign < 0)
            value = try math.sub(Intermediate(Int), value, 1);
    }

    const delim = try response.nextByte();
    response.advanceByte();
    if (delim != expected_delim)
        return Error.UnexpectedChar;

    return math.cast(Int, value) orelse Error.Overflow;
}

fn Intermediate(comptime Int: type) type {
    const info = @typeInfo(Int).int;
    return if (info.signedness == .signed)
        Int
    else
        @Int(.signed, info.bits + 1);
}

/// Parses base-10 integer.
/// Stops before first non-digit character, including decimal point.
fn takeDigitsPreDecimal(response: *Response, comptime Int: type) Error!struct {
    value: Intermediate(Int),
    length: usize,
} {
    var value: Intermediate(Int) = 0;
    var length: usize = 0;

    while (true) : (length += 1) {
        const char = try response.nextByte();

        const digit: Int = switch (char) {
            '0'...'9' => @intCast(char - '0'),
            else => break,
        };

        response.advanceByte();

        value = try math.mul(Intermediate(Int), value, 10);
        value = try math.add(Intermediate(Int), value, digit);
    }

    return .{ .value = value, .length = length };
}

/// Returns `true` if any digits are non-zero, i.e. value is not an integer.
/// Stops before first non-digit character.
fn takeDigitsPostDecimal(response: *Response) Error!bool {
    var is_integer = true;
    while (true) {
        switch (try response.nextByte()) {
            '0' => {},
            '1'...'9' => is_integer = false,
            else => break,
        }
        response.advanceByte();
    }
    return is_integer;
}

fn takeSignChar(response: *Response) Error!enum { negative, positive, none } {
    switch (try response.nextByte()) {
        '-' => {
            response.advanceByte();
            return .negative;
        },
        '+' => {
            response.advanceByte();
            return .positive;
        },
        else => {
            return .none;
        },
    }
}
