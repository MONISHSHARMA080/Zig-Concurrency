const std = @import("std");
// const coroutine = @import("ZigConcurrency").Coroutine;
const coroutine = @import("../coroutine/coroutine.zig").Coroutine;
const util = @import("../utils/typeChecking.zig");
const queue = @import("../utils/queue.zig").ThreadSafeQueue;
const libxev = @import("xev");
const allocator = std.mem.Allocator;
const allocOutOfMem = allocator.Error;
//
//probelm: how do we integrate the runtime here, like when the
//
//todo: 1st we need to design the schedulerInstanceOnThread, then we need to make the libxev loop in there running
//

pub const Scheduler = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    schedulerInstanceOnThread: ?SchedulerInstancePerThread,
    globalRunQueue: queue(*coroutine, .{ .listSize = 650 }),

    // globalRunQueue: ?std.ArrayList(*coroutine),

    pub fn init(allocatorArg: std.mem.Allocator, comptime options: struct { defualtGlobalRunQueueSize: u64 = 650 }) std.mem.Allocator.Error!Scheduler {
        return Scheduler{ .allocator = allocatorArg, .schedulerInstanceOnThread = null, .globalRunQueue = try queue(*coroutine, .{ .listSize = options.defualtGlobalRunQueueSize }).init(allocatorArg) };
    }

    /// impl it
    pub fn destroy(self: *Scheduler) void {
        // self.globalRunQueue.
        // destroy the coroutines in the fn first from the queue and then the destroy of queue, or we can give the queue
        // a comptime method name and tell it to call it while freeing
        _ = self;
    }

    // fn simulaterun(self: *Scheduler) !void {
    //     const readyQueue = try queue(*coroutine, .{}).init(self.allocator);
    //     const waitingQueue = try queue(*coroutine, .{}).init(self.allocator);
    //     //loop
    //     //inside the loop first thing we  do is check for the coroutine's sys call completion : libxev not impl
    //     //then we take the coroutine out of the loop and run them
    // }

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

        // now since the coroutine is in the Global run queue, now we need to wake up the threads instance if they are sleeping or smth(naive approach), optimization may be
        // to add some atomics, as sys call in every go() will kill performance

        // now use the libxev for the sys call completion check and the loop in the thread for the coroutines to execute, and if none wait on the conditional var or futex etc

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
        return;
    }
};

const SchedulerInstancePerThread = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    readyQueue: queue(*coroutine, .{ .listSize = 100 }),
    waitQueue: queue(*coroutine, .{ .listSize = 100 }),
    /// [the SchedulerInstance has completed the work and no other work is to be found and when we get one in the queue then wake it up]
    wakeMeUpWhenWorkArrives: std.atomic.Value(bool).init(false),

    const Self = @This();

    pub fn run(self: *SchedulerInstancePerThread) !void {
        _ = self;
        while (true) {
            //[1st] check is the sys calls are completed,using libxev and make coro as runnable : Not implemented
            //[2nd] check the local run queue, is coro then run it
            //[3rd] check the global run queue, is coro then run it
            //[4th] try work stealing
            //[5th] if both are not there and also not one waiting in the waitingQueue then wait on a futex or conditional var
            if (getWorkOrNull()) |coro| {
                // run it
            } else {
                // wait
            }
        }
    }

    /// gets work form 1>readyQueue 2> globalRunQueue 3> work stealing; if still none then return null
    fn getWorkOrNull(self: *Self) ?*coroutine {
        _ = self;
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

//
//
// ok like this is how I will use it, Scheduler{} and then a fn work(scheduler:Scheduler){
//  a();
//  b(); // now I want to yield
//  scheduler.yield();
// }
// now the thing is that if the fn is running then I can't call the yield via scheduler, instead I need to expose the coroutine struct and then allow it to call yield;
// or we can use some fn magic(ziro_stack_swap, form the coro->SchedulerInstanceOnThread.yield(){ziro_stack_swap}) to do this too, prefer the 2nd option
//
