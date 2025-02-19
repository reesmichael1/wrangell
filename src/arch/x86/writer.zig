const fmt = @import("std").fmt;
const IOWriter = @import("std").io.Writer;
const Serial = @import("serial.zig").Serial;

pub fn Writer(putCharOuter: fn (u8) void) type {
    return struct {
        const writer = IOWriter(void, error{}, callback){ .context = {} };

        fn callback(_: void, string: []const u8) error{}!usize {
            write(string);
            return string.len;
        }

        pub fn putChar(byte: u8) void {
            putCharOuter(byte);
        }

        pub fn printf(comptime format: []const u8, args: anytype) void {
            fmt.format(writer, format, args) catch unreachable;
        }

        pub fn write(data: []const u8) void {
            for (data) |c| {
                putCharOuter(c);
            }
        }

        pub fn writeln(data: []const u8) void {
            printf("{s}\n", .{data});
        }
    };
}
