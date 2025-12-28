const std = @import("std");
const coroutine = @import("../coroutine/coroutine.zig").Coroutine;
const util = @import("../utils/typeChecking.zig");
const queue = @import("../utils/queue.zig").ThreadSafeQueue;
const Scheduler = @import("../scheduler/scheduler.zig").Scheduler;
const InitError = @import("../scheduler/scheduler.zig").InitError;
const SchedulerInstancePerThread = @import("../scheduler/SchedulerInstancePerThread.zig").SchedulerInstancePerThread;
const SchedulerInstancePerThreadLib = @import("../scheduler/SchedulerInstancePerThread.zig");
const getAnyScheduler = SchedulerInstancePerThreadLib.getSelfRef;
const libxev = @import("xev");
const Allocator = std.mem.Allocator;
const allocOutOfMem = Allocator.Error;
const asserts = @import("../utils/assert.zig");
const assertWithMessage = asserts.assertWithMessage;
const assert = std.debug.assert;
const aio = @import("aio");

// --------------------------------
// for the lib stuff we can do it in a file and then here we can do the shovel work, like make a net lib and here give then pub const net = @import("net.zig")
// make the lib take the coro ref
// --------------------------------

pub const Runtime = struct {
    scheduler: Scheduler,
    allocator: Allocator,

    const Self = @This();
    pub fn init(self: Self, allocator: Allocator) InitError!void {
        // start the scheduler,
        self.allocator = allocator;
        self.scheduler = try Scheduler.init(allocator, .{});
    }
    pub fn spawnNew(self: *Self, comptime Fn: anytype, comptime fnArgs: anytype, options: struct {
        /// if there are 2 same types of the param then you need to provide their type 2 times as we will only skip for one type in the array once
        typeToSkipInChecking: ?[]const type = &[_]type{*coroutine},
        skipTypeChecking: bool = false,
    }) allocOutOfMem!void {
        _ = self;
        if (options.skipTypeChecking == false) {
            const typeIsCorrect = comptime util.validateArgsMatchFunction(Fn, fnArgs, options.typeToSkipInChecking);
            if (!typeIsCorrect) @compileError("there is a type mismatch between the fn and the parameter type in the args provided");
        }
        const selfRef = SchedulerInstancePerThreadLib.getSelfRef();
        switch (selfRef.*) {
            .scheduler => |sch| {
                sch.?.go(Fn, fnArgs, options);
            },
            .schedulerInstancePerThread => |sch| {
                sch.?.go(Fn, fnArgs, options);
            },
        }
    }

    pub inline fn submitWork(self: *Self, coro: *coroutine, work: *aio.Completion) void {
        _ = self;
        // maybe to give runtime access to the coroutine , for that in the schedulerInstance when we pop out the coro set it as a value in the runtime or in the
        // getAnyScheduler() 's tagged union make it into a struct that also has a coro field
        const scheduler = getAnyScheduler();
        switch (scheduler.*) {
            .scheduler => {
                @panic("in submitWork() trying to submit work to the schedulerInstancePerThread but instead got the scheduler instead \n");
            },
            .schedulerInstancePerThread => |schedulerInstance| {
                schedulerInstance.?.submitWork(coro, work);
            },
        }
    }
};
