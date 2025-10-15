const std = @import("std");
const builtin = @import("builtin");
const assert = @import("../utils/assert.zig");

pub const Error = error{
    StackTooSmall,
};
const ArchInfo = struct {
    num_registers: usize,
    jump_idx: usize,
    assembly: []const u8,
};

const archInfo: ArchInfo = switch (builtin.cpu.arch) {
    .aarch64 => .{
        .num_registers = 20,
        .jump_idx = 19,
        .assembly = @embedFile("../asm/aarch64.s"),
    },
    .x86_64 => switch (builtin.os.tag) {
        .windows => .{
            .num_registers = 32,
            .jump_idx = 30,
            .assembly = @embedFile("../asm/x86_64_windows.s"),
        },
        else => .{
            .num_registers = 8,
            .jump_idx = 6,
            .assembly = @embedFile("../asm/x86_64.s"),
        },
    },
    .riscv64 => .{
        .num_registers = 25,
        .jump_idx = 24,
        .assembly = @embedFile("../asm/riscv64.s"),
    },
    else => {
        @compileError("Unsupported cpu architecture");
    },
};

comptime {
    // asm (archInfo.assembly);
}

extern fn ziro_stack_swap(current: *anyopaque, target: *anyopaque) void;

pub const CoroutineState = enum { NotRunning, Waiting, Finished, Running, Completed, WaitingForChannel };

pub const Coroutine = struct {
    /// NOTE: keep this the first field as the assembly assumes(hardcoded) that you do if you not then you will get unknown error
    stack_pointer: [*]u8,
    stack: []u8,
    coroutineState: CoroutineState = .NotRunning,
    targetCoroutineToYieldTo: ?*Coroutine = null,

    caller_fn: ?*const fn (*anyopaque, *Coroutine) void = null, // Added *CoroutineBase param
    args_storage: [256]u8 align(8) = undefined,

    allocator: std.mem.Allocator,

    const Func = *const fn (
        from: *Coroutine,
        self: *Coroutine,
    ) callconv(.c) noreturn;

    const Self = @This();

    fn coroutineWrapper(from: *Coroutine, self: *Coroutine) callconv(.c) noreturn {
        self.coroutineState = .Running;
        self.targetCoroutineToYieldTo = from; // Set yield target automatically
        if (self.caller_fn) |caller| {
            caller(&self.args_storage, self); // Pass self to caller
        }
        self.coroutineState = .Finished;
        ziro_stack_swap(self, from);
        unreachable;
    }

    pub fn initWithFunc(comptime user_func: anytype, args: anytype, allocator: std.mem.Allocator, config: struct {
        stackAlignment: u8 = 16,
        /// for eg enter 1024 * 8 for 8KB, default is 5
        defaultStackSize: u16 = 1024 * 6,
    }) !Coroutine {
        if (@sizeOf(usize) != 8) @compileError("usize expected to take 8 bytes");
        if (@sizeOf(*Func) != 8) @compileError("function pointer expected to take 8 bytes");

        const ArgsType = @TypeOf(args);
        if (@sizeOf(ArgsType) > 256) {
            @compileError("Args too large, increase args_storage size");
        }
        var allocatedStack = try allocator.alloc(u8, config.defaultStackSize);

        errdefer allocator.free(allocatedStack);

        const register_bytes = archInfo.num_registers * 8;
        if (register_bytes > allocatedStack.len) return error.StackTooSmall;

        const register_space = allocatedStack[allocatedStack.len - register_bytes ..];

        const jump_ptr: *Func = @ptrCast(@alignCast(&register_space[archInfo.jump_idx * 8]));
        jump_ptr.* = coroutineWrapper;

        const Caller = struct {
            fn call(args_ptr: *anyopaque, coro: *Coroutine) void {
                const typed_args = @as(*ArgsType, @ptrCast(@alignCast(args_ptr)));
                // Prepend coro to the args tuple
                const new_args = .{coro} ++ typed_args.*;
                _ = @call(.auto, user_func, new_args);
            }
        };

        // where the fuck should I store the allocated stack and what is it's use, look into the previous one(stack allocating coro's stack on github)
        var result = Coroutine{
            .stack_pointer = register_space.ptr,
            .caller_fn = Caller.call,
            .stack = allocatedStack,
            .allocator = allocator,
        };

        const args_bytes = std.mem.asBytes(&args);
        @memcpy(result.args_storage[0..args_bytes.len], args_bytes);
        return result;
    }

    pub fn destroy(self: *Coroutine) void {
        assert.assertWithMessage(self.coroutineState != .Running, "attempted to destroy a coroutine while it is running\n");
        self.allocator.free(self.stack);
        self.coroutineState = .Completed;
    }

    pub inline fn resumeFrom(self: *Coroutine, from: *Coroutine) void {
        return ziro_stack_swap(from, self);
    }

    pub fn yield(self: *@This()) void {
        if (self.targetCoroutineToYieldTo) |target| {
            self.coroutineState = .Waiting;
            ziro_stack_swap(self, target);
        }
    }
};
//
// this lib will provide(not this , I am talking about the lib as a whole), 2 fn go(Fn) and goRunCoro(Fn)- the go is like
// the golang one while the goRunCoro will take in a fn and that fn should take in the argument Corotine type as I want to allow
// the fn to pasue or resume later
//
// now the thing is that we have too keep track of the state so as we do not want to call the resume on it
// 1) we can make the fn explicitly handle the state management
// 2) we can take in the fn and then put it in another fn and when the fn(original) is over then we can in the end put the
//  state to be done (enum)
//
//  -- make sure the coroutine heap allocates
//  --- next is the scheduler --
//
// you know instead of making a seperate yield and resume we can, just keep it and in the scheduler we can
// call other if it is not there then go to main
//
//
