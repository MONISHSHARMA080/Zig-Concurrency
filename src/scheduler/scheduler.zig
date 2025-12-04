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
const assertWithRuntimeMessage = asserts.assertWithMessageFmtRuntime;
const SchedulerInstancePerThread = @import("./SchedulerInstancePerThread.zig").SchedulerInstancePerThread;
//
//probelm: how do we integrate the runtime here, like when the
//
//todo: 1st we need to design the schedulerInstanceOnThread, then we need to make the libxev loop in there running
//

pub const Scheduler = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    schedulerInstanceOnThread: ?SchedulerInstancePerThread,
    globalRunQueue: queue(*coroutine),
    idleQueue: SchedulerThreadInstanceArray,
    runningQueue: SchedulerThreadInstanceArray,
    schedulerInstanceSleepingLock: std.Thread.Mutex = std.Thread.Mutex{},
    SchedulerInstancesOnThreads: []*SchedulerInstancePerThread,

    const SchedulerThreadInstanceArray = struct {
        arr: []*SchedulerInstancePerThread,
        /// this is the current index of opr, like if removing this is the index you remove at and then you decrement it
        index: u32 = 0,
        schedulerInstanceSleepingLock: std.Thread.Mutex = std.Thread.Mutex{},
        full: bool = false,
        empty: bool = true,
        const Self = @This();

        pub fn init(allocator: Allocator, cpuCoreCount: u32) !void {
            return SchedulerThreadInstanceArray{ .arr = try allocator.alloc(*SchedulerInstancePerThread, cpuCoreCount) };
        }

        pub fn insert(self: *Self, putInIdle: *SchedulerInstancePerThread) void {
            asserts.assertWithMessageFmtRuntime(self.full == false, "attempted to add to the indleQueue when the array is full", .{putInIdle.SchedulerInstanceId});
            asserts.assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access of the idleQueue while adding the schedulerInstanceOnThread:{d}\n", .{putInIdle.SchedulerInstanceId});
            // const schedulerToPutToSleep: ?*SchedulerInstancePerThread = blk: {
            //     for (self.arr) |value| {
            //         if (value.SchedulerInstanceId == putInIdle.SchedulerInstanceId) break :blk value;
            //     }
            //     break :blk null;
            // };
            // asserts.assertWithMessageFmtRuntime(schedulerToPutToSleep != null, "in registerIdle() we got to put the schedulerInstanceOnThread:{d} to sleep. but it was not in the runningQueue \n", .{putInIdle.SchedulerInstanceId});
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
            asserts.assertWithMessageFmtRuntime(self.empty == false, "attempted to remove from the idleQueue when the array is empty", .{});
            asserts.assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access as tried to access {d} in array of len {d}\n", .{ self.index, self.arr.len });
            self.arr[self.index].notify();
        }

        /// when the [schedulerToRemove] is null then we takes the last element at removes it and give it back
        pub fn remove(self: *Self, schedulerToRemove: ?*SchedulerInstancePerThread, comptime returnType: type) returnType {
            std.debug.assert(returnType == *SchedulerInstancePerThread or returnType == void);
            asserts.assertWithMessageFmtRuntime(self.empty == false, "attempted to remove from the idleQueue when the array is empty", .{});
            asserts.assertWithMessageFmtRuntime(self.index < self.arr.len, "out of bounds array access as tried to access {d} in array of len {d}\n", .{ self.index, self.arr.len });
            // Find the scheduler instance in the array
            const foundIndex: ?u32 = blk: {
                switch (schedulerToRemove) {
                    null => {
                        break :blk self.index;
                    },
                    else => {
                        var i: u32 = 0;
                        while (i < self.index) : (i += 1) {
                            if (self.arr[i].SchedulerInstanceId == schedulerToRemove.SchedulerInstanceId) {
                                break :blk i;
                            }
                        }
                        break :blk null;
                    },
                }
            };

            asserts.assertWithMessageFmtRuntime(foundIndex != null, "schedulerInstanceOnThread:{d} not found in the idleQueue for removal\n", .{schedulerToRemove.SchedulerInstanceId});

            const indexToRemove = foundIndex.?;
            asserts.assertWithMessageFmtRuntime(indexToRemove < self.index, "found index {d} is out of bounds for current size {d}\n", .{ indexToRemove, self.index });

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

            asserts.assertWithMessageFmtRuntime(self.index < self.arr.len, "index {d} should be less than array length {d} after removal\n", .{ self.index, self.arr.len });
            switch (returnType) {
                void => return,
                else => return elementAtIndex,
            }
        }
        // / does not call the lock
        // pub fn pop(self: *Self) ?*SchedulerInstancePerThread {
        //     // [1] Acquire the lock before checking/modifying
        //     if (self.index == 0) {
        //         return null; // Queue is empty
        //     }
        //     self.index -= 1;
        //     self.full = false;
        //     // The last element before decrementing is at self.index
        //     return self.arr[self.index];
        // }
    };

    pub fn init(allocatorArg: std.mem.Allocator, comptime options: struct { defualtGlobalRunQueueSize: u64 = 650 }) std.mem.Allocator.Error!Scheduler {
        const defualtCpuAssumption: u32 = 1;
        const cpuCoreCount: u32 = std.Thread.getCpuCount() catch |err| {
            std.debug.print("\n\n[WARN] error in gettting the no of cpus:{s} instead defaulting to {d}\n\n", .{ @errorName(err), defualtCpuAssumption });
        } orelse defualtCpuAssumption;
        // const cpuCoreCount: u32 = std.Thread.getCpuCount() catch |err| bkl: {
        //     const defualtCpuAssumption: u32 = 1;
        //     std.debug.print("\n\n[WARN] error in gettting the no of cpus:{s} instead defaulting to {d}\n\n", .{ @errorName(err), defualtCpuAssumption });
        //     break :bkl defualtCpuAssumption;
        // };
        return Scheduler{
            .allocator = allocatorArg,
            .schedulerInstanceOnThread = null,
            .globalRunQueue = try queue(*coroutine).init(allocatorArg, .{ .listSize = options.defualtGlobalRunQueueSize }),
            .idleQueue = try SchedulerThreadInstanceArray.init(allocatorArg, cpuCoreCount),
            .runningQueue = try SchedulerThreadInstanceArray.init(allocatorArg, cpuCoreCount),
            .schedulerInstanceSleepingLock = std.Thread.Mutex{},
        };
    }

    /// impl it
    pub fn destroy(self: *Scheduler) void {
        // self.globalRunQueue.
        // destroy the coroutines in the fn first from the queue and then the destroy of queue, or we can give the queue
        // a comptime method name and tell it to call it while freeing
        _ = self;
    }

    /// blocks
    pub fn registerIdle(self: *Scheduler, putInIdle: *SchedulerInstancePerThread) void {
        self.schedulerInstanceSleepingLock.lock();
        defer self.schedulerInstanceSleepingLock.unlock();
        self.idleQueue.insert(putInIdle);
        self.runningQueue.remove(putInIdle, void);
    }

    /// blocks
    pub fn deRegisterIdle(self: *Scheduler, putInIdle: *SchedulerInstancePerThread) void {
        self.schedulerInstanceSleepingLock.lock();
        defer self.schedulerInstanceSleepingLock.unlock();
        self.runningQueue.insert(putInIdle);
        self.idleQueue.remove(putInIdle, void);
    }

    /// this fn puts the coro in the global runQueue note this is slow as to check if the threads are sleeping we use a mutex and will slow you down try not to use it too much
    pub fn go(self: *Scheduler, comptime Fn: anytype, comptime fnArgs: anytype, options: struct {
        /// if there are 2 same types of the param then you need to provide their type 2 times as we will only skip for one type in the array once
        typeToSkipInChecking: ?[]const type = &[_]type{*coroutine},
        skipTypeChecking: bool = false,
    }) allocOutOfMem!void {

        // this fn will take in a fn and convert it into a coroutine and store it somewhere(global run queue etc)
        // ok here is a quick and dirty version of the scheduler just take in the struct that has the fn and atis args as a array and then convert them into coro
        // and start executing them, if one of them yield then I want you to take the next one and start executing it  until the state is finnished
        //
        // just hardcode some fn here and make them start
        if (options.skipTypeChecking == false) {
            const typeIsCorrect = comptime util.validateArgsMatchFunction(Fn, fnArgs, options.typeToSkipInChecking);
            if (!typeIsCorrect) @compileError("there is a type mismatch between the fn and the parameter type in the args provided");
        }
        const coro = coroutine.init(Fn, fnArgs, self.allocator, .{}) catch |err| switch (err) {
            coroutine.err.OutOfMemory => return allocOutOfMem.OutOfMemory,
            coroutine.err.StackTooSmall => @panic("the stack size of coroutine for the fn is small\n"),
        };
        try self.globalRunQueue.put(coro);
        self.schedulerInstanceSleepingLock.lock();
        defer self.schedulerInstanceSleepingLock.unlock();
        if (self.idleQueue.index == 0) return;
        self.idleQueue.callNotifyOnLastOne();
        return;
    }
};

// var coro1 = coroutine.init(&one, .{self}, self.allocator, .{}) catch unreachable;
// var coro2 = coroutine.init(&two, .{self}, self.allocator, .{}) catch unreachable;
// defer coro1.destroy();
// defer coro2.destroy();
// var main_coro: coroutine = .{
//     .stack = &[_]u8{},
//     .stack_pointer = undefined,
//     .allocator = undefined,
// };
// std.debug.print("in the scheduler's go fn\n", .{});
// coro1.targetCoroutineToYieldTo = &main_coro;
// coro2.targetCoroutineToYieldTo = &main_coro;
//
// while (coro1.coroutineState != .Finished or coro2.coroutineState != .Finished) {
//     // Run coro1 if not finished
//     if (coro1.coroutineState != .Finished) {
//         std.debug.print("[Scheduler loop] starting coro1\n", .{});
//         // coro1.startFrom(&main_coro);
//         coro1.startRunning();
//         std.debug.print("[Scheduler loop] coro1 has yielded\n", .{});
//     }
//
//     // Run coro2 if not finished
//     if (coro2.coroutineState != .Finished) {
//         std.debug.print("[Scheduler loop] starting coro2\n", .{});
//         coro2.startRunning();
//         std.debug.print("[Scheduler loop] coro2 has yielded\n", .{});
//     }
// }
//
// std.debug.print("[Scheduler] Both coroutines finished!\n", .{});
