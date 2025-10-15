const std = @import("std");
const Coroutine = @import("ZigConcurrency").Coroutine;
const assert = std.debug.assert;

/// Creates an array containing all numbers from `start` to `end` (inclusive) in random order
/// Caller owns the returned array and must free it
fn randomizedRange(
    allocator: std.mem.Allocator,
    start: i64,
    end: i64,
) ![]i64 {
    if (start > end) {
        return error.InvalidRange;
    } else if (start <= 1) {
        // this mess with the odd even
        return error.StartCantBeOneOr0;
    }

    const count = @as(usize, @intCast(end - start + 1));

    // Allocate array
    var arr = try allocator.alloc(i64, count);

    // Fill array with sequential values
    for (0..count) |i| {
        arr[i] = start + @as(i64, @intCast(i));
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

    // assert that we have all the nos.
    for (@intCast(start)..@intCast(end)) |numberToCheck| {
        var foundAt: ?i64 = null;
        for (arr, 0..) |valueAtIndex, index| {
            if (numberToCheck == valueAtIndex) {
                foundAt = @intCast(index);
                break;
            }
        }
        std.debug.assert(foundAt != null);
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

fn putTheEvenNoInArray(self: *Coroutine, evenNoInArray: u64, atIndexInTheSortedArray: u64, sortedArray: []i64, randomeizedArray: []i64) void {
    // the problem is that if the array starts from 10 then we are not getting the value
    assert(atIndexInTheSortedArray <= sortedArray.len);
    var newElementToPut: i64 = 0;
    for (randomeizedArray) |value| {
        // if we are at index 4 for eg, then we are searching for element/no 4
        if (value == evenNoInArray) {
            newElementToPut = value;
        }
    }
    // std.debug.print("the remainder of dividing {d} % 2 is {d} \n", .{ newElementToPut, @rem(newElementToPut, 2) });
    assert(@mod(newElementToPut, 2) == 0);

    // std.debug.print("at the sortedArray[{d}] we put the value {d} and it is {d}\n", .{ atIndexInTheSortedArray, newElementToPut, sortedArray[atIndexInTheSortedArray] });
    sortedArray[atIndexInTheSortedArray] = newElementToPut;
    // std.debug.print("after assignment sortedArray[{d}] we put the value {d} and it is {d}\n", .{ atIndexInTheSortedArray, newElementToPut, sortedArray[atIndexInTheSortedArray] });
    if (atIndexInTheSortedArray > 0) {
        std.debug.print("at index - 1:{d}; sortedArray[atIndex - 1]:{d}  and newElementToPut -1 {d} should be equal\n ", .{ atIndexInTheSortedArray - 1, sortedArray[atIndexInTheSortedArray - 1], newElementToPut - 1 });
        assert(sortedArray[atIndexInTheSortedArray - 1] == newElementToPut - 1); // at index:4 we have newElementToPut:4 and we want atIndex:3 the element 3
        assert(sortedArray[atIndexInTheSortedArray - 1] + 1 == sortedArray[atIndexInTheSortedArray]); // I know this is same as above but why not
    }
    if (atIndexInTheSortedArray == sortedArray.len - 1) self.coroutineState = .Finished;
    self.yield();
}

fn putTheOddNoInArray(self: *Coroutine, evenNoInArray: u64, atIndexInTheSortedArray: u64, sortedArray: []i64, randomeizedArray: []i64) void {
    // the problem is that if the array starts from 10 then we are not getting the value
    assert(atIndexInTheSortedArray <= sortedArray.len);
    var newElementToPut: i64 = 0;
    for (randomeizedArray) |value| {
        // if we are at index 4 for eg, then we are searching for element/no 4
        if (value == evenNoInArray) {
            newElementToPut = value;
        }
    }
    // std.debug.print("the remainder of dividing {d} % 2 is {d} \n", .{ newElementToPut, @rem(newElementToPut, 2) });
    assert(@mod(newElementToPut, 2) != 0);

    std.debug.print("at the sortedArray[{d}] we put the value {d} and it is {d}\n", .{ atIndexInTheSortedArray, newElementToPut, sortedArray[atIndexInTheSortedArray] });
    sortedArray[atIndexInTheSortedArray] = newElementToPut;
    std.debug.print("after assignment sortedArray[{d}] we put the value {d} and it is {d}\n", .{ atIndexInTheSortedArray, newElementToPut, sortedArray[atIndexInTheSortedArray] });
    if (atIndexInTheSortedArray > 0) {
        std.debug.print("at index - 1:{d}; sortedArray[atIndex - 1]:{d}  and newElementToPut -1 {d} should be equal\n ", .{ atIndexInTheSortedArray - 1, sortedArray[atIndexInTheSortedArray - 1], newElementToPut - 1 });
        assert(sortedArray[atIndexInTheSortedArray - 1] == newElementToPut - 1); // at index:4 we have newElementToPut:4 and we want atIndex:3 the element 3
        assert(sortedArray[atIndexInTheSortedArray - 1] + 1 == sortedArray[atIndexInTheSortedArray]); // I know this is same as above but why not
    }

    if (atIndexInTheSortedArray == sortedArray.len - 1) self.coroutineState = .Finished;
    self.yield();
}

// Helper function to process all even numbers and yield after each one
fn process_even_numbers(self: *Coroutine, data: struct { sortedArray: []i64, randomizedArray: []i64, start: i64, end: i64 }) void {
    const sortedArray = data.sortedArray;
    const randomizedArray = data.randomizedArray;
    const start = data.start;
    const end = data.end;

    for (start..end + 1) |value| {
        const index = @as(u64, @intCast(value - start));
        if (@mod(value, 2) == 0) {
            // Note: putTheEvenNoInArray is called as a regular function.
            // It uses the passed 'self' (the current coroutine's context) to yield.
            putTheEvenNoInArray(self, @as(u64, value), index, sortedArray, randomizedArray);
        }
    }
    std.debug.print("Even Coroutine Finished.\n", .{});
    // Ensure the state is marked finished, though the last putTheEvenNoInArray call should handle it if it was the very last element overall.
    self.coroutineState = .Finished;
}

// Helper function to process all odd numbers and yield after each one
fn process_odd_numbers(self: *Coroutine, data: struct { sortedArray: []i64, randomizedArray: []i64, start: i64, end: i64 }) void {
    const sortedArray = data.sortedArray;
    const randomizedArray = data.randomizedArray;
    const start = data.start;
    const end = data.end;

    for (start..end + 1) |value| {
        const index = @as(u64, @intCast(value - start));
        if (@mod(value, 2) != 0) {
            // Note: putTheOddNoInArray is called as a regular function.
            // It uses the passed 'self' (the current coroutine's context) to yield.
            putTheOddNoInArray(self, @as(u64, value), index, sortedArray, randomizedArray);
        }
    }
    std.debug.print("Odd Coroutine Finished.\n", .{});
    self.coroutineState = .Finished;
}

test "checking if the coroutine can pause and resume" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const start = 10;
    const end = 100;
    const array = try randomizedRange(allocator, start, end);
    defer allocator.free(array);
    const count = @as(usize, @intCast(end - start + 1));
    const sortedArray = try allocator.alloc(i64, count);
    var main_coro: Coroutine = .{
        .stack = &[_]u8{},
        .stack_pointer = undefined,
        .allocator = allocator,
    };
    for (start..end, 0..) |value, index| {
        const a = @as(u64, value);
        // _ = index;
        var evenNoInCoro = try Coroutine.initWithFunc(&putTheEvenNoInArray, .{ a, index, sortedArray, array }, allocator, .{});
        defer evenNoInCoro.destroy();
        var oddNoInCoro = try Coroutine.initWithFunc(&putTheOddNoInArray, .{ a, index, sortedArray, array }, allocator, .{});
        defer oddNoInCoro.destroy();
        if (@mod(value, 2) == 0) {
            // putTheEvenNoInArray(&main_coro, a, index, sortedArray, array);
            evenNoInCoro.resumeFrom(&main_coro);
            std.debug.print("got out from even coro \n", .{});
        } else {
            // putTheOddNoInArray(&main_coro, a, index, sortedArray, array);
            oddNoInCoro.resumeFrom(&main_coro);
            std.debug.print("got out from odd coro \n", .{});
        }
    }
    defer allocator.free(sortedArray);

    // verifying that we got this shit right
    for (@intCast(start)..@intCast(end)) |numberToCheck| {
        var foundAt: ?i64 = null;
        for (array, 0..) |valueAtIndex, index| {
            if (numberToCheck == valueAtIndex) {
                foundAt = @intCast(index);
                break;
            }
        }
        std.debug.assert(foundAt != null);
    }
    // now let's play the game of odd even , or smth where if we found the number bigger than the last one then we will add it to the array and yield and let the other
    // fn do it's job, we can make this into multiple fn
}
