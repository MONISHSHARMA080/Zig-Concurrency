pub fn assertWithMessage(condition: bool, comptime message: []const u8) void {
    if (!condition) @panic(message);
}
