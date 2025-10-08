const std = @import("std");
const zigConcurrency = @import("zigConcurrency");
const ziro = @import("ziro");
const aio = ziro.asyncio;
const CoroutineBase = @import("./coroutine/coroutineBase.zig").CoroutineBase;

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("the  stack size of a() is {d} kb\n", .{@intFromPtr(&aFn) / 1000});
    std.debug.print("the  stack size of main() is {d} kn\n", .{@intFromPtr(&main) / 1000});
    std.debug.print("the fn b finished\n", .{});
    var stack: [1024 * 5]u8 align(16) = undefined;
    // var main_coro = CoroutineBase{ .stack_pointer = undefined };
    // var Acoro = try CoroutineBase.init(a, &stack);
    // Acoro.resumeFrom(&main_coro);
    // Acoro.resumeFrom(&main_coro);
    var coro = try CoroutineBase.initWithFunc(&fubCal, .{ 42, 100 }, &stack);
    var main_coro2: CoroutineBase = undefined;
    coro.resumeFrom(&main_coro2);
    std.debug.print("State: {}\n", .{coro.coroutineState}); // .Finished
}

fn fubCal(x: i32, y: i32) void {
    std.debug.print("Running with {} and {}\n", .{ x, y });
    var a: u128 = 0;
    var b: u128 = 1;
    for (0..1000) |i| {
        const newVal = a + b;
        a = b;
        b = newVal;
        std.debug.print("fub at {d} is {d}\n", .{ i, newVal });
        // yiled() ? how do we yield here
        if (newVal > 1000) return;
    }
}

pub fn aFn(from: *CoroutineBase, self: *CoroutineBase) void {
    std.debug.print("hi from the fn a() and now we are suspending it \n", .{});
    self.yield(from);
    std.debug.print(" 2 hi from the fn a() and now we have resumed it \n", .{});
    self.yield(from);
    std.debug.print("this in a should not be shown\n", .{});
    unreachable;
}
