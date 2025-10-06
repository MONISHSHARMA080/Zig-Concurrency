const std = @import("std");
const zigConcurrency = @import("zigConcurrency");
const ziro = @import("ziro");
const aio = ziro.asyncio;
const CoroutineBase = @import("./coroutine/coroutineBase.zig").CoroutineBase;

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us and the zig coro is {s}.\n", .{ "codebase", @typeName(ziro.asyncio) });
    std.debug.print("the return value of the fn is {s}\n", .{"---"});
    var stack: [81192]u8 align(16) = undefined;
    var worker = try CoroutineBase.init(a, &stack);
    var main_coro = CoroutineBase{ .stack_pointer = undefined };
    worker.resumeFrom(&main_coro);
    worker.resumeFrom(&main_coro);
}
pub fn a(from: *CoroutineBase, self: *CoroutineBase) callconv(.c) noreturn {
    std.debug.print("hi from the fn a() and now we are suspending it \n", .{});

    // Yield back to caller
    self.yield(from);

    std.debug.print("hi from the fn a() and now we have resumed it \n", .{});

    // Must yield back one final time (can't just return)
    from.resumeFrom(self);

    unreachable; // Mark that we never actually return
}
