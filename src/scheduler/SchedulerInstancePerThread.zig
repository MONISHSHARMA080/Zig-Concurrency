const std = @import("std");
const coroutine = @import("../coroutine/coroutine.zig").Coroutine;
const util = @import("../utils/typeChecking.zig");
const queue = @import("../utils/queue.zig").ThreadSafeQueue;
const Scheduler = @import("./scheduler.zig").Scheduler;
const Allocator = std.mem.Allocator;
const allocOutOfMem = Allocator.Error;
const asserts = @import("../utils/assert.zig");
const assertWithMessage = asserts.assertWithMessage;
const assert = std.debug.assert;
const aio = @import("aio");

pub const ReferenceToScheduler = union(enum) {
    schedulerInstancePerThread: ?*SchedulerInstancePerThread,
    scheduler: ?*Scheduler,
};
pub threadlocal var SelfRef: ReferenceToScheduler = .{ .schedulerInstancePerThread = null };

pub fn isRefToSchedulerValid(refToScheduler: *ReferenceToScheduler, returnType: type) returnType {
    asserts.assertWithMessageFmtCompileTime(returnType == bool or returnType == void, "only bool or void as return types are allowed\n", .{});
    switch (returnType) {
        bool => {
            switch (refToScheduler.*) {
                .scheduler => |sch| if (sch == null) return false else return true,
                .schedulerInstancePerThread => |sch| if (sch == null) return false else return true,
            }
        },
        void => {
            // if (refToScheduler.scheduler != null or refToScheduler.schedulerInstancePerThread != null) return else @panic("only bool or void as return types are allowed\n");
            switch (refToScheduler.*) {
                .scheduler => |sch| if (sch == null) @panic(" the active field on the SelfRef, thread local var is null \n") else return,
                .schedulerInstancePerThread => |sch| if (sch == null) @panic(" the active field on the SelfRef, thread local var is null \n") else return,
            }
        },
        else => unreachable,
    }
}
pub fn getSelfRef() *ReferenceToScheduler {
    return &SelfRef;
}

pub fn setSelfRef(ref: ReferenceToScheduler) void {
    const selfRef = getSelfRef();
    selfRef.* = ref;
    isRefToSchedulerValid(&SelfRef, void);
}

pub const SchedulerInstancePerThread = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    parentScheduler: *Scheduler,
    readyQueue: queue(*coroutine),
    waitQueue: queue(*coroutine),
    // wakeMeUpWhenWorkArrives: std.atomic.Value(bool)= std.atomic.Value(bool).init(false),
    SchedulerInstanceId: u32,
    /// [the SchedulerInstance has completed the work and no other work is to be found and when we get one in the queue then wake it up]
    futex: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    loop: aio.Loop = undefined,
    const SpinLimit = 900;
    const Self = @This();

    /// think about it this var shouldn't be null, like if this is null then I make a programming mistake,
    pub fn init(allocator1: Allocator, parentScheduler: *Scheduler, id: u32) allocOutOfMem!SchedulerInstancePerThread {
        var a: aio.Loop = undefined;
        a.init(.{ .allocator = allocator1 }) catch |err| std.debug.panic("got a error while initing aio.loop -> {s} \n", .{@errorName(err)});
        return SchedulerInstancePerThread{
            .allocator = allocator1,
            .readyQueue = try queue(*coroutine).init(allocator1, .{}),
            .waitQueue = try queue(*coroutine).init(allocator1, .{}),
            .parentScheduler = parentScheduler,
            .SchedulerInstanceId = id,
            .loop = a,
        };
    }
    /// notify the scheduler that the work is there and wake the thread up
    pub fn notify(self: *Self) void {
        _ = self.futex.fetchAdd(1, .release);
        // 2. Wake the thread if it is sleeping
        std.Thread.Futex.wake(&self.futex, 1);
    }

    pub fn go(self: *Self, comptime Fn: anytype, comptime fnArgs: anytype, options: struct {
        /// if there are 2 same types of the param then you need to provide their type 2 times as we will only skip for one type in the array once
        typeToSkipInChecking: ?[]const type = &[_]type{*coroutine},
        skipTypeChecking: bool = false,
    }) allocOutOfMem!void {

        // this fn will take in a fn and convert it into a coroutine and store it somewhere(global run queue etc)
        // ok here is a quick and dirty version of the scheduler just take in the struct that has the fn and atis args as a array and then convert them into coro
        // and start executing them, if one of them yield then I want you to take the next one and start executing it  until the state is finnished
        if (options.skipTypeChecking == false) {
            const typeIsCorrect = comptime util.validateArgsMatchFunction(Fn, fnArgs, options.typeToSkipInChecking);
            if (!typeIsCorrect) @compileError("there is a type mismatch between the fn and the parameter type in the args provided");
        }
        const coro = coroutine.init(Fn, fnArgs, self.allocator, .{}) catch |err| switch (err) {
            coroutine.err.OutOfMemory => return allocOutOfMem.OutOfMemory,
            coroutine.err.StackTooSmall => @panic("the stack size of coroutine for the fn is small\n"),
        };
        try self.readyQueue.put(coro);
        return;
    }

    inline fn park(self: *Self) ?*coroutine {
        // [B] Snapshot the current state of the futex
        // This is the 'ticket' we use to safely enter the wait state.
        const ticket = self.futex.load(.monotonic);
        // [C] Spinning Phase: Try to find work again without syscalls
        // Double-check for work after setting futex
        // (prevents race condition where work arrives between check and wait)
        std.debug.print("in SchedulerInstance:{d} we are park() and trying to spin it one last time and park it \n", .{self.SchedulerInstanceId});
        for (0..12) |i| {
            // _ = i;
            std.debug.print("in SchedulerInstance:{d} and at index {d} \n", .{ self.SchedulerInstanceId, i });
            std.atomic.spinLoopHint();
            if (self.getWorkOrNull()) |coro| {
                std.debug.print("in SchedulerInstance:{d} we are putting it on wait(futex)\n", .{self.SchedulerInstanceId});
                return coro;
            }
            // std.debug.print("in SchedulerInstance:{d} we are putting it on wait(futex)\n", .{self.SchedulerInstanceId});
        }
        // [D] Sleep Phase: No work after spinning. Commit to kernel wait.
        // We pass the 'ticket' grabbed at [B].
        // If self.futex is STILL 'ticket', the OS puts us to sleep.
        // If self.futex is != 'ticket' (someone pushed work), we return immediately.
        std.debug.print("in SchedulerInstance:{d} we are putting it on wait(futex)\n", .{self.SchedulerInstanceId});
        self.parentScheduler.registerIdle(self);
        std.Thread.Futex.wait(&self.futex, ticket);
        self.parentScheduler.deRegisterIdle(self);

        return null;
    }

    pub fn run(self: *SchedulerInstancePerThread) !void {
        var coroToRunOther: coroutine = .{
            .stack = &[_]u8{},
            .stack_pointer = undefined,
            .allocator = undefined,
        };
        SelfRef = .{ .schedulerInstancePerThread = self };
        while (true) {
            //[1st] check is the sys calls are completed,using libxev and make coro as runnable : Not implemented
            //[2nd] check the local run queue, is coro then run it
            //[3rd] check the global run queue, is coro then run it
            //[4th] try work stealing
            //[5th] if both are not there and also not one waiting in the waitingQueue then wait on a futex or conditional var

            // from llm research what it seems the https://github.com/lalinsky/aio.zig seems like a better lib for the sys calls completion
            // I will need to implement the network, filesystem etc and that is too much work instead I should rather use something like zio
            //https://claude.ai/chat/7eca2f0c-a847-4159-8972-54b052839136

            // we could use this in a abstract way, like in the schedulerInstance fn we can accept a completion and a *coro, and there we can make the
            // callback = as generic and when the callback fires we can just wake it up and schedulerInstance, and the coro will give us the op(like FileRead)
            // and call yield on itself(or we can do it too), and when the coro wakes up then it can get the result using the getResult
            //
            // const op = aio.FileRead.init(0, .{ .iovecs = undefined }, 0);
            // op.c.userdata = Coroutine;
            // op.c.callback = undefined;
            // loop.add(&op.c);
            // try op.c.op.toType();
            // const x = op.getResult() catch unreachable;

            const coroToRun: *coroutine = blk: {
                if (self.getWorkOrNull()) |coro| {
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
        } else if (self.workStealingAndPutItInRunQueue()) |stolenCoro| {
            return stolenCoro;
        } else if (self.parentScheduler.globalRunQueue.pop()) |coroInGlobalRunQueue| {
            return coroInGlobalRunQueue;
        } else {
            return null;
        }
    }

    /// returns true if found the work
    fn workStealingAndPutItInRunQueue(self: *Self) ?*coroutine {
        // go to other schedulerInstanceOnThread and try to see if they have coro in the readyQueue, if yes then get it
        for (self.parentScheduler.SchedulerInstancesOnThreads) |schedulerInstance| {
            if (schedulerInstance.SchedulerInstanceId == self.SchedulerInstanceId) continue;
            const coro = schedulerInstance.readyQueue.pop();
            if (coro) |c| return c else continue;
        }
        return null;
    }

    pub fn destroy(self: *Self) void {
        // also destroy the coroutine , probablly use it by the queue
        self.waitQueue.destroy();
        self.readyQueue.destroy();
        self.loop.deinit();
    }
};
