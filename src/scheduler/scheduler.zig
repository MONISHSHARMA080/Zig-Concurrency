const std = @import("std");
// const coroutine = @import("ZigConcurrency").Coroutine;
const coroutine = @import("../coroutine/coroutine.zig").Coroutine;
const util = @import("../utils/typeChecking.zig");
//
//probelm: how do we integrate the runtime here, like when the
//
//todo: 1st we need to design the schedulerInstanceOnThread, then we need to make the libxev loop in there running
//
//
//
//

pub const Scheduler = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    schedulerInstanceOnThread: ?SchedulerInstancePerThread,
    globalRunQueue: std.ArrayList(*coroutine),

    pub fn init(allocator: std.mem.Allocator, options: struct { defualtGlobalRunQueueSize: u64 = 600 }) std.mem.Allocator.Error!Scheduler {
        return Scheduler{ .allocator = allocator, .schedulerInstanceOnThread = null, .globalRunQueue = try std.ArrayList(*coroutine).initCapacity(allocator, options.defualtGlobalRunQueueSize) };
    }

    pub fn destroy(self: *Scheduler) void {
        self.globalRunQueue.deinit(self.allocator);
    }

    pub fn go(self: *Scheduler, comptime Fn: anytype, comptime fnArgs: anytype, options: struct {
        /// if there are 2 same types of the param then you need to provide their type 2 times as we will only skip for one type in the array once
        typeToSkipInChecking: ?[]const type = &[_]type{*coroutine},
        skipTypeChecking: bool = false,
    }) void {
        // this fn will take in a fn and convert it into a coroutine and store it somewhere(global run queue etc)

        // ok here is a quick and dirty version of the scheduler just take in the struct that has the fn and atis args as a array and then convert them into coro
        // and start executing them, if one of them yield then I want you to take the next one and start executing it  until the state is finnished
        //
        // just hardcode some fn here and make them start
        //

        if (options.skipTypeChecking == false) {
            const typeIsCorrect = comptime util.validateArgsMatchFunction(Fn, fnArgs, options.typeToSkipInChecking);
            if (!typeIsCorrect) @compileError("there is a type mismatch between the fn and the parameter type in the args provided");
        }
        const coro = coroutine.init(Fn, fnArgs, self.allocator, .{}) catch unreachable;
        self.globalRunQueue.append(self.allocator, coro) catch unreachable;
        // self.globalRunQueue.print(self.allocator, "the global run queue is \n", .{}) catch unreachable;

        var coro1 = coroutine.init(&one, .{self}, self.allocator, .{}) catch unreachable;
        var coro2 = coroutine.init(&two, .{self}, self.allocator, .{}) catch unreachable;
        defer coro1.destroy();
        defer coro2.destroy();
        var main_coro: coroutine = .{
            .stack = &[_]u8{},
            .stack_pointer = undefined,
            .allocator = undefined,
        };
        // defer main_coro.destroy();
        std.debug.print("in the scheduler's go fn\n", .{});
        coro1.targetCoroutineToYieldTo = &main_coro;
        coro2.targetCoroutineToYieldTo = &main_coro;

        while (coro1.coroutineState != .Finished or coro2.coroutineState != .Finished) {
            // Run coro1 if not finished
            if (coro1.coroutineState != .Finished) {
                std.debug.print("[Scheduler loop] starting coro1\n", .{});
                // coro1.startFrom(&main_coro);
                coro1.startRunning();
                std.debug.print("[Scheduler loop] coro1 has yielded\n", .{});
            }

            // Run coro2 if not finished
            if (coro2.coroutineState != .Finished) {
                std.debug.print("[Scheduler loop] starting coro2\n", .{});
                coro2.startRunning();
                std.debug.print("[Scheduler loop] coro2 has yielded\n", .{});
            }
        }

        std.debug.print("[Scheduler] Both coroutines finished!\n", .{});
        return;
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

const SchedulerInstancePerThread = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    const FnToExecute = *const fn (userData: anyopaque) void;

    pub fn go(fnToExecute: FnToExecute) void {
        fnToExecute();
        return;
    }
    pub fn yield() void {
        // now to yield back to the Scheduler make a coroutine in the loop that is undefined and start from there
    }
};

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
//
//
//
//
