const std = @import("std");
const zigConcurrency = @import("zigConcurrency");
const ziro = @import("ziro");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us and the zig coro is {s}.\n", .{ "codebase", @typeName(ziro.asyncio) });
    const frame = ziro.xasync(a, .{}, null) catch |e| {
        std.debug.print(" got the error in making the fn async and it is {s} \n", .{@errorName(e)});
        unreachable;
    };
    std.debug.print("the type of frame is {any} \n ", .{""});
    ziro.xresume(frame);
    const returnValue = ziro.xawait(frame);
    std.debug.print("the return value of the fn is {any}\n", .{returnValue});
}

pub fn a() void {
    std.debug.print("hi from the fn a() and now we are suspending it \n", .{});
    ziro.xsuspend();
    std.debug.print("hi from the fn a() and now we have resumed it \n", .{});
    return;
}
