const std = @import("std");
const zigConcurrency = @import("zigConcurrency");
const ziro = @import("ziro");
const aio = ziro.asyncio;
const CoroutineBase = @import("./coroutine/coroutineBase.zig").CoroutineBase;

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("the  stack size of a() is {d} kb\n", .{@intFromPtr(&a) / 1000});
    std.debug.print("the  stack size of main() is {d} kn\n", .{@intFromPtr(&main) / 1000});
    b();
    std.debug.print("the fn b finished\n", .{});
    var stack: [1024 * 5]u8 align(16) = undefined;
    var worker = try CoroutineBase.init(a, &stack);
    var main_coro = CoroutineBase{ .stack_pointer = undefined };
    worker.resumeFrom(&main_coro);
    worker.resumeFrom(&main_coro);
}

pub fn b() void {
    std.debug.print(" hi this statement is from fn b() and I am now going to yield\n", .{});
    // var stack: [1024 * 5]u8 align(16) = undefined;
    // var worker = try CoroutineBase.init(main, &stack);
    var worker = CoroutineBase{ .stack_pointer = undefined };
    worker.yield(&worker);
    std.log.err("-------in b() this should not execute ------\n", .{});
}
pub fn a(from: *CoroutineBase, self: *CoroutineBase) callconv(.c) noreturn {
    std.debug.print("hi from the fn a() and now we are suspending it \n", .{});

    // Yield back to caller
    self.yield(from);

    std.debug.print("hi from the fn a() and now we have resumed it \n", .{});

    // Must yield back one final time (can't just return)
    self.yield(from);

    unreachable; // Mark that we never actually return
}
