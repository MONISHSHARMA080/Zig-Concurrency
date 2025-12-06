const std = @import("std");

pub fn assertWithMessage(condition: bool, comptime message: []const u8) void {
    if (!condition) @panic(message);
}
pub fn assertWithMessageFmt(condition: bool, comptime message: []const u8, comptime args: anytype) void {
    if (!condition) @panic(std.fmt.comptimePrint(message, args));
}
pub fn assertWithMessageFmtRuntime(condition: bool, comptime message: []const u8, args: anytype) void {
    if (!condition) {
        std.debug.print(message, args);
        @panic("");
    }
}

pub fn assertWithMessageFmtCompileTime(comptime condition: bool, comptime message: []const u8, comptime args: anytype) void {
    if (!condition) @compileError(std.fmt.comptimePrint(message, args));
}
