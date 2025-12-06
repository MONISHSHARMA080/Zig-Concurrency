const std = @import("std");
const coroutine = @import("../coroutine/coroutine.zig").Coroutine;
const util = @import("../utils/typeChecking.zig");
const queue = @import("../utils/queue.zig").ThreadSafeQueue;
const Scheduler = @import("../scheduler/scheduler.zig").Scheduler;
const InitError = @import("../scheduler/scheduler.zig").InitError;
const SchedulerInstancePerThread = @import("../scheduler/SchedulerInstancePerThread.zig").SchedulerInstancePerThread;
const SchedulerInstancePerThreadLib = @import("../scheduler/SchedulerInstancePerThread.zig");
const libxev = @import("xev");
const Allocator = std.mem.Allocator;
const allocOutOfMem = Allocator.Error;
const asserts = @import("../utils/assert.zig");
const assertWithMessage = asserts.assertWithMessage;
const assert = std.debug.assert;

// we will also have a runtime lib for the sys calls and stuff

pub const Runtime = struct {
    scheduler: Scheduler,
    allocator: Allocator,

    const Self = *@This();
    pub fn init(self: Self, allocator: Allocator) InitError!void {
        // start the scheduler,
        self.allocator = allocator;
        self.scheduler = try Scheduler.init(allocator, .{});
    }
    pub fn spawnNew(self: Self, comptime Fn: anytype, comptime fnArgs: anytype, options: struct {
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
};
