pub fn assertWithMessage(condition: bool, comptime message: u8) void {
    if (!condition) @panic(message);
}
