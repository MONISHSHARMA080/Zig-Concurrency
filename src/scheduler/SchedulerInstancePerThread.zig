const std = @import("std");
// const coroutine = @import("ZigConcurrency").Coroutine;
const coroutine = @import("../coroutine/coroutine.zig").Coroutine;
const util = @import("../utils/typeChecking.zig");
const queue = @import("../utils/queue.zig").ThreadSafeQueue;
const Scheduler = @import("./scheduler.zig").Scheduler;
const libxev = @import("xev");
const allocator = std.mem.Allocator;
const allocOutOfMem = allocator.Error;
const asserts = @import("../utils/assert.zig");
const assertWithMessage = asserts.assertWithMessage;

pub const SchedulerInstancePerThread = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    parentScheduler: *Scheduler,
    readyQueue: queue(*coroutine, .{ .listSize = 100 }),
    waitQueue: queue(*coroutine, .{ .listSize = 100 }),
    // wakeMeUpWhenWorkArrives: std.atomic.Value(bool)= std.atomic.Value(bool).init(false),
    SchedulerInstanceId: u32,
    /// [the SchedulerInstance has completed the work and no other work is to be found and when we get one in the queue then wake it up]
    futex: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    const SpinLimit = 320;
    const Self = @This();

    /// notify the scheduler that the work is there and wake the thread up
    pub fn notify(self: *Self) !void {
        _ = self.futex.fetchAdd(1, .Release);
        // 2. Wake the thread if it is sleeping
        std.Thread.Futex.wake(&self.futex, 1);
    }

    inline fn park(self: *Self) ?*coroutine {
        // [B] Snapshot the current state of the futex
        // This is the 'ticket' we use to safely enter the wait state.
        const ticket = self.futex.load(.Monotonic);
        // [C] Spinning Phase: Try to find work again without syscalls
        // Double-check for work after setting futex
        // (prevents race condition where work arrives between check and wait)
        for (0..SpinLimit) |i| {
            _ = i;
            std.atomic.spinLoopHint();
            if (self.getWorkOrNull()) |coro| {
                return coro;
            }
        }
        // [D] Sleep Phase: No work after spinning. Commit to kernel wait.
        // We pass the 'ticket' grabbed at [B].
        // If self.futex is STILL 'ticket', the OS puts us to sleep.
        // If self.futex is != 'ticket' (someone pushed work), we return immediately.
        self.parentScheduler.registerIdle(self);
        std.Thread.Futex.wait(&self.futex, ticket);

        return null;
    }

    pub fn run(self: *SchedulerInstancePerThread) !void {
        var coroToRunOther: coroutine = .{
            .stack = &[_]u8{},
            .stack_pointer = undefined,
            .allocator = undefined,
        };
        while (true) {
            //[1st] check is the sys calls are completed,using libxev and make coro as runnable : Not implemented
            //[2nd] check the local run queue, is coro then run it
            //[3rd] check the global run queue, is coro then run it
            //[4th] try work stealing
            //[5th] if both are not there and also not one waiting in the waitingQueue then wait on a futex or conditional var
            const coroToRun: *coroutine = blk: {
                if (getWorkOrNull()) |coro| {
                    break :blk coro;
                }
                if (self.park()) |coro| {
                    break :blk coro;
                }
                continue;
            };
            // run the coroutine and then repeat the loop
            coroToRun.targetCoroutineToYieldTo = &coroToRunOther;
            coroToRun.startRunning();
            if (coroToRun.coroutineState == .Finished) {
                // if the coro is finish then destroy and move on
                coroToRun.destroy();
            }
        }
    }

    /// gets work form 1>readyQueue 2> globalRunQueue 3> work stealing; if still none then return null
    fn getWorkOrNull(self: *Self) ?*coroutine {
        if (self.readyQueue.pop()) |coroInReadyQueue| {
            return coroInReadyQueue;
        } else if (self.parentScheduler.globalRunQueue.pop()) |coroInGlobalRunQueue| {
            return coroInGlobalRunQueue;
        } else if (self.workStealingAndPutItInRunQueue()) {
            const coro = self.readyQueue.pop();
            assertWithMessage(coro != null, "the value that was put into the runQueue via workStealingAndPutItInRunQueue fn should have been null when the queue is just popped \n");
            return coro.?;
        } else {
            return null;
        }
    }

    /// retunrs true if found the work
    fn workStealingAndPutItInRunQueue(self: *Self) bool {
        // go to other schedulerInstanceOnThread and try to see if they have coro in the readyQueue, if yes then get it

        var foundWork = false;
        for (self.parentScheduler.SchedulerInstancesOnThreads) |schedulerInstance| {
            if (schedulerInstance.SchedulerInstanceId == self.SchedulerInstanceId) continue;
            if (schedulerInstance.readyQueue.popNTimesOrLess(.{})) |coro| {
                self.readyQueue.putNTimes(coro) catch {
                    schedulerInstance.readyQueue.putNTimes(coro) catch {
                        std.debug.panic("\n got multiple coros form schedulerInstance:{d} during work stealing and tried to put it in my schedulerInstance's:{d} run queue but got allocOutOfMem error and then tried to put them back and still got the same error , don't know what to do with this coroutine so crashing\n", .{ schedulerInstance.SchedulerInstanceId, self.SchedulerInstanceId });
                        // probably delete some freed list in the shcedulers etc, and try it again
                    };
                };
                foundWork = true;
            } else continue;
        }
        return foundWork;
    }

    pub fn init(allocator1: allocator) allocOutOfMem!SchedulerInstancePerThread {
        return SchedulerInstancePerThread{
            .allocator = allocator1,
            .readyQueue = try queue(*coroutine, .{}).init(allocator),
            .waitQueue = try queue(*coroutine, .{}).init(allocator),
        };
    }

    pub fn destroy(self: *Self) void {
        // also destroy the coroutine , probablly use it by the queue
        self.waitQueue.destroy();
        self.readyQueue.destroy();
    }
};

fn one(coro: *coroutine, scheduler: *Scheduler) void {
    // _ = coro;
    _ = scheduler;
    // const goTill: u64 = 15000;
    const goTill: u64 = 88;
    for (0..goTill) |i| {
        std.debug.print("[one] at index {d}\n", .{i});
        if (i % 12 == 0) {
            std.debug.print("[one] at index {d} and it is divisible by 12 so we are yielding\n", .{i});
            coro.yield();
        }
    }
    coro.coroutineState = .Finished;
    coro.yield();
}

fn two(coro: *coroutine, scheduler: *Scheduler) void {
    // _ = coro;
    _ = scheduler;
    // const goTill: u64 = 15000;
    const goTill: u64 = 88;
    for (0..goTill) |i| {
        std.debug.print("[two] at index {d}\n", .{i});
        if (i % 12 == 0) {
            std.debug.print("[two] at index {d} and it is divisible by 12 so we are yielding\n", .{i});
            coro.yield();
        }
    }
}
