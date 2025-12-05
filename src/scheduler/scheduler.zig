const std = @import("std");
// const coroutine = @import("ZigConcurrency").Coroutine;
const coroutine = @import("../coroutine/coroutine.zig").Coroutine;
const util = @import("../utils/typeChecking.zig");
const queue = @import("../utils/queue.zig").ThreadSafeQueue;
const libxev = @import("xev");
const Allocator = std.mem.Allocator;
const AllocOutOfMemErr = Allocator.Error;
const asserts = @import("../utils/assert.zig");
const assertWithMessage = asserts.assertWithMessageFmt;
const assertWithRuntimeMessage = asserts.assertWithMessageFmtRuntime;
const SchedulerInstancePerThread = @import("./SchedulerInstancePerThread.zig").SchedulerInstancePerThread;
const SchedulerInstancePerThreadMod = @import("./SchedulerInstancePerThread.zig");
const SchedulerThreadInstanceArray = @import("./SchedulerThreadInstanceArray.zig").SchedulerThreadInstanceArray;

pub const InitError = AllocOutOfMemErr || std.Thread.SpawnError;

pub const Scheduler = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    globalRunQueue: queue(*coroutine),
    idleQueue: SchedulerThreadInstanceArray,
    runningQueue: SchedulerThreadInstanceArray,
    schedulerInstanceSleepingLock: std.Thread.Mutex = std.Thread.Mutex{},
    SchedulerInstancesOnThreads: []*SchedulerInstancePerThread,

    pub fn init(allocatorArg: std.mem.Allocator, comptime options: struct { defualtGlobalRunQueueSize: u64 = 650 }) InitError!*Scheduler {
        const cpuCoreCount = std.Thread.getCpuCount() catch |err| bkl: {
            const defualtCpuAssumption: u32 = 1;
            std.debug.print("\n\n[WARN] error in gettting the no of cpus:{s} instead defaulting to {d}\n\n", .{ @errorName(err), defualtCpuAssumption });
            break :bkl defualtCpuAssumption;
        };
        std.debug.print("== in the init and the selfRef is {?}\n", .{SchedulerInstancePerThreadMod.getSelfRef()});
        std.debug.print("== in the init and the selfRef is {?}\n", .{SchedulerInstancePerThreadMod.getSelfRef()});
        std.debug.print("1\n", .{});
        const coreCount: u32 = @intCast(cpuCoreCount);
        var scheduler = try allocatorArg.create(Scheduler);
        scheduler.* = Scheduler{
            .allocator = allocatorArg,
            .globalRunQueue = try queue(*coroutine).init(allocatorArg, .{ .listSize = options.defualtGlobalRunQueueSize }),
            .idleQueue = try SchedulerThreadInstanceArray.init(allocatorArg, coreCount),
            .runningQueue = try SchedulerThreadInstanceArray.init(allocatorArg, coreCount),
            .schedulerInstanceSleepingLock = std.Thread.Mutex{},
            .SchedulerInstancesOnThreads = try allocatorArg.alloc(*SchedulerInstancePerThread, cpuCoreCount),
        };
        std.debug.print("2\n", .{});
        //
        //
        //maybe we shoule have the mutex lock in that array too, or may be we should first create/alloc them and then run them in the loop, 2 loop
        //
        //
        for (0..cpuCoreCount) |value| {
            var schedulerInstance = try allocatorArg.create(SchedulerInstancePerThread);
            schedulerInstance.* = try SchedulerInstancePerThread.init(allocatorArg, scheduler, @intCast(value));
            schedulerInstance.SchedulerInstanceId = @intCast(value);
            // add it to the scheduler's queue
            scheduler.runningQueue.arr[value] = schedulerInstance;
            scheduler.SchedulerInstancesOnThreads[value] = schedulerInstance;
        }

        for (0..cpuCoreCount) |i| {
            const thread = try std.Thread.spawn(.{}, SchedulerInstancePerThread.run, .{scheduler.SchedulerInstancesOnThreads[i]});
            thread.detach();
        }
        std.debug.print("3\n", .{});
        return scheduler;
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
    }) AllocOutOfMemErr!void {
        // this fn will take in a fn and convert it into a coroutine and store it somewhere(global run queue etc)
        // ok here is a quick and dirty version of the scheduler just take in the struct that has the fn and atis args as a array and then convert them into coro
        // and start executing them, if one of them yield then I want you to take the next one and start executing it  until the state is finnished
        if (options.skipTypeChecking == false) {
            const typeIsCorrect = comptime util.validateArgsMatchFunction(Fn, fnArgs, options.typeToSkipInChecking);
            if (!typeIsCorrect) @compileError("there is a type mismatch between the fn and the parameter type in the args provided");
        }
        const coro = coroutine.init(Fn, fnArgs, self.allocator, .{}) catch |err| switch (err) {
            coroutine.err.OutOfMemory => return AllocOutOfMemErr.OutOfMemory,
            coroutine.err.StackTooSmall => @panic("the stack size of coroutine for the fn is small\n"),
        };
        //
        //
        //
        // here is a optimization, before putting it in the global run queue, lock and see if there is still a SchedulerInstancePerThread in idle queue if there is then put it
        // there and notify it,
        // if no one is there then take the cost and put it in the global run queue
        //
        //
        //
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
