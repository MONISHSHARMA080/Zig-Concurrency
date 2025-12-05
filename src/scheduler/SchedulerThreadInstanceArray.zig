const std = @import("std");
// const coroutine = @import("ZigConcurrency").Coroutine;
const coroutine = @import("../coroutine/coroutine.zig").Coroutine;
const util = @import("../utils/typeChecking.zig");
const queue = @import("../utils/queue.zig").ThreadSafeQueue;
const libxev = @import("xev");
const Allocator = std.mem.Allocator;
const allocOutOfMem = Allocator.Error;
const asserts = @import("../utils/assert.zig");
const assertWithMessage = asserts.assertWithMessageFmt;
const assertWithMessageFmtRuntime = asserts.assertWithMessageFmtRuntime;
const SchedulerInstancePerThread = @import("./SchedulerInstancePerThread.zig").SchedulerInstancePerThread;

pub const SchedulerThreadInstanceArray = struct {
    arr: []*SchedulerInstancePerThread,
    /// this is the current index of opr, like if removing this is the index you remove at and then you decrement it
    index: u32 = 0,
    schedulerInstanceSleepingLock: std.Thread.Mutex = std.Thread.Mutex{},
    full: bool = false,
    empty: bool = true,
    const Self = @This();

    pub fn init(allocator: Allocator, cpuCoreCount: u32) !SchedulerThreadInstanceArray {
        return SchedulerThreadInstanceArray{ .arr = try allocator.alloc(*SchedulerInstancePerThread, cpuCoreCount) };
    }

    pub fn insert(self: *Self, putInIdle: *SchedulerInstancePerThread) void {
        assertWithMessageFmtRuntime(self.full == false, "attempted to add to the indleQueue when the array is full, in schedulerInstance:{d}", .{putInIdle.SchedulerInstanceId});
        assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access of the idleQueue while adding the schedulerInstanceOnThread:{d}\n", .{putInIdle.SchedulerInstanceId});
        self.arr[self.index] = putInIdle;
        self.index += 1;
        std.debug.assert(self.index > 0);
        self.empty = false;
        if (self.index >= self.arr.len) {
            // as in if we are at 5th or more index after incrementation in arr of len 5 then we are full
            self.full = true;
            return;
        }
    }

    pub fn callNotifyOnLastOne(self: *Self) void {
        assertWithMessageFmtRuntime(self.empty == false, "attempted to remove from the idleQueue when the array is empty", .{});
        assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access as tried to access {d} in array of len {d}\n", .{ self.index, self.arr.len });
        self.arr[self.index].notify();
    }

    /// when the [schedulerToRemove] is null then we takes the last element at removes it and give it back
    pub fn remove(self: *Self, schedulerToRemove: ?*SchedulerInstancePerThread, comptime returnType: type) returnType {
        std.debug.assert(returnType == *SchedulerInstancePerThread or returnType == void);
        assertWithMessageFmtRuntime(self.empty == false, "attempted to remove from the idleQueue when the array is empty", .{});
        assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access as tried to access {d} in array of len {d}\n", .{ self.index, self.arr.len });
        // Find the scheduler instance in the array
        const foundIndex: ?u32 = blk: {
            if (schedulerToRemove) |scheduler| {
                var i: u32 = 0;
                while (i < self.index) : (i += 1) {
                    if (self.arr[i].SchedulerInstanceId == scheduler.SchedulerInstanceId) {
                        break :blk i;
                    }
                }
                break :blk null;
            } else {
                break :blk self.index;
            }
        };
        if (schedulerToRemove) |sch| {
            assertWithMessageFmtRuntime(foundIndex != null, "schedulerInstanceOnThread:{d} not found in the idleQueue for removal\n", .{sch.SchedulerInstanceId});
        } else {
            assertWithMessageFmtRuntime(foundIndex != null, "in remove() we are not able to find foundIndex at remove as it is null, the schedulerToRemove is also null", .{});
        }
        const indexToRemove = foundIndex.?;
        assertWithMessageFmtRuntime(indexToRemove < self.index, "found index {d} is out of bounds for current size {d}\n", .{ indexToRemove, self.index });
        const elementAtIndex = self.arr[indexToRemove];
        // Remove the element at the found index by shifting left
        // If we're removing from the middle, shift all elements after it to the left
        var i: u32 = indexToRemove;
        while (i < self.index - 1) : (i += 1) {
            self.arr[i] = self.arr[i + 1];
        }

        // Decrement index after removal operation
        if (self.index == 0) {
            self.index = 0;
            self.empty = true;
        } else {
            self.index -= 1;
        }

        // Update state flags
        self.full = false;

        assertWithMessageFmtRuntime(self.index < self.arr.len, "index {d} should be less than array length {d} after removal\n", .{ self.index, self.arr.len });
        switch (returnType) {
            void => return,
            else => return elementAtIndex,
        }
    }
};
