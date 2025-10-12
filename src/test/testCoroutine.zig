const std = @import("std");
// const Coroutine = @import("ZigConcurrency").ZigConcurrency.Coroutine;
const Coroutine = @import("ZigConcurrency").Coroutine;

/// Creates an array containing all numbers from `start` to `end` (inclusive) in random order
/// Caller owns the returned array and must free it
fn randomizedRange(
    allocator: std.mem.Allocator,
    start: i32,
    end: i32,
) ![]i32 {
    if (start > end) {
        return error.InvalidRange;
    }

    const count = @as(usize, @intCast(end - start + 1));

    // Allocate array
    var arr = try allocator.alloc(i32, count);

    // Fill array with sequential values
    for (0..count) |i| {
        arr[i] = start + @as(i32, @intCast(i));
    }

    // Fisher-Yates shuffle
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    for (0..count - 1) |i| {
        const j = i + random.uintLessThan(usize, count - i);
        const temp = arr[i];
        arr[i] = arr[j];
        arr[j] = temp;
    }

    return arr;
}
fn calling() !void {
    // _ = self;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    std.debug.print("in the calling and creating coro and main_coro2 \n", .{});
    var coro = try Coroutine.initWithFunc(&aFn, .{}, allocator, .{});
    defer coro.destroy();
    std.debug.print("in the calling() and attempting to call main_coro2 from it \n", .{});
    var main_coro2: Coroutine = .{
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

fn fubCal(coro: *Coroutine, x: i32, y: i32) void {
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
pub fn aFn(self: *Coroutine) void {
    std.debug.print("hi from the fn aFn() and now we are suspending it \n", .{});

    // self.yield(from);
    std.debug.print(" 2 hi from the fn aFn() and now we have resumed it \n", .{});
    self.yield();
    std.debug.print("this in a should not be shown\n", .{});
    // unreachable;
}
test "checking if the coroutine can pause and resume" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const start = 10;
    const end = 100;
    const array = try randomizedRange(allocator, start, end);
    defer allocator.free(array);
    for (0..20) |number| {
        var foundAt: ?u64 = null;
        for (array, 0..) |value, i| {
            if (number == value) {
                foundAt = i;
                break;
            }
        }
        std.debug.assert(foundAt != null);
    }
    // now let's play the game of odd even , or smth where if we found the number bigger than the last one then we will add it to the array and yield and let the other
    // fn do it's job, we can make this into multiple fn
}
