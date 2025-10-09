const std = @import("std");
const zigConcurrency = @import("zigConcurrency");
const CoroutineBase = @import("./coroutine/coroutineBase.zig").CoroutineBase;

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("the  stack size of a() is {d} kb\n", .{@intFromPtr(&aFn) / 1000});
    std.debug.print("the  stack size of main() is {d} kn\n", .{@intFromPtr(&main) / 1000});
    std.debug.print("the fn b finished\n", .{});
    // var stack: [1024 * 5]u8 align(16) = undefined;
    // var main_coro = CoroutineBase{ .stack_pointer = undefined };
    // var Acoro = try CoroutineBase.init(a, &stack);
    // Acoro.resumeFrom(&main_coro);
    // Acoro.resumeFrom(&main_coro);
    std.debug.print("\nin the main\n", .{});
    try calling();
    // const alloc = std.heap.GeneralPurposeAllocator(.{}).init;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var coro = try CoroutineBase.initWithFunc(&fubCal, .{ 42, 100 }, allocator, .{});
    var main_coro2: CoroutineBase = .{
        .stack = &[_]u8{},
        .stack_pointer = undefined,
        .allocator = undefined,
    };
    defer main_coro2.destroy();
    defer coro.destroy();
    std.debug.print("State after created: {}\n", .{coro.coroutineState}); // .Finished
    for (0..10) |i| {
        if (coro.coroutineState != .Finished) {
            std.debug.print("the corotine is not finish  in main at {d}\n", .{i});
            coro.resumeFrom(&main_coro2);
        } else {
            std.debug.print("the corotine is marked finish in main at {d}\n", .{i});
            break;
        }
    }
    std.debug.print("State: {}\n", .{coro.coroutineState}); // .Finished
}

fn immediateYield(self: *CoroutineBase) void {
    self.yield();
}

fn calling() !void {
    // _ = self;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    std.debug.print("in the calling and creating coro and main_coro2 \n", .{});
    var coro = try CoroutineBase.initWithFunc(&aFn, .{}, allocator, .{});
    defer coro.destroy();
    std.debug.print("in the calling() and attempting to call main_coro2 from it \n", .{});
    var main_coro2: CoroutineBase = .{
        .stack = &[_]u8{},
        .stack_pointer = undefined,
        .allocator = undefined,
    };

    coro.resumeFrom(&main_coro2); // Saves calling() context here

    std.debug.print("i am in the calling() and got hit with yield\n", .{});
    std.debug.print("here is the work in the calling() \n", .{});
    std.debug.print("State in calling(): {}\n\n", .{coro.coroutineState});

    for (0..20) |i| {
        std.debug.print("{d} -- ", .{i});
    }

    std.debug.print("\nhere the work is done in the calling() \n", .{});

    for (0..10) |i| {
        if (coro.coroutineState != .Finished) {
            std.debug.print("the corotine is not finish at {d}\n", .{i});
            coro.resumeFrom(&main_coro2); // Resume with saved context
        } else {
            std.debug.print("the corotine is marked finish at {d}\n", .{i});
            break;
        }
    }
    std.debug.print("i am in the calling() and got hit with yield\n", .{});
    std.debug.print("here is the work in the calling() \n", .{});
    std.debug.print("State in calling(): {}\n\n", .{coro.coroutineState}); // .Finished
    for (0..20) |i| {
        std.debug.print("{d} -- ", .{i});
    }
    std.debug.print("here the work is done in the calling() \n", .{});
    for (0..10) |i| {
        if (coro.coroutineState != .Finished) {
            std.debug.print("the corotine is not finish at {d}\n", .{i});
            coro.resumeFrom(&main_coro2);
        } else {
            std.debug.print("the corotine is marked finish at {d}\n", .{i});
            break;
        }
    }
    // the fn coroutineWrapper is not running I think(or at the compile time)
    std.debug.print("State in calling()'s end: {}\n\n", .{coro.coroutineState}); // .Finished
}

fn fubCal(coro: *CoroutineBase, x: i32, y: i32) void {
    std.debug.print("in the fubcal fn\n", .{});
    std.debug.print("Running with {} and {}\n", .{ x, y });
    var a: u128 = 0;
    var b: u128 = 1;
    for (0..1000) |i| {
        const newVal = a + b;
        a = b;
        b = newVal;
        if (i % 5 == 0 and i != 0) {
            std.debug.print("fub at {d} is {d} and it is % 32 so we are yielding\n", .{ i, newVal });
            coro.yield();
        }
        std.debug.print("fub at {d} is {d}\n", .{ i, newVal });
        if (i > 17) return;
    }
}

pub fn aFn(self: *CoroutineBase) void {
    std.debug.print("hi from the fn aFn() and now we are suspending it \n", .{});

    // self.yield(from);
    std.debug.print(" 2 hi from the fn aFn() and now we have resumed it \n", .{});
    self.yield();
    std.debug.print("this in a should not be shown\n", .{});
    // unreachable;
}
