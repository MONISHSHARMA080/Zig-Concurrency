const std = @import("std");
// const coroutine = @import("ZigConcurrency").Coroutine;
const Coroutine = @import("../coroutine/coroutine.zig").Coroutine;
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
    arr: []?*SchedulerInstancePerThread,
    /// this is the current index of opr, like if removing this is the index you remove at and then you decrement it
    index: u32 = 0,
    // schedulerInstanceSleepingLock: std.Thread.Mutex = std.Thread.Mutex{},
    full: bool = false,
    empty: bool = true,
    lock: std.Thread.Mutex = std.Thread.Mutex{},
    const Self = @This();

    pub fn init(allocator: Allocator, cpuCoreCount: u32) !SchedulerThreadInstanceArray {
        return SchedulerThreadInstanceArray{ .arr = try allocator.alloc(?*SchedulerInstancePerThread, cpuCoreCount) };
    }

    pub fn insert(self: *Self, putInIdle: *SchedulerInstancePerThread) void {
        self.lock.lock();
        defer self.lock.unlock();
        assertWithMessageFmtRuntime(self.full == false, "attempted to add to the indleQueue when the array is full, in schedulerInstance:{d}", .{putInIdle.SchedulerInstanceId});
        assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access of the idleQueue while adding the schedulerInstanceOnThread:{d}\n", .{putInIdle.SchedulerInstanceId});
        std.debug.print(" the index is {d}\n", .{self.index});
        std.debug.assert(self.index >= 0);
        self.arr[self.index] = putInIdle;
        self.empty = false;
        if (self.index + 1 >= self.arr.len) {
            // as in if we are at 5th or more index after incrementation in arr of len 5 then we are full
            self.full = true;
            assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access of the idleQueue while adding the schedulerInstanceOnThread:{d}\n", .{putInIdle.SchedulerInstanceId});
            return;
        }
        self.index += 1;
        // assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access of the idleQueue while adding the schedulerInstanceOnThread:{d}\n", .{putInIdle.SchedulerInstanceId});
    }

    /// iterates from the last one to first index; returns false if the array is empty or can't put it in any of the coro in the array
    /// note: it is callers responsiblity to call mutex lock, and call it on the running/ready Queue
    pub fn putCoroInany(self: *Self, coro: *Coroutine, config: struct { alsoWakeItUp: bool = false }) bool {
        self.lock.lock();
        defer self.lock.unlock();
        assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access as tried to access {d} in array of len {d}\n", .{ self.index, self.arr.len });

        if (self.empty == true) return false;
        var i = self.index;
        while (i != 0) : (i -= 1) {
            if (self.arr[i]) |schedulerInstance| {
                schedulerInstance.readyQueue.put(coro) catch continue;
                if (config.alsoWakeItUp) {
                    schedulerInstance.notify();
                }
                return true;
            } else continue;
        }
        return false;
    }

    pub fn callNotifyOnLastOne(self: *Self) void {
        assertWithMessageFmtRuntime(self.empty == false, "attempted to remove from the idleQueue when the array is empty", .{});
        assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access as tried to access {d} in array of len {d}\n", .{ self.index, self.arr.len });
        // self.arr[self.index].notify();
        var i = self.arr.len - 1;
        while (i != 0) : (i -= 1) {
            if (self.arr[i]) |schedulerInstance| {
                schedulerInstance.notify();
                return;
            } else continue;
        }
    }

    /// when the [schedulerToRemove] is null then we takes the last element at removes it and give it back
    pub fn remove(self: *Self, schedulerToRemove: ?*SchedulerInstancePerThread, comptime returnType: type) returnType {
        std.debug.assert(returnType == *SchedulerInstancePerThread or returnType == void);
        assertWithMessageFmtRuntime(self.empty == false, "attempted to remove from the idleQueue when the array is empty\n", .{});
        assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access as tried to access {d} in array of len {d}\n", .{ self.index, self.arr.len });
        // Find the scheduler instance in the array
        var ia: u32 = 0;
        const foundIndex: ?u32 = blk: {
            if (schedulerToRemove) |schedulerInsToRemove| {
                while (ia < self.arr.len) : (ia += 1) {
                    if (self.arr[ia]) |schedulerIns| {
                        // std.debug.print("=== schedulerInstanceOnThread:{d} at index:{d} \n", .{ schedulerInsToRemove.SchedulerInstanceId, ia });
                        if (schedulerIns.SchedulerInstanceId == schedulerInsToRemove.SchedulerInstanceId) {
                            std.debug.print(" schedulerInstanceOnThread:{d} self.arr[{d}].SchedulerInstanceId:{d} == scheduler.SchedulerInstanceId:{d} we got \n", .{ schedulerInsToRemove.SchedulerInstanceId, ia, schedulerIns.SchedulerInstanceId, schedulerInsToRemove.SchedulerInstanceId });
                            break :blk ia;
                        } else continue;
                    } else continue;
                }
                // std.debug.print("=== schedulerInstanceOnThread:{d} at index:{d} and arr len is {d} and size:{d} and bout to retunr null \n", .{ schedulerInsToRemove.SchedulerInstanceId, ia, self.arr.len, self.arr.len - 1 });
                break :blk null;
            } else {
                const a: u32 = @intCast(self.arr.len);
                ia = a - 1;
                while (ia != 0) : (ia -= 1) {
                    if (self.arr[ia] != null) {
                        break :blk ia;
                    }
                }
                break :blk null;
            }
        };
        // maybe search the whole array in remove or make it []*?SchedulerInstancePerThread and when it is not there then make it null

        if (schedulerToRemove) |sch| {
            assertWithMessageFmtRuntime(foundIndex != null, "schedulerInstanceOnThread:{d} not found in the idleQueue for removal\n", .{sch.SchedulerInstanceId});
        } else {
            assertWithMessageFmtRuntime(foundIndex != null, "in remove() we are not able to find foundIndex at remove as it is null, the schedulerToRemove is also null\n", .{});
        }
        const indexToRemove = foundIndex.?;
        const schedulerInstanceId: i32 = if (schedulerToRemove == null) -1 else @intCast(schedulerToRemove.?.SchedulerInstanceId);
        assertWithMessageFmtRuntime(indexToRemove < self.arr.len, " schedulerInstanceOnThread:{d} found index {d} is out of bounds for current size {d}\n", .{ schedulerInstanceId, indexToRemove, self.index });
        const elementAtIndex = self.arr[indexToRemove];
        self.arr[indexToRemove] = null;
        if (self.index == 0) {
            self.index = 0;
            self.empty = true;
        } else {
            self.index -= 1;
        }
        self.full = false;
        assertWithMessageFmtRuntime(self.index < self.arr.len, "index {d} should be less than array length {d} after removal\n", .{ self.index, self.arr.len });
        switch (returnType) {
            void => return,
            else => return elementAtIndex,
        }
    }
};
