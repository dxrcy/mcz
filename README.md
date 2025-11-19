# MCZ (Minecraft-Zig)

A Zig rewrite of [mcpp](https://github.com/rozukke/mcpp), a library to
interface with Minecraft.

Requires a server running [ELCI](https://github.com/rozukke/elci).

> See also [MCRS](https://github.com/dxrcy/mcrs)

```zig
pub fn main() !void {
    var conn = try mcz.Connection.new();
    conn.init();
    try conn.postToChat("Hello!");
}
```


