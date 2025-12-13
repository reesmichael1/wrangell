const std = @import("std");
const IOWriter = std.io.Writer;

pub fn Writer(comptime ContextType: type, comptime ErrType: type, comptime Callback: fn (ContextType, []const u8) ErrType!usize) type {
    return struct {
        const Error = ErrType;
        writer: IOWriter(ContextType, Error, Callback),
        context: ContextType,

        const Self = @This();

        pub fn init(context: ContextType) Self {
            return Self{
                .writer = IOWriter(ContextType, Error, Callback){
                    .context = context,
                },
                .context = context,
            };
        }

        pub fn printf(self: *Self, comptime fmt: []const u8, args: anytype) void {
            std.fmt.format(self.writer, fmt, args) catch unreachable;
        }

        pub fn write(self: *Self, data: []const u8) Error!void {
            _ = self.writer.writeAll(data);
            return null;
        }
    };
}
